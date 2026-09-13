from std.collections import Span
from std.origin import Origin, MutUntrackedOrigin

struct BCJFilter:
    @staticmethod
    def is_executable[origin: Origin](data: Span[UInt8, origin]) -> Bool:
        if len(data) >= 4:
            # ELF magic: 0x7F, 'E', 'L', 'F'
            if data[0] == 0x7F and data[1] == UInt8(ord("E")) and data[2] == UInt8(ord("L")) and data[3] == UInt8(ord("F")):
                return True
            # PE magic: 'M', 'Z'
            if data[0] == UInt8(ord("M")) and data[1] == UInt8(ord("Z")):
                return True
        return False

    @staticmethod
    def forward(mut buf: List[UInt8]):
        var n = len(buf)
        var i = 0
        while i + 5 <= n:
            var b = buf[i]
            if b == 0xE8 or b == 0xE9:
                var b4 = buf[i + 4]
                if b4 == 0x00 or b4 == 0xFF:
                    var src = (UInt32(b4) << 24) | (UInt32(buf[i+3]) << 16) | (UInt32(buf[i+2]) << 8) | UInt32(buf[i+1])
                    var dest = src + UInt32(i + 5)
                    buf[i+1] = UInt8(dest & 0xFF)
                    buf[i+2] = UInt8((dest >> 8) & 0xFF)
                    buf[i+3] = UInt8((dest >> 16) & 0xFF)
                    buf[i+4] = UInt8((~(((dest >> 24) & 1) - 1)) & 0xFF)
                    i += 5
                    continue
            i += 1

    @staticmethod
    def inverse_ptr(buf_ptr: Pointer[UInt8, MutUntrackedOrigin], n: Int):
        var i = 0
        while i + 5 <= n:
            var b = buf_ptr.unsafe_offset(i)[]
            if b == 0xE8 or b == 0xE9:
                var b4 = buf_ptr.unsafe_offset(i + 4)[]
                if b4 == 0x00 or b4 == 0xFF:
                    var src = (UInt32(b4) << 24) | (UInt32(buf_ptr.unsafe_offset(i+3)[]) << 16) | (UInt32(buf_ptr.unsafe_offset(i+2)[]) << 8) | UInt32(buf_ptr.unsafe_offset(i+1)[])
                    var dest = src - UInt32(i + 5)
                    buf_ptr.unsafe_offset(i+1)[] = UInt8(dest & 0xFF)
                    buf_ptr.unsafe_offset(i+2)[] = UInt8((dest >> 8) & 0xFF)
                    buf_ptr.unsafe_offset(i+3)[] = UInt8((dest >> 16) & 0xFF)
                    buf_ptr.unsafe_offset(i+4)[] = UInt8((~(((dest >> 24) & 1) - 1)) & 0xFF)
                    i += 5
                    continue
            i += 1

    @staticmethod
    def inverse(mut buf: List[UInt8]):
        Self.inverse_ptr(Pointer[UInt8, MutUntrackedOrigin](unsafe_from_address=Int(buf.unsafe_ptr())), len(buf))

