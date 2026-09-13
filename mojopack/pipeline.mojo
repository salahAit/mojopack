from std.runtime.asyncrt import TaskGroup, parallelism_level
from std.collections import Span
from std.origin import Origin, MutUntrackedOrigin
from std.memory.alloc import alloc, dealloc, Layout
from mojopack.compressor import Compressor, CompressedChunk

async def _compress_chunk_task(chunk_idx: Int, in_addr: Int, in_len: Int, level: Int, out_chunks_addr: Int):
    var in_ptr = Pointer[UInt8, MutUntrackedOrigin](unsafe_from_address=in_addr)
    var in_span = Span[UInt8, MutUntrackedOrigin](unsafe_ptr=in_ptr, length=in_len)
    var comp = Compressor(level=level)
    var chunk = comp.compress(in_span)
    var out_ptr = Pointer[CompressedChunk, MutUntrackedOrigin](unsafe_from_address=out_chunks_addr)
    out_ptr.unsafe_offset(chunk_idx).unsafe_write(chunk^)


struct Pipeline:
    comptime DEFAULT_CHUNK_SIZE: Int = 2 * 1024 * 1024 # 2 MB

    var level: Int
    var chunk_size: Int

    def __init__(out self, level: Int = 1, chunk_size: Int = 2 * 1024 * 1024):
        self.level = level
        if chunk_size == 2 * 1024 * 1024 and level >= 9:
            self.chunk_size = 8 * 1024 * 1024
        else:
            self.chunk_size = chunk_size

    def compress_stream[origin: Origin](self, data: Span[UInt8, origin]) raises -> List[CompressedChunk]:
        var total_len = len(data)
        var result = List[CompressedChunk]()

        if total_len == 0:
            var comp = Compressor(level=self.level)
            var c = comp.compress(data)
            result.append(c^)
            return result^

        var num_chunks = (total_len + self.chunk_size - 1) // self.chunk_size

        if num_chunks <= 1:
            var comp = Compressor(level=self.level)
            var c = comp.compress(data)
            result.append(c^)
            return result^

        # Multi-threaded chunk compression using TaskGroup
        var layout = Layout[CompressedChunk](count=num_chunks)
        var out_mem = alloc(layout)
        var out_ptr = out_mem.unsafe_ptr()
        var out_addr = Int(out_ptr)

        var in_ptr = Pointer[UInt8, MutUntrackedOrigin](unsafe_from_address=Int(data.unsafe_ptr()))

        var tg = TaskGroup()
        for i in range(num_chunks):
            var offset = i * self.chunk_size
            var cur_len = min(self.chunk_size, total_len - offset)
            var c_addr = Int(in_ptr.unsafe_offset(offset))
            tg.create_task(_compress_chunk_task(i, c_addr, cur_len, self.level, out_addr))

        tg.wait()

        for i in range(num_chunks):
            var chunk = out_ptr.unsafe_offset(i).unsafe_take_pointee()
            result.append(chunk^)

        dealloc(out_mem^)
        return result^
