from std.builtin.simd import SIMD
from std.memory.unsafe import pack_bits
from std.bit import count_trailing_zeros
from std.collections import Span
from std.origin import Origin

struct Match:
    var offset: Int
    var length: Int

    def __init__(out self, offset: Int, length: Int):
        self.offset = offset
        self.length = length

    def __init__(out self):
        self.offset = 0
        self.length = 0


struct MatchFinder:
    comptime HASH_BITS: Int = 16
    comptime HASH_SIZE: Int = 1 << Self.HASH_BITS
    comptime HASH_MASK: Int = Self.HASH_SIZE - 1
    comptime HASH_PRIME: UInt32 = 0x1E35A7BD
    comptime MIN_MATCH: Int = 4
    comptime WINDOW_SIZE: Int = 262144
    comptime WINDOW_MASK: Int = Self.WINDOW_SIZE - 1
    comptime EMPTY_SENTINEL: UInt32 = 0xFFFFFFFF

    var head: List[UInt32]
    var prev: List[UInt32]
    var max_window: Int
    var max_depth: Int
    var nice_length: Int

    def __init__(out self, max_window: Int = 262144, max_depth: Int = 6, nice_length: Int = 32):
        self.max_window = min(max_window, Self.WINDOW_SIZE)
        self.max_depth = max_depth
        self.nice_length = nice_length
        self.head = List[UInt32](capacity=Self.HASH_SIZE)
        for _ in range(Self.HASH_SIZE):
            self.head.append(Self.EMPTY_SENTINEL)
        self.prev = List[UInt32](capacity=Self.WINDOW_SIZE)
        for _ in range(Self.WINDOW_SIZE):
            self.prev.append(Self.EMPTY_SENTINEL)

    def init_prev(mut self, size: Int):
        pass

    def reset(mut self):
        for i in range(Self.HASH_SIZE):
            self.head[i] = Self.EMPTY_SENTINEL
        for i in range(Self.WINDOW_SIZE):
            self.prev[i] = Self.EMPTY_SENTINEL

    @staticmethod
    @always_inline
    def hash4[origin: Origin](data: Span[UInt8, origin], pos: Int) -> Int:
        var val = UInt32(data[pos]) | (UInt32(data[pos + 1]) << 8) | (UInt32(data[pos + 2]) << 16) | (UInt32(data[pos + 3]) << 24)
        var h = (val * Self.HASH_PRIME) >> UInt32(32 - Self.HASH_BITS)
        return Int(h & UInt32(Self.HASH_MASK))

    @staticmethod
    @always_inline
    def count_match_simd[origin: Origin](data: Span[UInt8, origin], pos1: Int, pos2: Int, max_len: Int) -> Int:
        var matched = 0
        var ptr = data.unsafe_ptr()

        # 32-byte direct AVX2 SIMD vector comparison loop
        while matched + 32 <= max_len:
            var v1 = ptr.unsafe_offset(pos1 + matched).unsafe_load[width=32]()
            var v2 = ptr.unsafe_offset(pos2 + matched).unsafe_load[width=32]()
            if v1 != v2:
                var ne = v1.ne(v2)
                var bits = pack_bits(ne)
                return matched + Int(count_trailing_zeros(bits))
            matched += 32

        # 16-byte SIMD vector comparison
        if matched + 16 <= max_len:
            var v1 = ptr.unsafe_offset(pos1 + matched).unsafe_load[width=16]()
            var v2 = ptr.unsafe_offset(pos2 + matched).unsafe_load[width=16]()
            if v1 != v2:
                var ne = v1.ne(v2)
                var bits = pack_bits(ne)
                return matched + Int(count_trailing_zeros(bits))
            matched += 16

        # Remainder scalar comparison
        while matched < max_len:
            if data[pos1 + matched] != data[pos2 + matched]:
                break
            matched += 1

        return matched

    def find_match_fast[origin: Origin](mut self, data: Span[UInt8, origin], pos: Int, bytes_remaining: Int) -> Match:
        if bytes_remaining < Self.MIN_MATCH:
            return Match(0, 0)

        var h = Self.hash4(data, pos)
        var cand = self.head[h]
        self.head[h] = UInt32(pos)
        self.prev[pos & Self.WINDOW_MASK] = cand

        if cand == Self.EMPTY_SENTINEL:
            return Match(0, 0)

        var cand_int = Int(cand)
        var offset = pos - cand_int
        if offset <= 0 or offset > self.max_window:
            return Match(0, 0)

        # Fast 4-byte check
        if data[cand_int] != data[pos] or data[cand_int + 3] != data[pos + 3]:
            return Match(0, 0)

        var match_len = Self.count_match_simd(data, cand_int, pos, bytes_remaining)
        if match_len >= Self.MIN_MATCH:
            return Match(offset, match_len)

        return Match(0, 0)

    def find_match_deep[origin: Origin](mut self, data: Span[UInt8, origin], pos: Int, bytes_remaining: Int) -> Match:
        if bytes_remaining < Self.MIN_MATCH:
            return Match(0, 0)

        var h = Self.hash4(data, pos)
        var cand = self.head[h]
        self.head[h] = UInt32(pos)
        self.prev[pos & Self.WINDOW_MASK] = cand

        if cand == Self.EMPTY_SENTINEL:
            return Match(0, 0)

        var best_len = 0
        var best_offset = 0
        var depth = 0
        var cand_int = Int(cand)

        while depth < self.max_depth:
            var offset = pos - cand_int
            if offset <= 0 or offset > self.max_window:
                break

            if data[cand_int] == data[pos] and data[cand_int + best_len] == data[pos + best_len]:
                var match_len = Self.count_match_simd(data, cand_int, pos, bytes_remaining)
                if match_len > best_len:
                    best_len = match_len
                    best_offset = offset
                    if best_len >= bytes_remaining or best_len >= self.nice_length:
                        break

            var next_cand = self.prev[cand_int & Self.WINDOW_MASK]
            if next_cand == Self.EMPTY_SENTINEL or Int(next_cand) >= cand_int:
                break
            cand_int = Int(next_cand)
            depth += 1

        if best_len >= Self.MIN_MATCH:
            return Match(best_offset, best_len)

        return Match(0, 0)

    def insert[origin: Origin](mut self, data: Span[UInt8, origin], start_pos: Int, count: Int):
        var limit = min(start_pos + count, len(data) - Self.MIN_MATCH + 1)
        if count <= 8:
            for p in range(start_pos, limit):
                var h = Self.hash4(data, p)
                var cand = self.head[h]
                self.head[h] = UInt32(p)
                self.prev[p & Self.WINDOW_MASK] = cand
        else:
            # Strided insertion for long matches:
            # Always insert first 2 positions
            for p in range(start_pos, min(start_pos + 2, limit)):
                var h = Self.hash4(data, p)
                var cand = self.head[h]
                self.head[h] = UInt32(p)
                self.prev[p & Self.WINDOW_MASK] = cand
            # Step by 3 through the body
            var p = start_pos + 2
            while p < limit - 2:
                var h = Self.hash4(data, p)
                var cand = self.head[h]
                self.head[h] = UInt32(p)
                self.prev[p & Self.WINDOW_MASK] = cand
                p += 3
            # Always insert last 2 positions
            for lp in range(max(start_pos + 2, limit - 2), limit):
                var h = Self.hash4(data, lp)
                var cand = self.head[h]
                self.head[h] = UInt32(lp)
                self.prev[lp & Self.WINDOW_MASK] = cand



