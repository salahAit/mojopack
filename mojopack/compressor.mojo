from std.collections import Span, List, InlineArray
from std.origin import Origin, MutUntrackedOrigin
from std.bit import count_leading_zeros
from mojopack.match_finder import MatchFinder, Match
from mojopack.entropy import EntropyUtils, RangeEncoder, RangeDecoder
from mojopack.checksum import XXH3_64
from mojopack.filters.bcj import BCJFilter

struct ChunkMode:
    comptime RAW: UInt8 = 0
    comptime FAST: UInt8 = 1
    comptime ULTRA: UInt8 = 2
    comptime ULTRA_RC: UInt8 = 3
    comptime ULTRA_RC_BCJ: UInt8 = 4

struct CompressedChunk:
    var mode: UInt8
    var uncompressed_size: Int
    var compressed_size: Int
    var checksum: UInt64
    var data: List[UInt8]

    def __init__(out self, mode: UInt8, uncompressed_size: Int, compressed_size: Int, checksum: UInt64, var data: List[UInt8]):
        self.mode = mode
        self.uncompressed_size = uncompressed_size
        self.compressed_size = compressed_size
        self.checksum = checksum
        self.data = data^

    def __init__(out self):
        self.mode = ChunkMode.RAW
        self.uncompressed_size = 0
        self.compressed_size = 0
        self.checksum = 0
        self.data = List[UInt8]()

    def copy(self) -> Self:
        var d_copy = self.data.copy()
        return Self(self.mode, self.uncompressed_size, self.compressed_size, self.checksum, d_copy^)


struct Compressor:
    var level: Int
    var xxh: XXH3_64

    def __init__(out self, level: Int = 1):
        self.level = level
        self.xxh = XXH3_64()

    def compress[origin: Origin](self, src: Span[UInt8, origin]) -> CompressedChunk:
        var src_len = len(src)
        var chk = self.xxh.compute(src)

        if src_len < 32 or EntropyUtils.is_incompressible(src):
            # Store raw
            var raw_data = List[UInt8](capacity=src_len)
            for i in range(src_len):
                raw_data.append(src[i])
            return CompressedChunk(ChunkMode.RAW, src_len, src_len, chk, raw_data^)

        var compressed_data: List[UInt8]
        var mode: UInt8

        if self.level >= 9:
            if BCJFilter.is_executable(src):
                var filtered = List[UInt8](capacity=src_len)
                for i in range(src_len):
                    filtered.append(src[i])
                BCJFilter.forward(filtered)
                mode = ChunkMode.ULTRA_RC_BCJ
                compressed_data = Self._compress_ultra_rc(Span[UInt8](filtered))
            else:
                mode = ChunkMode.ULTRA_RC
                compressed_data = Self._compress_ultra_rc(src)
        else:
            mode = ChunkMode.FAST
            compressed_data = Self._compress_fast_lz(src)

        # Check for expansion
        if len(compressed_data) >= src_len:
            var raw_data = List[UInt8](capacity=src_len)
            for i in range(src_len):
                raw_data.append(src[i])
            return CompressedChunk(ChunkMode.RAW, src_len, src_len, chk, raw_data^)

        var comp_len = len(compressed_data)
        return CompressedChunk(mode, src_len, comp_len, chk, compressed_data^)

    @staticmethod
    def _compress_fast_lz[origin: Origin](src: Span[UInt8, origin], max_window: Int = 65535) -> List[UInt8]:
        var out = List[UInt8]()
        var src_len = len(src)
        if src_len == 0:
            return out^

        var mf = MatchFinder(max_window, 1)
        var ip = 0
        var anchor = 0

        while ip + 12 <= src_len:
            var m = mf.find_match_fast(src, ip, src_len - ip)
            if m.length >= 4 and m.offset > 0 and m.offset <= max_window:
                var lit_len = ip - anchor
                var match_len = m.length - 4
                var token_lit = min(lit_len, 15)
                var token_match = min(match_len, 15)
                var token = UInt8((token_lit << 4) | token_match)
                out.append(token)

                if lit_len >= 15:
                    var extra = lit_len - 15
                    while extra >= 255:
                        out.append(UInt8(255))
                        extra -= 255
                    out.append(UInt8(extra))

                for j in range(lit_len):
                    out.append(src[anchor + j])

                out.append(UInt8(m.offset & 0xFF))
                out.append(UInt8((m.offset >> 8) & 0xFF))

                if match_len >= 15:
                    var extra_m = match_len - 15
                    while extra_m >= 255:
                        out.append(UInt8(255))
                        extra_m -= 255
                    out.append(UInt8(extra_m))

                ip += m.length
                anchor = ip
            else:
                ip += 1

        var tail_len = src_len - anchor
        var token_tail = UInt8(min(tail_len, 15) << 4)
        out.append(token_tail)
        if tail_len >= 15:
            var extra_t = tail_len - 15
            while extra_t >= 255:
                out.append(UInt8(255))
                extra_t -= 255
            out.append(UInt8(extra_t))

        for j in range(tail_len):
            out.append(src[anchor + j])

        return out^

    @staticmethod
    def _compress_ultra_lz[origin: Origin](src: Span[UInt8, origin], max_window: Int = 65535) -> List[UInt8]:
        var out = List[UInt8]()
        var src_len = len(src)
        if src_len == 0:
            return out^

        var mf = MatchFinder(max_window, 16)
        mf.init_prev(src_len)
        var ip = 0
        var anchor = 0

        while ip + 12 <= src_len:
            var m1 = mf.find_match_deep(src, ip, src_len - ip)
            if m1.length >= 4 and m1.offset > 0 and m1.offset <= max_window:
                var m2 = mf.find_match_deep(src, ip + 1, src_len - (ip + 1))
                if m2.length > m1.length + 1 and m2.offset > 0 and m2.offset <= max_window:
                    ip += 1
                    continue

                var lit_len = ip - anchor
                var match_len = m1.length - 4
                var token_lit = min(lit_len, 15)
                var token_match = min(match_len, 15)
                var token = UInt8((token_lit << 4) | token_match)
                out.append(token)

                if lit_len >= 15:
                    var extra = lit_len - 15
                    while extra >= 255:
                        out.append(UInt8(255))
                        extra -= 255
                    out.append(UInt8(extra))

                for j in range(lit_len):
                    out.append(src[anchor + j])

                out.append(UInt8(m1.offset & 0xFF))
                out.append(UInt8((m1.offset >> 8) & 0xFF))

                if match_len >= 15:
                    var extra_m = match_len - 15
                    while extra_m >= 255:
                        out.append(UInt8(255))
                        extra_m -= 255
                    out.append(UInt8(extra_m))

                ip += m1.length
                anchor = ip
            else:
                ip += 1

        var tail_len = src_len - anchor
        var token_tail = UInt8(min(tail_len, 15) << 4)
        out.append(token_tail)
        if tail_len >= 15:
            var extra_t = tail_len - 15
            while extra_t >= 255:
                out.append(UInt8(255))
                extra_t -= 255
            out.append(UInt8(extra_t))

        for j in range(tail_len):
            out.append(src[anchor + j])

        return out^

    @staticmethod
    def _compress_ultra_rc[origin: Origin](src: Span[UInt8, origin], max_window: Int = 33554432) -> List[UInt8]:
        var src_len = len(src)
        var enc = RangeEncoder(capacity=src_len // 2 + 1024)
        if src_len == 0:
            return enc.get_output()

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

        var mf = MatchFinder(max_window=262144, max_depth=6, nice_length=32)
        mf.init_prev(src_len)

        var rep0 = 1
        var rep1 = 1
        var rep2 = 1
        var rep3 = 1
        var state = 0
        var ip = 0
        var prev_byte: UInt8 = 0
        var consecutive_misses = 0

        while ip < src_len:
            var rem = src_len - ip

            if consecutive_misses >= 16 and rem > 16:
                var skip_count = min(consecutive_misses >> 4, 8)
                skip_count = min(skip_count, rem - 4)
                for _ in range(skip_count):
                    enc.encode_bit(is_match[state], 0)
                    var lit = src[ip]
                    var ctx = Int(prev_byte >> 4)
                    var ctx_base = ctx * 256
                    var tree_idx = 1
                    for b in range(7, -1, -1):
                        var bit = Int((lit >> UInt8(b)) & 1)
                        enc.encode_bit(lit_probs[ctx_base + tree_idx], bit)
                        tree_idx = (tree_idx << 1) | bit

                    state = state - 3 if state >= 7 else (state - 2 if state >= 4 else 0)
                    prev_byte = lit
                    ip += 1
                rem = src_len - ip
                if ip >= src_len:
                    break

            var best_rep_len = 0
            var best_rep_idx = 0
            if rem >= 2:
                if ip >= rep0 and src[ip] == src[ip - rep0] and src[ip + 1] == src[ip - rep0 + 1]:
                    best_rep_len = MatchFinder.count_match_simd(src, ip - rep0, ip, rem)
                    best_rep_idx = 0
                if ip >= rep1 and src[ip] == src[ip - rep1] and src[ip + 1] == src[ip - rep1 + 1]:
                    var l1 = MatchFinder.count_match_simd(src, ip - rep1, ip, rem)
                    if l1 > best_rep_len:
                        best_rep_len = l1
                        best_rep_idx = 1
                if ip >= rep2 and src[ip] == src[ip - rep2] and src[ip + 1] == src[ip - rep2 + 1]:
                    var l2 = MatchFinder.count_match_simd(src, ip - rep2, ip, rem)
                    if l2 > best_rep_len:
                        best_rep_len = l2
                        best_rep_idx = 2
                if ip >= rep3 and src[ip] == src[ip - rep3] and src[ip + 1] == src[ip - rep3 + 1]:
                    var l3 = MatchFinder.count_match_simd(src, ip - rep3, ip, rem)
                    if l3 > best_rep_len:
                        best_rep_len = l3
                        best_rep_idx = 3

            var m = Match(0, 0)
            if best_rep_len < 32 and rem >= 4:
                m = mf.find_match_deep(src, ip, rem)

            var use_rep = False
            var use_match = False
            var match_len = 0
            var match_offset = 0

            if (best_rep_len >= 3 and best_rep_len >= m.length) or (best_rep_len >= 2 and m.length < 3):
                use_rep = True
                match_len = min(best_rep_len, 273)
            elif m.length >= 4 and m.offset > 0:
                use_match = True
                match_len = min(m.length, 273)
                match_offset = m.offset

            if use_rep:
                enc.encode_bit(is_match[state], 1)
                enc.encode_bit(is_rep[state], 1)

                if best_rep_idx == 0:
                    enc.encode_bit(is_rep0[state], 0)
                else:
                    enc.encode_bit(is_rep0[state], 1)
                    if best_rep_idx == 1:
                        enc.encode_bit(is_rep1[state], 0)
                        var tmp = rep1
                        rep1 = rep0
                        rep0 = tmp
                    else:
                        enc.encode_bit(is_rep1[state], 1)
                        if best_rep_idx == 2:
                            enc.encode_bit(is_rep2[state], 0)
                            var tmp = rep2
                            rep2 = rep1
                            rep1 = rep0
                            rep0 = tmp
                        else:
                            enc.encode_bit(is_rep2[state], 1)
                            var tmp = rep3
                            rep3 = rep2
                            rep2 = rep1
                            rep1 = rep0
                            rep0 = tmp

                var len_val = match_len - 2
                if len_val < 8:
                    enc.encode_bit(len_choice, 0)
                    var tree_idx = 1
                    for b in range(2, -1, -1):
                        var bit = (len_val >> b) & 1
                        enc.encode_bit(len_low[tree_idx], bit)
                        tree_idx = (tree_idx << 1) | bit
                elif len_val < 16:
                    enc.encode_bit(len_choice, 1)
                    enc.encode_bit(len_choice2, 0)
                    var sub = len_val - 8
                    var tree_idx = 1
                    for b in range(2, -1, -1):
                        var bit = (sub >> b) & 1
                        enc.encode_bit(len_mid[tree_idx], bit)
                        tree_idx = (tree_idx << 1) | bit
                else:
                    enc.encode_bit(len_choice, 1)
                    enc.encode_bit(len_choice2, 1)
                    enc.encode_direct_bits(UInt32(len_val - 16), 8)

                state = 8 if state < 7 else 11
                mf.insert(src, ip + 1, match_len - 1)
                ip += match_len
                prev_byte = src[ip - 1]
                consecutive_misses = 0

            elif use_match:
                enc.encode_bit(is_match[state], 1)
                enc.encode_bit(is_rep[state], 0)

                var len_val = match_len - 2
                if len_val < 8:
                    enc.encode_bit(len_choice, 0)
                    var tree_idx = 1
                    for b in range(2, -1, -1):
                        var bit = (len_val >> b) & 1
                        enc.encode_bit(len_low[tree_idx], bit)
                        tree_idx = (tree_idx << 1) | bit
                elif len_val < 16:
                    enc.encode_bit(len_choice, 1)
                    enc.encode_bit(len_choice2, 0)
                    var sub = len_val - 8
                    var tree_idx = 1
                    for b in range(2, -1, -1):
                        var bit = (sub >> b) & 1
                        enc.encode_bit(len_mid[tree_idx], bit)
                        tree_idx = (tree_idx << 1) | bit
                else:
                    enc.encode_bit(len_choice, 1)
                    enc.encode_bit(len_choice2, 1)
                    enc.encode_direct_bits(UInt32(len_val - 16), 8)

                # Slot-based offset encoding
                var pos_slot: Int
                var num_direct = 0
                var direct_val = 0
                if match_offset <= 4:
                    pos_slot = match_offset - 1
                else:
                    var msb = 31 - Int(count_leading_zeros(UInt32(match_offset)))
                    pos_slot = (msb << 1) | Int((match_offset >> (msb - 1)) & 1)
                    num_direct = (pos_slot >> 1) - 1
                    var base_val = (2 | (pos_slot & 1)) << num_direct
                    direct_val = match_offset - base_val

                var len_to_pos_state = min(len_val, 3)
                var slot_ctx_base = len_to_pos_state * 64
                var slot_tree = 1
                for b in range(5, -1, -1):
                    var bit = (pos_slot >> b) & 1
                    enc.encode_bit(pos_slot_probs[slot_ctx_base + slot_tree], bit)
                    slot_tree = (slot_tree << 1) | bit

                if num_direct > 0:
                    enc.encode_direct_bits(UInt32(direct_val), num_direct)

                rep3 = rep2
                rep2 = rep1
                rep1 = rep0
                rep0 = match_offset

                state = 7 if state < 7 else 10
                mf.insert(src, ip + 1, match_len - 1)
                ip += match_len
                prev_byte = src[ip - 1]
                consecutive_misses = 0

            else:
                enc.encode_bit(is_match[state], 0)
                var lit = src[ip]
                var ctx = Int(prev_byte >> 4)
                var ctx_base = ctx * 256
                var tree_idx = 1
                for b in range(7, -1, -1):
                    var bit = Int((lit >> UInt8(b)) & 1)
                    enc.encode_bit(lit_probs[ctx_base + tree_idx], bit)
                    tree_idx = (tree_idx << 1) | bit

                state = state - 3 if state >= 7 else (state - 2 if state >= 4 else 0)
                prev_byte = lit
                ip += 1
                consecutive_misses += 1

        return enc.get_output()


struct Decompressor:
    var xxh: XXH3_64

    def __init__(out self):
        self.xxh = XXH3_64()

    def decompress[origin: Origin](self, mode: UInt8, src: Span[UInt8, origin], uncompressed_size: Int, expected_checksum: UInt64) raises -> List[UInt8]:
        var dst = List[UInt8](capacity=uncompressed_size)
        for _ in range(uncompressed_size):
            dst.append(0)
        var dst_ptr = Pointer[UInt8, MutUntrackedOrigin](unsafe_from_address=Int(dst.unsafe_ptr()))
        self.decompress_to_ptr(mode, src, dst_ptr, uncompressed_size, expected_checksum)
        return dst^

    def decompress_to_ptr[origin: Origin](self, mode: UInt8, src: Span[UInt8, origin], dst_ptr: Pointer[UInt8, MutUntrackedOrigin], uncompressed_size: Int, expected_checksum: UInt64) raises:
        if mode == ChunkMode.RAW:
            for i in range(uncompressed_size):
                dst_ptr.unsafe_offset(i)[] = src[i]
        elif mode == ChunkMode.FAST or mode == ChunkMode.ULTRA:
            Self._decompress_lz_ptr(src, dst_ptr, uncompressed_size)
        elif mode == ChunkMode.ULTRA_RC:
            Self._decompress_ultra_rc_ptr(src, dst_ptr, uncompressed_size)
        elif mode == ChunkMode.ULTRA_RC_BCJ:
            Self._decompress_ultra_rc_ptr(src, dst_ptr, uncompressed_size)
            BCJFilter.inverse_ptr(dst_ptr, uncompressed_size)
        else:
            raise Error("Unknown chunk compression mode: " + String(mode))

        var actual_checksum = self.xxh.compute(Span[UInt8, MutUntrackedOrigin](unsafe_ptr=dst_ptr, length=uncompressed_size))
        if actual_checksum != expected_checksum:
            raise Error("Chunk integrity verification failed: expected " + hex(expected_checksum) + ", got " + hex(actual_checksum))

    @staticmethod
    def _decompress_lz[origin: Origin](src: Span[UInt8, origin], uncompressed_size: Int) -> List[UInt8]:
        var dst = List[UInt8](capacity=uncompressed_size)
        for _ in range(uncompressed_size):
            dst.append(0)
        var dst_ptr = Pointer[UInt8, MutUntrackedOrigin](unsafe_from_address=Int(dst.unsafe_ptr()))
        Self._decompress_lz_ptr(src, dst_ptr, uncompressed_size)
        return dst^

    @staticmethod
    def _decompress_lz_ptr[origin: Origin](src: Span[UInt8, origin], dst_ptr: Pointer[UInt8, MutUntrackedOrigin], uncompressed_size: Int):
        for i in range(uncompressed_size):
            dst_ptr.unsafe_offset(i)[] = 0

        var sp = 0
        var dp = 0
        var src_len = len(src)

        while dp < uncompressed_size and sp < src_len:
            var token = Int(src[sp])
            sp += 1
            var lit_len = (token >> 4) & 0x0F
            if lit_len == 15:
                while sp < src_len and src[sp] == 255:
                    lit_len += 255
                    sp += 1
                if sp < src_len:
                    lit_len += Int(src[sp])
                    sp += 1

            for _ in range(lit_len):
                if sp < src_len and dp < uncompressed_size:
                    dst_ptr.unsafe_offset(dp)[] = src[sp]
                    dp += 1
                    sp += 1

            if dp >= uncompressed_size or sp >= src_len:
                break

            var offset = Int(src[sp]) | (Int(src[sp + 1]) << 8)
            sp += 2

            var match_len = (token & 0x0F)
            if match_len == 15:
                while sp < src_len and src[sp] == 255:
                    match_len += 255
                    sp += 1
                if sp < src_len:
                    match_len += Int(src[sp])
                    sp += 1
            match_len += 4

            var match_src = dp - offset
            for _ in range(match_len):
                if dp < uncompressed_size:
                    dst_ptr.unsafe_offset(dp)[] = dst_ptr.unsafe_offset(match_src)[]
                    dp += 1
                    match_src += 1

    @staticmethod
    def _decompress_ultra_rc[origin: Origin](src: Span[UInt8, origin], uncompressed_size: Int) -> List[UInt8]:
        var dst = List[UInt8](capacity=uncompressed_size)
        for _ in range(uncompressed_size):
            dst.append(0)
        if uncompressed_size == 0:
            return dst^
        var dst_ptr = Pointer[UInt8, MutUntrackedOrigin](unsafe_from_address=Int(dst.unsafe_ptr()))
        Self._decompress_ultra_rc_ptr(src, dst_ptr, uncompressed_size)
        return dst^

    @staticmethod
    def _decompress_ultra_rc_ptr[origin: Origin](src: Span[UInt8, origin], dst_ptr: Pointer[UInt8, MutUntrackedOrigin], uncompressed_size: Int):
        for i in range(uncompressed_size):
            dst_ptr.unsafe_offset(i)[] = 0

        if uncompressed_size == 0:
            return

        var dec = RangeDecoder(src)

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
            var bit_match = dec.decode_bit(is_match[state], src)
            if bit_match == 0:
                var ctx = Int(prev_byte >> 4)
                var ctx_base = ctx * 256
                var tree_idx = 1
                var symbol: UInt8 = 0
                for _ in range(8):
                    var bit = dec.decode_bit(lit_probs[ctx_base + tree_idx], src)
                    symbol = (symbol << 1) | UInt8(bit)
                    tree_idx = (tree_idx << 1) | bit
                dst_ptr.unsafe_offset(dp)[] = symbol
                dp += 1
                prev_byte = symbol
                state = state - 3 if state >= 7 else (state - 2 if state >= 4 else 0)
            else:
                var bit_rep = dec.decode_bit(is_rep[state], src)
                var offset = 0
                if bit_rep == 1:
                    var bit_rep0 = dec.decode_bit(is_rep0[state], src)
                    if bit_rep0 == 0:
                        offset = rep0
                    else:
                        var bit_rep1 = dec.decode_bit(is_rep1[state], src)
                        if bit_rep1 == 0:
                            offset = rep1
                            var tmp = rep1
                            rep1 = rep0
                            rep0 = tmp
                        else:
                            var bit_rep2 = dec.decode_bit(is_rep2[state], src)
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
                var bit_choice = dec.decode_bit(len_choice, src)
                var len_val: Int
                if bit_choice == 0:
                    var tree_idx = 1
                    for _ in range(3):
                        var b = dec.decode_bit(len_low[tree_idx], src)
                        tree_idx = (tree_idx << 1) | b
                    len_val = tree_idx - 8
                    match_len = len_val + 2
                else:
                    var bit_choice2 = dec.decode_bit(len_choice2, src)
                    if bit_choice2 == 0:
                        var tree_idx = 1
                        for _ in range(3):
                            var b = dec.decode_bit(len_mid[tree_idx], src)
                            tree_idx = (tree_idx << 1) | b
                        len_val = (tree_idx - 8) + 8
                        match_len = len_val + 2
                    else:
                        var raw_len = Int(dec.decode_direct_bits(8, src))
                        len_val = raw_len + 16
                        match_len = len_val + 2

                if bit_rep == 0:
                    var len_to_pos_state = min(len_val, 3)
                    var slot_ctx_base = len_to_pos_state * 64
                    var slot_tree = 1
                    for _ in range(6):
                        var b = dec.decode_bit(pos_slot_probs[slot_ctx_base + slot_tree], src)
                        slot_tree = (slot_tree << 1) | b
                    var pos_slot = slot_tree - 64
                    if pos_slot < 4:
                        offset = pos_slot + 1
                    else:
                        var num_direct = (pos_slot >> 1) - 1
                        var base_val = (2 | (pos_slot & 1)) << num_direct
                        var direct = Int(dec.decode_direct_bits(num_direct, src))
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

