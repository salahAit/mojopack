from std.math import log2
from std.collections import Span
from std.origin import Origin
from mojopack.bitstream import BitWriter, BitReader

struct EntropyUtils:
    @staticmethod
    def estimate_shannon_entropy[origin: Origin](data: Span[UInt8, origin], max_sample: Int = 65536) -> Float64:
        var sample_len = min(len(data), max_sample)
        if sample_len == 0:
            return 0.0

        var counts = List[Int](capacity=256)
        for _ in range(256):
            counts.append(0)

        for i in range(sample_len):
            counts[Int(data[i])] += 1

        var ent: Float64 = 0.0
        var total_f = Float64(sample_len)

        for i in range(256):
            var c = counts[i]
            if c > 0:
                var p = Float64(c) / total_f
                ent -= p * log2(p)

        return ent

    @staticmethod
    def is_incompressible[origin: Origin](data: Span[UInt8, origin]) -> Bool:
        if len(data) < 512:
            return False
        var ent = Self.estimate_shannon_entropy(data, 65536)
        return ent > 7.85


struct HuffmanEncoder:
    var lengths: List[Int]
    var codes: List[UInt32]

    def __init__(out self):
        self.lengths = List[Int](capacity=256)
        self.codes = List[UInt32](capacity=256)
        for _ in range(256):
            self.lengths.append(0)
            self.codes.append(0)

    def build_tree(mut self, freqs: List[Int]):
        for i in range(256):
            self.lengths[i] = 0
            self.codes[i] = 0

        var active = List[Int]()
        for i in range(256):
            if freqs[i] > 0:
                active.append(i)

        if len(active) == 0:
            return
        if len(active) == 1:
            self.lengths[active[0]] = 1
            self.codes[active[0]] = 0
            return

        var weights = List[Int]()
        var lefts = List[Int]()
        var rights = List[Int]()
        var syms = List[Int]()

        for i in range(len(active)):
            var s = active[i]
            weights.append(freqs[s])
            syms.append(s)
            lefts.append(-1)
            rights.append(-1)

        var num_nodes = len(weights)
        var active_nodes = List[Int]()
        for i in range(num_nodes):
            active_nodes.append(i)

        while len(active_nodes) > 1:
            var min1_idx = 0
            var min2_idx = 1
            if weights[active_nodes[min1_idx]] > weights[active_nodes[min2_idx]]:
                min1_idx = 1
                min2_idx = 0

            for i in range(2, len(active_nodes)):
                var node = active_nodes[i]
                if weights[node] < weights[active_nodes[min1_idx]]:
                    min2_idx = min1_idx
                    min1_idx = i
                elif weights[node] < weights[active_nodes[min2_idx]]:
                    min2_idx = i

            var n1 = active_nodes[min1_idx]
            var n2 = active_nodes[min2_idx]

            var parent = num_nodes
            num_nodes += 1
            weights.append(weights[n1] + weights[n2])
            syms.append(-1)
            lefts.append(n1)
            rights.append(n2)

            var new_active = List[Int]()
            for i in range(len(active_nodes)):
                if i != min1_idx and i != min2_idx:
                    new_active.append(active_nodes[i])
            new_active.append(parent)
            active_nodes = new_active^

        var root = active_nodes[0]
        var stack_node = List[Int]()
        var stack_depth = List[Int]()
        stack_node.append(root)
        stack_depth.append(0)

        while len(stack_node) > 0:
            var node = stack_node.pop()
            var depth = stack_depth.pop()

            if syms[node] >= 0:
                var s = syms[node]
                self.lengths[s] = min(depth, 15)
            else:
                if lefts[node] >= 0:
                    stack_node.append(lefts[node])
                    stack_depth.append(depth + 1)
                if rights[node] >= 0:
                    stack_node.append(rights[node])
                    stack_depth.append(depth + 1)

        var bl_count = List[Int](capacity=16)
        for _ in range(16):
            bl_count.append(0)
        for i in range(256):
            if self.lengths[i] > 0:
                bl_count[self.lengths[i]] += 1

        var next_code = List[UInt32](capacity=16)
        for _ in range(16):
            next_code.append(0)
        var code: UInt32 = 0
        for bits in range(1, 16):
            code = (code + UInt32(bl_count[bits - 1])) << 1
            next_code[bits] = code

        for i in range(256):
            var len_i = self.lengths[i]
            if len_i > 0:
                self.codes[i] = next_code[len_i]
                next_code[len_i] += 1


struct HuffmanDecoder:
    var lengths: List[Int]
    var table: List[Int]
    var tree_left: List[Int]
    var tree_right: List[Int]
    var tree_sym: List[Int]

    def __init__(out self):
        self.lengths = List[Int](capacity=256)
        self.table = List[Int](capacity=256)
        for _ in range(256):
            self.lengths.append(0)
            self.table.append(-1)
        self.tree_left = List[Int]()
        self.tree_right = List[Int]()
        self.tree_sym = List[Int]()

    def build(mut self, lengths: List[Int], codes: List[UInt32]):
        for i in range(256):
            self.lengths[i] = lengths[i]
            self.table[i] = -1

        self.tree_left = List[Int]()
        self.tree_right = List[Int]()
        self.tree_sym = List[Int]()
        self.tree_left.append(-1)
        self.tree_right.append(-1)
        self.tree_sym.append(-1)

        for sym in range(256):
            var l = lengths[sym]
            if l == 0:
                continue
            var c = Int(codes[sym])

            if l <= 8:
                var step = 1 << l
                var idx = c
                while idx < 256:
                    self.table[idx] = (sym << 8) | l
                    idx += step
            else:
                var node = 0
                for bit_pos in range(l):
                    var bit = (c >> bit_pos) & 1
                    if bit == 0:
                        if self.tree_left[node] == -1:
                            var new_node = len(self.tree_sym)
                            self.tree_left.append(-1)
                            self.tree_right.append(-1)
                            self.tree_sym.append(-1)
                            self.tree_left[node] = new_node
                        node = self.tree_left[node]
                    else:
                        if self.tree_right[node] == -1:
                            var new_node = len(self.tree_sym)
                            self.tree_left.append(-1)
                            self.tree_right.append(-1)
                            self.tree_sym.append(-1)
                            self.tree_right[node] = new_node
                        node = self.tree_right[node]
                self.tree_sym[node] = sym

    def decode_symbol[origin: Origin](mut self, mut br: BitReader, data: Span[UInt8, origin]) -> Int:
        var peek = Int(br.peek_bits(data, 8))
        var entry = self.table[peek]
        if entry >= 0:
            var l = entry & 0xFF
            var sym = entry >> 8
            br.drop_bits(l)
            return sym

        var node = 0
        while self.tree_sym[node] == -1:
            var bit = Int(br.read_bits(data, 1))
            if bit == 0:
                node = self.tree_left[node]
            else:
                node = self.tree_right[node]
            if node < 0:
                return 0
        return self.tree_sym[node]


struct RangeEncoder:
    var low: UInt64
    var range: UInt32
    var cache_byte: UInt8
    var cache_size: UInt32
    var out: List[UInt8]

    def __init__(out self, capacity: Int = 65536):
        self.low = 0
        self.range = 0xFFFFFFFF
        self.cache_byte = 0
        self.cache_size = 1
        self.out = List[UInt8](capacity=capacity)

    @always_inline
    def encode_bit(mut self, mut prob: UInt16, bit: Int):
        var bound: UInt32 = (self.range >> 11) * UInt32(prob)
        if bit == 0:
            self.range = bound
            prob += (UInt16(2048) - prob) >> 5
        else:
            self.low += UInt64(bound)
            self.range -= bound
            prob -= prob >> 5

        while self.range < 0x01000000:
            self._shift_low()
            self.range <<= 8

    @always_inline
    def encode_direct_bits(mut self, value: UInt32, num_bits: Int):
        for i in range(num_bits - 1, -1, -1):
            var bit = Int((value >> UInt32(i)) & 1)
            self.range >>= 1
            if bit != 0:
                self.low += UInt64(self.range)
            while self.range < 0x01000000:
                self._shift_low()
                self.range <<= 8

    @always_inline
    def _shift_low(mut self):
        var low_hi = UInt32(self.low >> 32)
        if low_hi != 0 or self.low < 0xFF000000:
            var temp = self.cache_byte
            while True:
                self.out.append(temp + UInt8(low_hi & 0xFF))
                temp = 0xFF
                self.cache_size -= 1
                if self.cache_size == 0:
                    break
            self.cache_byte = UInt8((self.low >> 24) & 0xFF)
        self.cache_size += 1
        self.low = (self.low & 0x00FFFFFF) << 8

    def flush(mut self):
        for _ in range(5):
            self._shift_low()

    def get_output(mut self) -> List[UInt8]:
        self.flush()
        var res = self.out.copy()
        return res^


struct RangeDecoder:
    var code: UInt32
    var range: UInt32
    var pos: Int

    def __init__(out self, data: Span[UInt8, _]):
        self.code = 0
        self.range = 0xFFFFFFFF
        self.pos = 0
        for _ in range(5):
            var b = data[self.pos] if self.pos < len(data) else 0
            self.code = (self.code << 8) | UInt32(b)
            self.pos += 1

    @always_inline
    def decode_bit(mut self, mut prob: UInt16, data: Span[UInt8, _]) -> Int:
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
            var b = data[self.pos] if self.pos < len(data) else 0
            self.pos += 1
            self.code = (self.code << 8) | UInt32(b)
            self.range <<= 8

        return bit

    @always_inline
    def decode_direct_bits(mut self, num_bits: Int, data: Span[UInt8, _]) -> UInt32:
        var res: UInt32 = 0
        for _ in range(num_bits):
            self.range >>= 1
            var bit: UInt32 = 0
            if self.code >= self.range:
                self.code -= self.range
                bit = 1
            res = (res << 1) | bit
            while self.range < 0x01000000:
                var b = data[self.pos] if self.pos < len(data) else 0
                self.pos += 1
                self.code = (self.code << 8) | UInt32(b)
                self.range <<= 8
        return res

