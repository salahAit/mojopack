from std.collections import List, Span, InlineArray
from std.origin import MutUntrackedOrigin
from std.ffi import external_call
from std.sys import argv
from std.time import perf_counter_ns
from std.runtime.asyncrt import TaskGroup

# ==============================================================================
# Fast Checksum (XXH3 64-bit) - Inlined for zero dependencies
# ==============================================================================
struct XXH3_64:
    comptime PRIME64_1: UInt64 = 0x9E3779B185EBCA87
    comptime PRIME64_2: UInt64 = 0xC2B2AE3D27D4EB4F
    comptime PRIME64_3: UInt64 = 0x165667B19E3779F9
    comptime PRIME64_4: UInt64 = 0x85EBCA77C2B2AE63
    comptime PRIME64_5: UInt64 = 0x27D4EB2F165667C5

    def __init__(out self):
        pass

    @always_inline
    @staticmethod
    def _rotl(v: UInt64, r: UInt64) -> UInt64:
        return (v << r) | (v >> (UInt64(64) - r))

    def compute(self, data: Span[UInt8, _]) -> UInt64:
        var length = len(data)
        if length == 0:
            return Self.PRIME64_5

        var h64: UInt64 = UInt64(length) * Self.PRIME64_1
        var idx = 0

        while idx + 32 <= length:
            var v1 = UInt64(data[idx]) | (UInt64(data[idx+1]) << 8) | (UInt64(data[idx+2]) << 16) | (UInt64(data[idx+3]) << 24) | (UInt64(data[idx+4]) << 32) | (UInt64(data[idx+5]) << 40) | (UInt64(data[idx+6]) << 48) | (UInt64(data[idx+7]) << 56)
            var v2 = UInt64(data[idx+8]) | (UInt64(data[idx+9]) << 8) | (UInt64(data[idx+10]) << 16) | (UInt64(data[idx+11]) << 24) | (UInt64(data[idx+12]) << 32) | (UInt64(data[idx+13]) << 40) | (UInt64(data[idx+14]) << 48) | (UInt64(data[idx+15]) << 56)
            var v3 = UInt64(data[idx+16]) | (UInt64(data[idx+17]) << 8) | (UInt64(data[idx+18]) << 16) | (UInt64(data[idx+19]) << 24) | (UInt64(data[idx+20]) << 32) | (UInt64(data[idx+21]) << 40) | (UInt64(data[idx+22]) << 48) | (UInt64(data[idx+23]) << 56)
            var v4 = UInt64(data[idx+24]) | (UInt64(data[idx+25]) << 8) | (UInt64(data[idx+26]) << 16) | (UInt64(data[idx+27]) << 24) | (UInt64(data[idx+28]) << 32) | (UInt64(data[idx+29]) << 40) | (UInt64(data[idx+30]) << 48) | (UInt64(data[idx+31]) << 56)

            var mix1 = v1 ^ Self.PRIME64_2
            mix1 = Self._rotl(mix1, 31) * Self.PRIME64_1
            var mix2 = v2 ^ Self.PRIME64_3
            mix2 = Self._rotl(mix2, 27) * Self.PRIME64_2
            var mix3 = v3 ^ Self.PRIME64_4
            mix3 = Self._rotl(mix3, 33) * Self.PRIME64_3
            var mix4 = v4 ^ Self.PRIME64_5
            mix4 = Self._rotl(mix4, 29) * Self.PRIME64_4

            h64 ^= mix1 ^ mix2 ^ mix3 ^ mix4
            h64 = Self._rotl(h64, 27) * Self.PRIME64_1 + Self.PRIME64_4
            idx += 32

        while idx + 8 <= length:
            var v = UInt64(data[idx]) | (UInt64(data[idx+1]) << 8) | (UInt64(data[idx+2]) << 16) | (UInt64(data[idx+3]) << 24) | (UInt64(data[idx+4]) << 32) | (UInt64(data[idx+5]) << 40) | (UInt64(data[idx+6]) << 48) | (UInt64(data[idx+7]) << 56)
            var k1 = Self._rotl(v * Self.PRIME64_2, 31) * Self.PRIME64_1
            h64 ^= k1
            h64 = Self._rotl(h64, 27) * Self.PRIME64_1 + Self.PRIME64_4
            idx += 8

        while idx < length:
            h64 ^= UInt64(data[idx]) * Self.PRIME64_5
            h64 = Self._rotl(h64, 11) * Self.PRIME64_1
            idx += 1

        h64 ^= h64 >> UInt64(33)
        h64 *= Self.PRIME64_2
        h64 ^= h64 >> UInt64(29)
        h64 *= Self.PRIME64_3
        h64 ^= h64 >> UInt64(32)

        return h64

# ==============================================================================
# Lean POSIX FFI Helpers (Zero-overhead libc calls)
# ==============================================================================
@always_inline
def to_c_str(s: String) -> List[UInt8]:
    var b = s.as_bytes()
    var l = List[UInt8](capacity=len(b) + 1)
    for i in range(len(b)):
        l.append(b[i])
    l.append(0)
    return l^

def posix_open(path: String, flags: Int32, mode: UInt32 = 0o644) -> Int32:
    var c_str = to_c_str(path)
    return external_call["open", Int32](c_str.unsafe_ptr(), flags, mode)

def posix_close(fd: Int32):
    _ = external_call["close", Int32](fd)

def posix_read(fd: Int32, buf: Pointer[UInt8, MutUntrackedOrigin], count: Int) -> Int:
    var total = 0
    while total < count:
        var n = external_call["read", Int](Int(fd), buf.unsafe_offset(total), count - total)
        if n <= 0:
            break
        total += n
    return total

def posix_write(fd: Int32, buf: Pointer[UInt8, MutUntrackedOrigin], count: Int) -> Int:
    var total = 0
    while total < count:
        var n = external_call["write", Int](Int(fd), buf.unsafe_offset(total), count - total)
        if n <= 0:
            break
        total += n
    return total

def posix_mkdir(path: String, mode: UInt32 = 0o755) -> Int32:
    var c_str = to_c_str(path)
    return external_call["mkdir", Int32](c_str.unsafe_ptr(), mode)

def posix_chmod(path: String, mode: UInt32):
    var c_str = to_c_str(path)
    _ = external_call["chmod", Int32](c_str.unsafe_ptr(), mode)

def posix_lseek_end(fd: Int32) -> Int:
    return external_call["lseek", Int](fd, 0, Int32(2)) # SEEK_END = 2

def posix_lseek_set(fd: Int32, offset: Int) -> Int:
    return external_call["lseek", Int](fd, offset, Int32(0)) # SEEK_SET = 0

def posix_malloc(size: Int) -> Pointer[UInt8, MutUntrackedOrigin]:
    return external_call["malloc", Pointer[UInt8, MutUntrackedOrigin]](size)

def posix_free(ptr: Pointer[UInt8, MutUntrackedOrigin]):
    _ = external_call["free", NoneType](ptr)

@always_inline
def read_u16(ptr: Pointer[UInt8, MutUntrackedOrigin], off: Int) -> Int:
    return Int(ptr.unsafe_offset(off)[]) | (Int(ptr.unsafe_offset(off + 1)[]) << 8)

@always_inline
def read_u32(ptr: Pointer[UInt8, MutUntrackedOrigin], off: Int) -> Int:
    return Int(ptr.unsafe_offset(off)[]) | (Int(ptr.unsafe_offset(off + 1)[]) << 8) | (Int(ptr.unsafe_offset(off + 2)[]) << 16) | (Int(ptr.unsafe_offset(off + 3)[]) << 24)

@always_inline
def read_u64(ptr: Pointer[UInt8, MutUntrackedOrigin], off: Int) -> UInt64:
    var res: UInt64 = 0
    for b in range(8):
        res |= UInt64(ptr.unsafe_offset(off + b)[]) << UInt64(b * 8)
    return res

def ensure_dir(path: String):
    if path == "" or path == ".":
        return
    var n = path.byte_length()
    var cur = String()
    for i in range(n):
        var c = path[byte=i]
        if c == "/" or c == "\\":
            if cur != "" and cur != ".":
                _ = posix_mkdir(cur, UInt32(0o755))
            cur += "/"
        else:
            cur += c
    if cur != "" and cur != ".":
        _ = posix_mkdir(cur, UInt32(0o755))

def get_dirname(path: String) -> String:
    var n = path.byte_length()
    var last_slash = -1
    for i in range(n):
        if path[byte=i] == "/" or path[byte=i] == "\\":
            last_slash = i
    if last_slash <= 0:
        return ""
    var res = String()
    for i in range(last_slash):
        res += path[byte=i]
    return res

def join_path(a: String, b: String) -> String:
    if a == "" or a == ".":
        return b
    if b == "":
        return a
    if a.endswith("/"):
        return a + b
    return a + "/" + b

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

# ==============================================================================
# Ultra-Lean Range Decoder (Zero Heap Allocation)
# ==============================================================================
struct RangeDecoder:
    var code: UInt32
    var range: UInt32
    var pos: Int

    def __init__(out self, data_ptr: Pointer[UInt8, MutUntrackedOrigin], data_len: Int):
        self.code = 0
        self.range = 0xFFFFFFFF
        self.pos = 0
        for _ in range(5):
            var b = data_ptr.unsafe_offset(self.pos)[] if self.pos < data_len else UInt8(0)
            self.code = (self.code << 8) | UInt32(b)
            self.pos += 1

    @always_inline
    def decode_bit(mut self, mut prob: UInt16, data_ptr: Pointer[UInt8, MutUntrackedOrigin], data_len: Int) -> Int:
        var bound: UInt32 = (self.range >> 11) * UInt32(prob)
        var bit: Int
        if self.code < bound:
            self.range = bound
            prob += (UInt16(2048) - prob) >> 5
            bit = 0
        else:
            self.range -= bound
            self.code -= bound
            prob -= prob >> 5
            bit = 1

        while self.range < 0x01000000:
            var b = data_ptr.unsafe_offset(self.pos)[] if self.pos < data_len else UInt8(0)
            self.pos += 1
            self.code = (self.code << 8) | UInt32(b)
            self.range <<= 8

        return bit

    @always_inline
    def decode_direct_bits(mut self, num_bits: Int, data_ptr: Pointer[UInt8, MutUntrackedOrigin], data_len: Int) -> UInt32:
        var res: UInt32 = 0
        for _ in range(num_bits):
            self.range >>= 1
            var bit: UInt32 = 0
            if self.code >= self.range:
                self.code -= self.range
                bit = 1
            res = (res << 1) | bit
            while self.range < 0x01000000:
                var b = data_ptr.unsafe_offset(self.pos)[] if self.pos < data_len else UInt8(0)
                self.pos += 1
                self.code = (self.code << 8) | UInt32(b)
                self.range <<= 8
        return res

# ==============================================================================
# x86-64 BCJ Inverse Normalizer
# ==============================================================================
struct BCJ:
    @staticmethod
    @no_inline
    def inverse(ptr: Pointer[UInt8, MutUntrackedOrigin], size: Int):
        var i = 0
        while i + 5 <= size:
            var b = ptr.unsafe_offset(i)[]
            if b == 0xE8 or b == 0xE9:
                var b4 = ptr.unsafe_offset(i + 4)[]
                if b4 == 0x00 or b4 == 0xFF:
                    var src = (UInt32(b4) << 24) | (UInt32(ptr.unsafe_offset(i+3)[]) << 16) | (UInt32(ptr.unsafe_offset(i+2)[]) << 8) | UInt32(ptr.unsafe_offset(i+1)[])
                    var dest = src - UInt32(i + 5)
                    ptr.unsafe_offset(i+1)[] = UInt8(dest & 0xFF)
                    ptr.unsafe_offset(i+2)[] = UInt8((dest >> 8) & 0xFF)
                    ptr.unsafe_offset(i+3)[] = UInt8((dest >> 16) & 0xFF)
                    ptr.unsafe_offset(i+4)[] = UInt8((~(((dest >> 24) & 1) - 1)) & 0xFF)
                    i += 5
                    continue
            i += 1

# ==============================================================================
# Decompressor Engine (LZ4-style + LZMA-style Ultra Range Coder)
# ==============================================================================
struct CoreDecompressor:
    @staticmethod
    @no_inline
    def _decompress_lz(src: Pointer[UInt8, MutUntrackedOrigin], src_len: Int, dst_ptr: Pointer[UInt8, MutUntrackedOrigin], uncompressed_size: Int):
        for i in range(uncompressed_size):
            dst_ptr.unsafe_offset(i)[] = 0

        var sp = 0
        var dp = 0

        while dp < uncompressed_size and sp < src_len:
            var token = Int(src.unsafe_offset(sp)[])
            sp += 1
            var lit_len = (token >> 4) & 0x0F
            if lit_len == 15:
                while sp < src_len and src.unsafe_offset(sp)[] == 255:
                    lit_len += 255
                    sp += 1
                if sp < src_len:
                    lit_len += Int(src.unsafe_offset(sp)[])
                    sp += 1

            for _ in range(lit_len):
                if sp < src_len and dp < uncompressed_size:
                    dst_ptr.unsafe_offset(dp)[] = src.unsafe_offset(sp)[]
                    dp += 1
                    sp += 1

            if dp >= uncompressed_size or sp >= src_len:
                break

            var offset = Int(src.unsafe_offset(sp)[]) | (Int(src.unsafe_offset(sp + 1)[]) << 8)
            sp += 2

            var match_len = (token & 0x0F)
            if match_len == 15:
                while sp < src_len and src.unsafe_offset(sp)[] == 255:
                    match_len += 255
                    sp += 1
                if sp < src_len:
                    match_len += Int(src.unsafe_offset(sp)[])
                    sp += 1
            match_len += 4

            var match_src = dp - offset
            for _ in range(match_len):
                if dp < uncompressed_size:
                    dst_ptr.unsafe_offset(dp)[] = dst_ptr.unsafe_offset(match_src)[]
                    dp += 1
                    match_src += 1

    @staticmethod
    @no_inline
    def _decompress_ultra_rc(src: Pointer[UInt8, MutUntrackedOrigin], src_len: Int, dst_ptr: Pointer[UInt8, MutUntrackedOrigin], uncompressed_size: Int):
        for i in range(uncompressed_size):
            dst_ptr.unsafe_offset(i)[] = 0

        if uncompressed_size == 0:
            return

        var dec = RangeDecoder(src, src_len)

        var is_match = InlineArray[UInt16, 12](fill=1024)
        var is_rep = InlineArray[UInt16, 12](fill=1024)
        var is_rep0 = InlineArray[UInt16, 12](fill=1024)
        var is_rep1 = InlineArray[UInt16, 12](fill=1024)
        var is_rep2 = InlineArray[UInt16, 12](fill=1024)
        var lit_probs = InlineArray[UInt16, 4096](fill=1024)
        var len_choice: UInt16 = 1024
        var len_choice2: UInt16 = 1024
        var len_low = InlineArray[UInt16, 16](fill=1024)
        var len_mid = InlineArray[UInt16, 16](fill=1024)
        var pos_slot_probs = InlineArray[UInt16, 256](fill=1024)

        var rep0 = 1
        var rep1 = 1
        var rep2 = 1
        var rep3 = 1
        var state = 0
        var dp = 0
        var prev_byte: UInt8 = 0

        while dp < uncompressed_size:
            var bit_match = dec.decode_bit(is_match[state], src, src_len)
            if bit_match == 0:
                var ctx = Int(prev_byte >> 4)
                var ctx_base = ctx * 256
                var tree_idx = 1
                var symbol: UInt8 = 0
                for _ in range(8):
                    var bit = dec.decode_bit(lit_probs[ctx_base + tree_idx], src, src_len)
                    symbol = (symbol << 1) | UInt8(bit)
                    tree_idx = (tree_idx << 1) | bit
                dst_ptr.unsafe_offset(dp)[] = symbol
                dp += 1
                prev_byte = symbol
                state = state - 3 if state >= 7 else (state - 2 if state >= 4 else 0)
            else:
                var bit_rep = dec.decode_bit(is_rep[state], src, src_len)
                var offset = 0
                if bit_rep == 1:
                    var bit_rep0 = dec.decode_bit(is_rep0[state], src, src_len)
                    if bit_rep0 == 0:
                        offset = rep0
                    else:
                        var bit_rep1 = dec.decode_bit(is_rep1[state], src, src_len)
                        if bit_rep1 == 0:
                            offset = rep1
                            var tmp = rep1
                            rep1 = rep0
                            rep0 = tmp
                        else:
                            var bit_rep2 = dec.decode_bit(is_rep2[state], src, src_len)
                            if bit_rep2 == 0:
                                offset = rep2
                                var tmp = rep2
                                rep2 = rep1
                                rep1 = rep0
                                rep0 = tmp
                            else:
                                offset = rep3
                                var tmp = rep3
                                rep3 = rep2
                                rep2 = rep1
                                rep1 = rep0
                                rep0 = tmp
                    state = 8 if state < 7 else 11
                else:
                    state = 7 if state < 7 else 10

                var match_len: Int
                var bit_choice = dec.decode_bit(len_choice, src, src_len)
                var len_val: Int
                if bit_choice == 0:
                    var tree_idx = 1
                    for _ in range(3):
                        var b = dec.decode_bit(len_low[tree_idx], src, src_len)
                        tree_idx = (tree_idx << 1) | b
                    len_val = tree_idx - 8
                    match_len = len_val + 2
                else:
                    var bit_choice2 = dec.decode_bit(len_choice2, src, src_len)
                    if bit_choice2 == 0:
                        var tree_idx = 1
                        for _ in range(3):
                            var b = dec.decode_bit(len_mid[tree_idx], src, src_len)
                            tree_idx = (tree_idx << 1) | b
                        len_val = (tree_idx - 8) + 8
                        match_len = len_val + 2
                    else:
                        var raw_len = Int(dec.decode_direct_bits(8, src, src_len))
                        len_val = raw_len + 16
                        match_len = len_val + 2

                if bit_rep == 0:
                    var len_to_pos_state = min(len_val, 3)
                    var slot_ctx_base = len_to_pos_state * 64
                    var slot_tree = 1
                    for _ in range(6):
                        var b = dec.decode_bit(pos_slot_probs[slot_ctx_base + slot_tree], src, src_len)
                        slot_tree = (slot_tree << 1) | b
                    var pos_slot = slot_tree - 64
                    if pos_slot < 4:
                        offset = pos_slot + 1
                    else:
                        var num_direct = (pos_slot >> 1) - 1
                        var base_val = (2 | (pos_slot & 1)) << num_direct
                        var direct = Int(dec.decode_direct_bits(num_direct, src, src_len))
                        offset = base_val + direct

                    rep3 = rep2
                    rep2 = rep1
                    rep1 = rep0
                    rep0 = offset

                var match_src = dp - offset
                for _ in range(match_len):
                    if dp < uncompressed_size:
                        dst_ptr.unsafe_offset(dp)[] = dst_ptr.unsafe_offset(match_src)[]
                        dp += 1
                        match_src += 1

                prev_byte = dst_ptr.unsafe_offset(dp - 1)[]

    @staticmethod
    @no_inline
    def decompress_chunk(mode: UInt8, src_ptr: Pointer[UInt8, MutUntrackedOrigin], src_len: Int, dst_ptr: Pointer[UInt8, MutUntrackedOrigin], uncompressed_size: Int, expected_checksum: UInt64):
        if mode == 0:
            for i in range(uncompressed_size):
                dst_ptr.unsafe_offset(i)[] = src_ptr.unsafe_offset(i)[]
        elif mode == 1 or mode == 2:
            Self._decompress_lz(src_ptr, src_len, dst_ptr, uncompressed_size)
        elif mode == 3 or mode == 4:
            Self._decompress_ultra_rc(src_ptr, src_len, dst_ptr, uncompressed_size)
            if mode == 4:
                BCJ.inverse(dst_ptr, uncompressed_size)

        var chk_span = Span[UInt8, MutUntrackedOrigin](unsafe_ptr=dst_ptr, length=uncompressed_size)
        var xxh = XXH3_64()
        var actual_chk = xxh.compute(chk_span)
        if actual_chk != expected_checksum:
            print("ERROR: Checksum mismatch!")

async def _decompress_task(mode: UInt8, src_addr: Int, comp: Int, dst_addr: Int, uncomp: Int, chk: UInt64):
    var src_ptr = Pointer[UInt8, MutUntrackedOrigin](unsafe_from_address=src_addr)
    var dst_ptr = Pointer[UInt8, MutUntrackedOrigin](unsafe_from_address=dst_addr)
    CoreDecompressor.decompress_chunk(mode, src_ptr, comp, dst_ptr, uncomp, chk)

# ==============================================================================
# Archive Extraction Pipeline
# ==============================================================================
def extract_archive(archive_path: String, dest_dir: String):
    var fd = posix_open(archive_path, 0) # O_RDONLY
    if fd < 0:
        print("Failed to open archive:", archive_path)
        return

    var file_size = posix_lseek_end(fd)
    _ = posix_lseek_set(fd, 0)
    if file_size < 28:
        print("Invalid archive: file too small")
        posix_close(fd)
        return

    var raw_ptr = posix_malloc(file_size)
    var read_bytes = posix_read(fd, raw_ptr, file_size)
    posix_close(fd)

    if read_bytes != file_size:
        print("Failed to read entire archive")
        posix_free(raw_ptr)
        return

    if raw_ptr.unsafe_offset(0)[] != UInt8(ord("M")) or raw_ptr.unsafe_offset(1)[] != UInt8(ord("P")) or raw_ptr.unsafe_offset(2)[] != UInt8(ord("K")) or raw_ptr.unsafe_offset(3)[] != UInt8(ord("1")):
        print("Invalid MPK archive magic")
        posix_free(raw_ptr)
        return

    var num_chunks = read_u32(raw_ptr, 8)
    var meta_offset = Int(read_u64(raw_ptr, 12))

    # Pass 1: compute total uncompressed size
    var p = 20
    var total_uncomp = 0
    for _ in range(num_chunks):
        if p + 17 > meta_offset:
            break
        var uncomp = read_u32(raw_ptr, p + 1)
        var comp = read_u32(raw_ptr, p + 5)
        total_uncomp += uncomp
        p += 17 + comp

    # Pre-allocate solid buffer once via malloc
    var solid_ptr = posix_malloc(total_uncomp)

    # Pass 2: Decompress chunks concurrently across active worker threads
    var t0 = perf_counter_ns()
    var tg = TaskGroup()
    p = 20
    var solid_off = 0
    for _ in range(num_chunks):
        if p + 17 > meta_offset:
            break
        var mode = raw_ptr.unsafe_offset(p)[]
        var uncomp = read_u32(raw_ptr, p + 1)
        var comp = read_u32(raw_ptr, p + 5)
        var chk = read_u64(raw_ptr, p + 9)
        var src_addr = Int(raw_ptr.unsafe_offset(p + 17))
        var dst_addr = Int(solid_ptr.unsafe_offset(solid_off))

        tg.create_task(_decompress_task(mode, src_addr, comp, dst_addr, uncomp, chk))
        solid_off += uncomp
        p += 17 + comp
    tg.wait()

    var t1 = perf_counter_ns()
    var elapsed_ms = Int((t1 - t0) / 1_000_000)
    var speed_mb_s = (Int(total_uncomp) / 1_048_576) * 1000 / max(elapsed_ms, 1)

    # Pass 3: Extract files directly to disk
    ensure_dir(dest_dir)
    var p_meta = meta_offset
    var num_files = 0
    if p_meta + 4 <= file_size:
        num_files = read_u32(raw_ptr, p_meta)
        p_meta += 4
        for _ in range(num_files):
            if p_meta + 2 > file_size:
                break
            var path_len = read_u16(raw_ptr, p_meta)
            p_meta += 2
            var path_span = Span[UInt8, MutUntrackedOrigin](unsafe_ptr=raw_ptr.unsafe_offset(p_meta), length=path_len)
            var file_path = String(from_utf8_lossy=path_span)
            p_meta += path_len

            var ent_size = Int(read_u64(raw_ptr, p_meta))
            p_meta += 8
            var ent_solid_off = Int(read_u64(raw_ptr, p_meta))
            p_meta += 8
            var ent_mode = UInt32(read_u32(raw_ptr, p_meta))
            p_meta += 4
            p_meta += 8 # mtime

            var clean_path = sanitize_path(file_path)
            var out_file_path = join_path(dest_dir, clean_path)
            var d = get_dirname(out_file_path)
            if d != "":
                ensure_dir(d)

            # O_WRONLY = 1, O_CREAT = 64, O_TRUNC = 512 -> 577 (0o1101 in octal)
            var out_fd = posix_open(out_file_path, 577, UInt32(0o755 if ent_mode != 0 else 0o644))
            if out_fd >= 0:
                var file_src_ptr = solid_ptr.unsafe_offset(ent_solid_off)
                _ = posix_write(out_fd, file_src_ptr, ent_size)
                posix_close(out_fd)

            if ent_mode != 0:
                posix_chmod(out_file_path, ent_mode)

    print("Unpacked", num_files, "files (", total_uncomp, "bytes) in", elapsed_ms, "ms (", speed_mb_s, "MB/s)")

    posix_free(solid_ptr)
    posix_free(raw_ptr)

def main():
    var args = argv()
    if len(args) < 2 or args[1] == "-h" or args[1] == "--help" or args[1] == "help":
        print("unmpack v1.0.0 - Ultra-Lean Standalone Decompressor for MojoPack (.mpk)")
        print("Copyright (c) 2026 Salah AIT AMOKRANE. Released under MIT License.")
        print("")
        print("Usage:")
        print("  unmpack <archive.mpk> [-o <dest_dir>]    Extract archive to destination directory")
        print("  unmpack -v, --version                    Print version information")
        print("  unmpack -h, --help                       Print this help message")
        return

    if args[1] == "-v" or args[1] == "--version" or args[1] == "version":
        print("unmpack v1.0.0 (x86_64-linux)")
        print("MojoPack Standalone Decompressor - Zero-Dependency Lean Binary")
        print("Copyright (c) 2026 Salah AIT AMOKRANE. Released under MIT License.")
        return

    var archive_path = args[1]
    var dest_dir = "."
    var i = 2
    while i < len(args):
        if args[i] == "-o" and i + 1 < len(args):
            dest_dir = args[i + 1]
            i += 1
        i += 1

    extract_archive(archive_path, dest_dir)
