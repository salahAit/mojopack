from std.collections import Span
from std.io.file import open
from std.os import listdir
from std.os.path import isdir, isfile, join, basename, dirname, exists
from std.os.fstat import stat
from std.time import perf_counter_ns
from std.origin import MutUntrackedOrigin
from std.ffi import external_call
from mojopack.container import FileMetadata, ContainerUtils, ArchiveWriter, ArchiveReader
from mojopack.pipeline import Pipeline
from mojopack.compressor import Decompressor, ChunkMode
from mojopack.checksum import XXH3_64

@always_inline
def to_c_str(s: String) -> List[UInt8]:
    var b = s.as_bytes()
    var l = List[UInt8](capacity=len(b) + 1)
    for i in range(len(b)):
        l.append(b[i])
    l.append(0)
    return l^

@always_inline
def posix_open(path: String, flags: Int32, mode: UInt32 = 0o644) -> Int32:
    var c_str = to_c_str(path)
    # Use openat(-100 / AT_FDCWD) to avoid signature conflict with Mojo stdlib's open
    return external_call["openat", Int32](Int32(-100), c_str.unsafe_ptr(), flags, mode)

struct CLI:
    @staticmethod
    def print_version():
        print("MojoPack (mpack) v1.0.0 (x86_64-linux)")
        print("Pure Mojo High-Performance Lossless Archiver")
        print("Copyright (c) 2026 Salah AIT AMOKRANE. Released under MIT License.")

    @staticmethod
    def print_usage():
        print("MojoPack (mpack) v1.0.0 - Ultra-Fast Modern File Archiver in Mojo")
        print("Usage:")
        print("  mpack c [-1|-9] <archive.mpk> <path...>  Create archive (-1 fast, -9 ultra)")
        print("  mpack x <archive.mpk> [-o <dest_dir>]    Extract archive")
        print("  mpack l <archive.mpk>                   List archive contents")
        print("  mpack t <archive.mpk>                   Test archive integrity")
        print("  mpack b <path>                          Benchmark compression on file/dir")
        print("  mpack -v, --version                     Print version information")
        print("  mpack -h, --help                        Print this help message")

    @staticmethod
    def collect_files(paths: List[String]) raises -> List[String]:
        var files = List[String]()
        for i in range(len(paths)):
            var p = paths[i]
            if isfile(p):
                files.append(p)
            elif isdir(p):
                var stack = List[String]()
                stack.append(p)
                while len(stack) > 0:
                    var curr = stack.pop()
                    var entries = listdir(curr)
                    for j in range(len(entries)):
                        var child = join(curr, entries[j])
                        if isdir(child):
                            stack.append(child)
                        elif isfile(child):
                            files.append(child)
        return files^

    @staticmethod
    def create(archive_path: String, input_paths: List[String], level: Int = 1) raises:
        var t0 = perf_counter_ns()
        var file_paths = Self.collect_files(input_paths)
        if len(file_paths) == 0:
            print("Warning: No files found to archive.")
            return

        var writer = ArchiveWriter()
        var num_files = len(file_paths)

        # Pass 1: Fast metadata sizing pass
        var total_uncompressed_bytes = 0
        var file_sizes = List[Int](capacity=num_files)
        var file_modes = List[UInt32](capacity=num_files)
        var file_mtimes = List[UInt64](capacity=num_files)

        for i in range(num_files):
            var fp = file_paths[i]
            var st = stat(fp)
            var sz = Int(st.st_size)
            file_sizes.append(sz)
            file_modes.append(UInt32(st.st_mode))
            file_mtimes.append(UInt64(st.st_mtimespec.tv_sec))
            total_uncompressed_bytes += sz

        # Pass 2: Pre-allocate solid buffer once
        var solid_stream = List[UInt8](capacity=total_uncompressed_bytes)
        for _ in range(total_uncompressed_bytes):
            solid_stream.append(0)

        var solid_ptr = Pointer[UInt8, MutUntrackedOrigin](unsafe_from_address=Int(solid_stream.unsafe_ptr()))
        var curr_offset = 0

        print("Packaging " + String(num_files) + " files into solid stream...")
        for i in range(num_files):
            var fp = file_paths[i]
            var sz = file_sizes[i]
            if sz > 0:
                var fd = posix_open(fp, 0, 0)
                if fd >= 0:
                    var dest_ptr = solid_ptr.unsafe_offset(curr_offset)
                    var read_total = 0
                    while read_total < sz:
                        var n = external_call["read", Int](Int(fd), dest_ptr.unsafe_offset(read_total), sz - read_total)
                        if n <= 0:
                            break
                        read_total += n
                    _ = external_call["close", Int32](fd)

            var clean_path = ContainerUtils.sanitize_path(fp)
            writer.add_entry(FileMetadata(clean_path, sz, curr_offset, file_modes[i], file_mtimes[i]))
            curr_offset += sz

        print("Compressing solid stream (" + String(total_uncompressed_bytes) + " bytes) at level -" + String(level) + "...")
        var pipeline = Pipeline(level=level)
        var chunks = pipeline.compress_stream(Span[UInt8](solid_stream))

        for i in range(len(chunks)):
            var c = chunks[i].copy()
            writer.add_chunk(c^)

        writer.write_to_file(archive_path)
        var t1 = perf_counter_ns()
        var elapsed = Float64(t1 - t0) / 1000000000.0

        var arch_stat = stat(archive_path)
        var comp_size = arch_stat.st_size
        var ratio = (Float64(comp_size) / Float64(max(total_uncompressed_bytes, 1))) * 100.0
        var speed_mb = (Float64(total_uncompressed_bytes) / (1024.0 * 1024.0)) / max(elapsed, 0.000001)

        print("Created archive: " + archive_path)
        print("  Files:           " + String(len(file_paths)))
        print("  Original Size:   " + String(total_uncompressed_bytes) + " bytes")
        print("  Archive Size:    " + String(comp_size) + " bytes (" + String(ratio) + "%)")
        print("  Chunks:          " + String(len(chunks)))
        print("  Time Elapsed:    " + String(elapsed) + " s (" + String(speed_mb) + " MB/s)")

    @staticmethod
    def extract(archive_path: String, dest_dir: String = ".") raises:
        var t0 = perf_counter_ns()
        print("Opening archive: " + archive_path)
        var reader = ArchiveReader(archive_path)
        print("Decompressing solid stream (" + String(reader.num_chunks) + " chunks)...")
        var solid_bytes = reader.decompress_solid_stream()

        print("Extracting " + String(len(reader.entries)) + " files to " + dest_dir + "...")
        ContainerUtils.ensure_dir(dest_dir)

        var total_bytes = 0
        for i in range(len(reader.entries)):
            ref ent = reader.entries[i]
            var out_path = join(dest_dir, ent.path) if dest_dir != "." else ent.path
            
            # Ensure parent directories exist
            var parent_dir = dirname(out_path)
            if parent_dir != "" and parent_dir != ".":
                ContainerUtils.ensure_dir(parent_dir)

            var solid_ptr = Pointer[UInt8, MutUntrackedOrigin](unsafe_from_address=Int(solid_bytes.unsafe_ptr()))
            var out_fd = posix_open(out_path, 577, UInt32(0o755 if ent.mode != 0 else 0o644))
            if out_fd >= 0:
                var src_ptr = solid_ptr.unsafe_offset(ent.solid_offset)
                var to_write = ent.size
                var written = 0
                while written < to_write:
                    var n = external_call["write", Int](Int(out_fd), src_ptr.unsafe_offset(written), to_write - written)
                    if n <= 0:
                        break
                    written += n
                _ = external_call["close", Int32](out_fd)

            if ent.mode != 0:
                var c_out = to_c_str(out_path)
                _ = external_call["chmod", Int32](c_out.unsafe_ptr(), UInt32(ent.mode))

            total_bytes += ent.size

        var t1 = perf_counter_ns()
        var elapsed = Float64(t1 - t0) / 1000000000.0
        var speed_mb = (Float64(total_bytes) / (1024.0 * 1024.0)) / max(elapsed, 0.000001)
        print("Extraction complete: " + String(len(reader.entries)) + " files (" + String(total_bytes) + " bytes)")
        print("  Time Elapsed: " + String(elapsed) + " s (" + String(speed_mb) + " MB/s)")

    @staticmethod
    def list_contents(archive_path: String) raises:
        var reader = ArchiveReader(archive_path)
        print("Archive: " + archive_path)
        print("Chunks:  " + String(reader.num_chunks))
        print("----------------------------------------------------------------------")
        print("Mode       Size (Bytes)   Solid Offset   Path")
        print("----------------------------------------------------------------------")

        var total_size = 0
        for i in range(len(reader.entries)):
            ref ent = reader.entries[i]
            print(hex(ent.mode) + "   " + String(ent.size) + " \t  " + String(ent.solid_offset) + " \t " + ent.path)
            total_size += ent.size

        print("----------------------------------------------------------------------")
        print("Total Files: " + String(len(reader.entries)) + " | Total Size: " + String(total_size) + " bytes")

    @staticmethod
    def test_integrity(archive_path: String) raises:
        var t0 = perf_counter_ns()
        print("Testing integrity: " + archive_path)
        var reader = ArchiveReader(archive_path)
        var all_ok = True
        try:
            _ = reader.decompress_solid_stream()
        except e:
            print("FAILED: " + String(e))
            all_ok = False

        var t1 = perf_counter_ns()
        var elapsed = Float64(t1 - t0) / 1000000000.0
        if all_ok:
            print("Archive integrity verification: OK (" + String(reader.num_chunks) + " chunks verified in " + String(elapsed) + " s)")
        else:
            print("Archive integrity verification: CORRUPTED")

    @staticmethod
    def benchmark(target_path: String) raises:
        print("=== MojoPack High-Performance Archiver Benchmark ===")
        var file_paths = Self.collect_files([target_path])
        if len(file_paths) == 0:
            print("Error: Target path not found or empty.")
            return

        var solid_bytes = List[UInt8]()
        for i in range(len(file_paths)):
            var fp = file_paths[i]
            with open(fp, "r") as f:
                var fb = f.read_bytes()
                for j in range(len(fb)):
                    solid_bytes.append(fb[j])

        var total_size = len(solid_bytes)
        print("Target: " + target_path + " (" + String(total_size) + " bytes across " + String(len(file_paths)) + " files)")
        print("")

        # Benchmark Fast (-1)
        var p_fast = Pipeline(level=1)
        var t0 = perf_counter_ns()
        var chunks_fast = p_fast.compress_stream(Span[UInt8](solid_bytes))
        var t1 = perf_counter_ns()
        var comp_fast_size = 0
        for i in range(len(chunks_fast)):
            comp_fast_size += chunks_fast[i].compressed_size
        var elapsed_c_fast = Float64(t1 - t0) / 1000000000.0
        var speed_c_fast = (Float64(total_size) / (1024.0 * 1024.0)) / max(elapsed_c_fast, 0.000001)

        # Decompression benchmark
        var decomp = Decompressor()
        var t2 = perf_counter_ns()
        for i in range(len(chunks_fast)):
            ref c = chunks_fast[i]
            _ = decomp.decompress(c.mode, Span[UInt8](c.data), c.uncompressed_size, c.checksum)
        var t3 = perf_counter_ns()
        var elapsed_d_fast = Float64(t3 - t2) / 1000000000.0
        var speed_d_fast = (Float64(total_size) / (1024.0 * 1024.0)) / max(elapsed_d_fast, 0.000001)

        print("[Mode -1 (Fast)]")
        print("  Compression:   " + String(speed_c_fast) + " MB/s (" + String(elapsed_c_fast) + " s)")
        print("  Decompression: " + String(speed_d_fast) + " MB/s (" + String(elapsed_d_fast) + " s)")
        print("  Size:          " + String(comp_fast_size) + " bytes (" + String((Float64(comp_fast_size)/Float64(max(total_size,1)))*100.0) + "%)")
        print("")

        # Benchmark Ultra (-9)
        var p_ultra = Pipeline(level=9)
        var t4 = perf_counter_ns()
        var chunks_ultra = p_ultra.compress_stream(Span[UInt8](solid_bytes))
        var t5 = perf_counter_ns()
        var comp_ultra_size = 0
        for i in range(len(chunks_ultra)):
            comp_ultra_size += chunks_ultra[i].compressed_size
        var elapsed_c_ultra = Float64(t5 - t4) / 1000000000.0
        var speed_c_ultra = (Float64(total_size) / (1024.0 * 1024.0)) / max(elapsed_c_ultra, 0.000001)

        print("[Mode -9 (Ultra)]")
        print("  Compression:   " + String(speed_c_ultra) + " MB/s (" + String(elapsed_c_ultra) + " s)")
        print("  Size:          " + String(comp_ultra_size) + " bytes (" + String((Float64(comp_ultra_size)/Float64(max(total_size,1)))*100.0) + "%)")
