from std.builtin.simd import SIMD
from std.collections import Span
from std.origin import Origin

struct CRC32:
    var table: List[UInt32]

    def __init__(out self):
        self.table = List[UInt32](capacity=256)
        for i in range(256):
            var c = UInt32(i)
            for _ in range(8):
                if (c & 1) != 0:
                    c = 0xEDB88320 ^ (c >> 1)
                else:
                    c = c >> 1
            self.table.append(c)

    def compute[origin: Origin](self, data: Span[UInt8, origin]) -> UInt32:
        var crc: UInt32 = 0xFFFFFFFF
        for i in range(len(data)):
            var idx = Int((crc ^ UInt32(data[i])) & 0xFF)
            crc = self.table[idx] ^ (crc >> 8)
        return crc ^ 0xFFFFFFFF

    def compute_ptr[origin: Origin](self, p: Pointer[UInt8, origin], length: Int) -> UInt32:
        var crc: UInt32 = 0xFFFFFFFF
        for i in range(length):
            var idx = Int((crc ^ UInt32(p.unsafe_offset(i)[])) & 0xFF)
            crc = self.table[idx] ^ (crc >> 8)
        return crc ^ 0xFFFFFFFF


struct XXH3_64:
    comptime PRIME64_1: UInt64 = 0x9E3779B185EBCA87
    comptime PRIME64_2: UInt64 = 0xC2B2AE3D27D4EB4F
    comptime PRIME64_3: UInt64 = 0x165667B19E3779F9
    comptime PRIME64_4: UInt64 = 0x85EBCA77C2B2AE63
    comptime PRIME64_5: UInt64 = 0x27D4EB2F165667C5

    def __init__(out self):
        pass

    @staticmethod
    def _rotl(v: UInt64, r: UInt64) -> UInt64:
        return (v << r) | (v >> (UInt64(64) - r))

    def compute[origin: Origin](self, data: Span[UInt8, origin]) -> UInt64:
        var length = len(data)
        if length == 0:
            return Self.PRIME64_5

        var h64: UInt64 = UInt64(length) * Self.PRIME64_1
        var idx = 0

        # Process 32-byte blocks
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

        # Process 8-byte blocks
        while idx + 8 <= length:
            var v = UInt64(data[idx]) | (UInt64(data[idx+1]) << 8) | (UInt64(data[idx+2]) << 16) | (UInt64(data[idx+3]) << 24) | (UInt64(data[idx+4]) << 32) | (UInt64(data[idx+5]) << 40) | (UInt64(data[idx+6]) << 48) | (UInt64(data[idx+7]) << 56)
            var k1 = Self._rotl(v * Self.PRIME64_2, 31) * Self.PRIME64_1
            h64 ^= k1
            h64 = Self._rotl(h64, 27) * Self.PRIME64_1 + Self.PRIME64_4
            idx += 8

        # Remaining bytes
        while idx < length:
            h64 ^= UInt64(data[idx]) * Self.PRIME64_5
            h64 = Self._rotl(h64, 11) * Self.PRIME64_1
            idx += 1

        # Avalanche
        h64 ^= h64 >> UInt64(33)
        h64 *= Self.PRIME64_2
        h64 ^= h64 >> UInt64(29)
        h64 *= Self.PRIME64_3
        h64 ^= h64 >> UInt64(32)

        return h64
