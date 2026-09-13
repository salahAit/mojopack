from std.collections import Span
from std.origin import Origin

struct BitWriter:
    var buf: List[UInt8]
    var bit_buf: UInt64
    var bit_count: Int

    def __init__(out self):
        self.buf = List[UInt8]()
        self.bit_buf = 0
        self.bit_count = 0

    def __init__(out self, capacity: Int):
        self.buf = List[UInt8](capacity=capacity)
        self.bit_buf = 0
        self.bit_count = 0

    def write_bits(mut self, value: UInt64, count: Int):
        if count <= 0:
            return
        var mask: UInt64 = (UInt64(1) << UInt64(count)) - 1 if count < 64 else 0xFFFFFFFFFFFFFFFF
        self.bit_buf |= (value & mask) << UInt64(self.bit_count)
        self.bit_count += count
        while self.bit_count >= 8:
            self.buf.append(UInt8(self.bit_buf & 0xFF))
            self.bit_buf >>= UInt64(8)
            self.bit_count -= 8

    def write_byte(mut self, b: UInt8):
        self.write_bits(UInt64(b), 8)

    def flush(mut self):
        if self.bit_count > 0:
            self.buf.append(UInt8(self.bit_buf & 0xFF))
            self.bit_buf = 0
            self.bit_count = 0


struct BitReader:
    var bit_buf: UInt64
    var bit_count: Int
    var pos: Int

    def __init__(out self):
        self.bit_buf = 0
        self.bit_count = 0
        self.pos = 0

    def read_bits[origin: Origin](mut self, data: Span[UInt8, origin], count: Int) -> UInt64:
        if count <= 0:
            return 0
        while self.bit_count < count and self.pos < len(data):
            self.bit_buf |= UInt64(data[self.pos]) << UInt64(self.bit_count)
            self.pos += 1
            self.bit_count += 8
        var mask: UInt64 = (UInt64(1) << UInt64(count)) - 1 if count < 64 else 0xFFFFFFFFFFFFFFFF
        var res = self.bit_buf & mask
        self.bit_buf >>= UInt64(count)
        self.bit_count -= count
        return res

    def peek_bits[origin: Origin](mut self, data: Span[UInt8, origin], count: Int) -> UInt64:
        if count <= 0:
            return 0
        while self.bit_count < count and self.pos < len(data):
            self.bit_buf |= UInt64(data[self.pos]) << UInt64(self.bit_count)
            self.pos += 1
            self.bit_count += 8
        var mask: UInt64 = (UInt64(1) << UInt64(count)) - 1 if count < 64 else 0xFFFFFFFFFFFFFFFF
        return self.bit_buf & mask

    def drop_bits(mut self, count: Int):
        if count <= 0:
            return
        self.bit_buf >>= UInt64(count)
        self.bit_count -= count
