from std.collections import Span
from std.origin import Origin, MutUntrackedOrigin
from std.runtime.asyncrt import TaskGroup
from std.io.file import open
from std.os.path import exists, isdir, isfile, dirname, join
from std.os import mkdir
from mojopack.compressor import CompressedChunk, ChunkMode, Compressor, Decompressor
from mojopack.checksum import XXH3_64

struct FileMetadata:
    var path: String
    var size: Int
    var solid_offset: Int
    var mode: UInt32
    var mtime: UInt64

    def __init__(out self, path: String, size: Int, solid_offset: Int, mode: UInt32, mtime: UInt64):
        self.path = path
        self.size = size
        self.solid_offset = solid_offset
        self.mode = mode
        self.mtime = mtime


struct ContainerUtils:
    @staticmethod
    def sanitize_path(path: String) -> String:
        var res = String()
        var i = 0
        var n = path.byte_length()
        while i < n and (path[byte=i] == "/" or path[byte=i] == "\\"):
            i += 1

        var part = String()
        while i < n:
            var b = path[byte=i]
            if b == "/" or b == "\\":
                if part != "" and part != "." and part != "..":
                    if res != "":
                        res += "/"
                    res += part
                part = String()
            else:
                part += b
            i += 1

        if part != "" and part != "." and part != "..":
            if res != "":
                res += "/"
            res += part

        if res == "":
            return "extracted_file"
        return res

    @staticmethod
    def ensure_dir(path: String) raises:
        if path == "" or path == "." or isdir(path):
            return
        var parent = dirname(path)
        if parent != "" and parent != path and parent != ".":
            Self.ensure_dir(parent)
        if not exists(path):
            try:
                mkdir(path)
            except:
                pass


struct ArchiveWriter:
    var entries: List[FileMetadata]
    var chunks: List[CompressedChunk]

    def __init__(out self):
        self.entries = List[FileMetadata]()
        self.chunks = List[CompressedChunk]()

    def add_entry(mut self, var entry: FileMetadata):
        self.entries.append(entry^)

    def add_chunk(mut self, var chunk: CompressedChunk):
        self.chunks.append(chunk^)

    def write_to_file(self, archive_path: String) raises:
        var num_chunks = len(self.chunks)
        var num_files = len(self.entries)

        var expected_total = 20 + num_chunks * 17
        for i in range(num_chunks):
            expected_total += len(self.chunks[i].data)
        expected_total += 4 + num_files * 34
        for i in range(num_files):
            expected_total += self.entries[i].path.byte_length()
        expected_total += 8

        var out_bytes = List[UInt8](capacity=expected_total)

        # 4 Bytes Magic: "MPK1"
        out_bytes.append(UInt8(ord("M")))
        out_bytes.append(UInt8(ord("P")))
        out_bytes.append(UInt8(ord("K")))
        out_bytes.append(UInt8(ord("1")))

        # 4 Bytes Flags (0)
        for _ in range(4):
            out_bytes.append(0)

        # 4 Bytes Chunks count
        out_bytes.append(UInt8(num_chunks & 0xFF))
        out_bytes.append(UInt8((num_chunks >> 8) & 0xFF))
        out_bytes.append(UInt8((num_chunks >> 16) & 0xFF))
        out_bytes.append(UInt8((num_chunks >> 24) & 0xFF))

        # 8 Bytes Placeholder for Metadata Table Offset
        var meta_offset_pos = len(out_bytes)
        for _ in range(8):
            out_bytes.append(0)

        # Write each chunk
        for i in range(num_chunks):
            ref c = self.chunks[i]
            # 1 Byte Mode
            out_bytes.append(c.mode)
            # 4 Bytes Uncompressed Size
            out_bytes.append(UInt8(c.uncompressed_size & 0xFF))
            out_bytes.append(UInt8((c.uncompressed_size >> 8) & 0xFF))
            out_bytes.append(UInt8((c.uncompressed_size >> 16) & 0xFF))
            out_bytes.append(UInt8((c.uncompressed_size >> 24) & 0xFF))
            # 4 Bytes Compressed Size
            out_bytes.append(UInt8(c.compressed_size & 0xFF))
            out_bytes.append(UInt8((c.compressed_size >> 8) & 0xFF))
            out_bytes.append(UInt8((c.compressed_size >> 16) & 0xFF))
            out_bytes.append(UInt8((c.compressed_size >> 24) & 0xFF))
            # 8 Bytes Checksum
            for b in range(8):
                out_bytes.append(UInt8((c.checksum >> UInt64(b * 8)) & 0xFF))
            # Fast vectorized payload copy
            out_bytes.extend(Span[UInt8](c.data))

        # Record Metadata Offset
        var meta_offset = len(out_bytes)
        for b in range(8):
            out_bytes[meta_offset_pos + b] = UInt8((UInt64(meta_offset) >> UInt64(b * 8)) & 0xFF)

        # Write Metadata Table
        # 4 Bytes: Files count
        out_bytes.append(UInt8(num_files & 0xFF))
        out_bytes.append(UInt8((num_files >> 8) & 0xFF))
        out_bytes.append(UInt8((num_files >> 16) & 0xFF))
        out_bytes.append(UInt8((num_files >> 24) & 0xFF))

        for i in range(num_files):
            ref ent = self.entries[i]
            var path_len = ent.path.byte_length()
            # 2 Bytes Path Length
            out_bytes.append(UInt8(path_len & 0xFF))
            out_bytes.append(UInt8((path_len >> 8) & 0xFF))
            # Path UTF-8
            out_bytes.extend(Span[UInt8](ent.path.as_bytes()))
            # 8 Bytes Size
            for b in range(8):
                out_bytes.append(UInt8((UInt64(ent.size) >> UInt64(b * 8)) & 0xFF))
            # 8 Bytes Solid Offset
            for b in range(8):
                out_bytes.append(UInt8((UInt64(ent.solid_offset) >> UInt64(b * 8)) & 0xFF))
            # 4 Bytes Mode
            for b in range(4):
                out_bytes.append(UInt8((ent.mode >> UInt32(b * 8)) & 0xFF))
            # 8 Bytes Mtime
            for b in range(8):
                out_bytes.append(UInt8((ent.mtime >> UInt64(b * 8)) & 0xFF))

        # 8 Bytes Footer Magic: "EOF_MPK\0"
        out_bytes.append(UInt8(ord("E")))
        out_bytes.append(UInt8(ord("O")))
        out_bytes.append(UInt8(ord("F")))
        out_bytes.append(UInt8(ord("_")))
        out_bytes.append(UInt8(ord("M")))
        out_bytes.append(UInt8(ord("P")))
        out_bytes.append(UInt8(ord("K")))
        out_bytes.append(0)

        with open(archive_path, "w") as f:
            f.write_bytes(out_bytes)


async def _decompress_chunk_task(
    mode: UInt8,
    src_addr: Int,
    comp_size: Int,
    dst_addr: Int,
    uncomp_size: Int,
    expected_checksum: UInt64,
):
    var src_ptr = Pointer[UInt8, MutUntrackedOrigin](unsafe_from_address=src_addr)
    var dst_ptr = Pointer[UInt8, MutUntrackedOrigin](unsafe_from_address=dst_addr)
    var decomp = Decompressor()
    var src_span = Span[UInt8, MutUntrackedOrigin](unsafe_ptr=src_ptr, length=comp_size)
    try:
        decomp.decompress_to_ptr(mode, src_span, dst_ptr, uncomp_size, expected_checksum)
    except:
        pass


struct ArchiveReader:
    var raw_bytes: List[UInt8]
    var flags: UInt32
    var num_chunks: Int
    var meta_offset: Int
    var entries: List[FileMetadata]

    def __init__(out self, archive_path: String) raises:
        self.flags = 0
        self.num_chunks = 0
        self.meta_offset = 0
        self.entries = List[FileMetadata]()

        with open(archive_path, "r") as f:
            self.raw_bytes = f.read_bytes()

        var total_len = len(self.raw_bytes)
        if total_len < 28:
            raise Error("File too small to be an MPK archive")

        # Verify magic "MPK1"
        if self.raw_bytes[0] != UInt8(ord("M")) or self.raw_bytes[1] != UInt8(ord("P")) or self.raw_bytes[2] != UInt8(ord("K")) or self.raw_bytes[3] != UInt8(ord("1")):
            raise Error("Invalid MPK archive magic header")

        # Read flags
        self.flags = UInt32(self.raw_bytes[4]) | (UInt32(self.raw_bytes[5]) << 8) | (UInt32(self.raw_bytes[6]) << 16) | (UInt32(self.raw_bytes[7]) << 24)

        # Read num chunks
        self.num_chunks = Int(self.raw_bytes[8]) | (Int(self.raw_bytes[9]) << 8) | (Int(self.raw_bytes[10]) << 16) | (Int(self.raw_bytes[11]) << 24)

        # Read meta offset
        var off: UInt64 = 0
        for b in range(8):
            off |= UInt64(self.raw_bytes[12 + b]) << UInt64(b * 8)
        self.meta_offset = Int(off)

        # Read metadata table
        self._read_metadata()

    def _read_metadata(mut self) raises:
        var p = self.meta_offset
        var total_len = len(self.raw_bytes)
        if p >= total_len:
            raise Error("Invalid metadata offset in MPK archive")

        var num_files = Int(self.raw_bytes[p]) | (Int(self.raw_bytes[p + 1]) << 8) | (Int(self.raw_bytes[p + 2]) << 16) | (Int(self.raw_bytes[p + 3]) << 24)
        p += 4

        for _ in range(num_files):
            if p + 2 > total_len:
                break
            var path_len = Int(self.raw_bytes[p]) | (Int(self.raw_bytes[p + 1]) << 8)
            p += 2

            var path_chars = List[UInt8]()
            for _ in range(path_len):
                if p < total_len:
                    path_chars.append(self.raw_bytes[p])
                    p += 1

            var file_path = String(from_utf8_lossy=path_chars)

            var size: UInt64 = 0
            for b in range(8):
                if p < total_len:
                    size |= UInt64(self.raw_bytes[p]) << UInt64(b * 8)
                    p += 1

            var solid_offset: UInt64 = 0
            for b in range(8):
                if p < total_len:
                    solid_offset |= UInt64(self.raw_bytes[p]) << UInt64(b * 8)
                    p += 1

            var mode: UInt32 = 0
            for b in range(4):
                if p < total_len:
                    mode |= UInt32(self.raw_bytes[p]) << UInt32(b * 8)
                    p += 1

            var mtime: UInt64 = 0
            for b in range(8):
                if p < total_len:
                    mtime |= UInt64(self.raw_bytes[p]) << UInt64(b * 8)
                    p += 1

            self.entries.append(FileMetadata(file_path, Int(size), Int(solid_offset), mode, mtime))

    def decompress_solid_stream(self) raises -> List[UInt8]:
        var p = 20
        var total_uncomp = 0
        for _ in range(self.num_chunks):
            if p + 17 > len(self.raw_bytes):
                break
            var uncomp = Int(self.raw_bytes[p + 1]) | (Int(self.raw_bytes[p + 2]) << 8) | (Int(self.raw_bytes[p + 3]) << 16) | (Int(self.raw_bytes[p + 4]) << 24)
            var comp = Int(self.raw_bytes[p + 5]) | (Int(self.raw_bytes[p + 6]) << 8) | (Int(self.raw_bytes[p + 7]) << 16) | (Int(self.raw_bytes[p + 8]) << 24)
            total_uncomp += uncomp
            p += 17 + comp

        var solid = List[UInt8](capacity=total_uncomp)
        for _ in range(total_uncomp):
            solid.append(0)

        var solid_ptr = Pointer[UInt8, MutUntrackedOrigin](unsafe_from_address=Int(solid.unsafe_ptr()))
        var raw_ptr = Pointer[UInt8, MutUntrackedOrigin](unsafe_from_address=Int(self.raw_bytes.unsafe_ptr()))

        if self.num_chunks <= 1:
            if self.num_chunks == 1:
                p = 20
                var mode = raw_ptr.unsafe_offset(p)[]
                var uncomp = Int(self.raw_bytes[p + 1]) | (Int(self.raw_bytes[p + 2]) << 8) | (Int(self.raw_bytes[p + 3]) << 16) | (Int(self.raw_bytes[p + 4]) << 24)
                var comp = Int(self.raw_bytes[p + 5]) | (Int(self.raw_bytes[p + 6]) << 8) | (Int(self.raw_bytes[p + 7]) << 16) | (Int(self.raw_bytes[p + 8]) << 24)
                var chk: UInt64 = 0
                for b in range(8):
                    chk |= UInt64(self.raw_bytes[p + 9 + b]) << UInt64(b * 8)
                var src_span = Span[UInt8, MutUntrackedOrigin](unsafe_ptr=raw_ptr.unsafe_offset(p + 17), length=comp)
                var decomp = Decompressor()
                decomp.decompress_to_ptr(mode, src_span, solid_ptr, uncomp, chk)
        else:
            var tg = TaskGroup()
            p = 20
            var solid_off = 0
            for _ in range(self.num_chunks):
                if p + 17 > len(self.raw_bytes):
                    break
                var mode = raw_ptr.unsafe_offset(p)[]
                var uncomp = Int(self.raw_bytes[p + 1]) | (Int(self.raw_bytes[p + 2]) << 8) | (Int(self.raw_bytes[p + 3]) << 16) | (Int(self.raw_bytes[p + 4]) << 24)
                var comp = Int(self.raw_bytes[p + 5]) | (Int(self.raw_bytes[p + 6]) << 8) | (Int(self.raw_bytes[p + 7]) << 16) | (Int(self.raw_bytes[p + 8]) << 24)
                var chk: UInt64 = 0
                for b in range(8):
                    chk |= UInt64(self.raw_bytes[p + 9 + b]) << UInt64(b * 8)

                var src_addr = Int(raw_ptr.unsafe_offset(p + 17))
                var dst_addr = Int(solid_ptr.unsafe_offset(solid_off))
                tg.create_task(_decompress_chunk_task(mode, src_addr, comp, dst_addr, uncomp, chk))
                solid_off += uncomp
                p += 17 + comp
            tg.wait()

        return solid^
