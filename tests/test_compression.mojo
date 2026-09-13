from mojopack.compressor import Compressor, Decompressor, ChunkMode
from mojopack.checksum import XXH3_64
from std.collections import Span
from std.random import random_ui64

def assert_identical(original: Span[UInt8, _], restored: List[UInt8], test_name: String) raises:
    if len(original) != len(restored):
        raise Error("[FAIL] " + test_name + ": length mismatch. Original=" + String(len(original)) + ", Restored=" + String(len(restored)))
    for i in range(len(original)):
        if original[i] != restored[i]:
            raise Error("[FAIL] " + test_name + ": mismatch at byte " + String(i) + "! Expected " + hex(original[i]) + ", got " + hex(restored[i]))
    print("[PASS] " + test_name + ": verified 100% byte-for-byte exact equality (" + String(len(original)) + " bytes)")

def test_boundaries() raises:
    var comp_fast = Compressor(level=1)
    var decomp = Decompressor()

    # 1. Empty buffer
    var empty = List[UInt8]()
    var c_empty = comp_fast.compress(Span[UInt8](empty))
    var r_empty = decomp.decompress(c_empty.mode, Span[UInt8](c_empty.data), c_empty.uncompressed_size, c_empty.checksum)
    assert_identical(Span[UInt8](empty), r_empty, "Boundary: Empty Buffer")

    # 2. 1 Byte
    var one = List[UInt8]()
    one.append(42)
    var c_one = comp_fast.compress(Span[UInt8](one))
    var r_one = decomp.decompress(c_one.mode, Span[UInt8](c_one.data), c_one.uncompressed_size, c_one.checksum)
    assert_identical(Span[UInt8](one), r_one, "Boundary: 1 Byte")

    # 3. 15 Bytes (under threshold, should store RAW)
    var fifteen = List[UInt8]()
    for i in range(15):
        fifteen.append(UInt8(i * 3))
    var c_fifteen = comp_fast.compress(Span[UInt8](fifteen))
    var r_fifteen = decomp.decompress(c_fifteen.mode, Span[UInt8](c_fifteen.data), c_fifteen.uncompressed_size, c_fifteen.checksum)
    assert_identical(Span[UInt8](fifteen), r_fifteen, "Boundary: 15 Bytes")

def test_repetitive_text() raises:
    var comp_fast = Compressor(level=1)
    var comp_ultra = Compressor(level=9)
    var decomp = Decompressor()

    var text = String("Mojo is designed for high-performance systems and MLIR-native execution. ") * 100
    var b = text.as_bytes()

    # Mode -1 Fast
    var c_fast = comp_fast.compress(b)
    print("Repetitive Text Mode -1: " + String(c_fast.uncompressed_size) + " -> " + String(c_fast.compressed_size) + " bytes")
    var r_fast = decomp.decompress(c_fast.mode, Span[UInt8](c_fast.data), c_fast.uncompressed_size, c_fast.checksum)
    assert_identical(b, r_fast, "Repetitive Text Mode -1 (Fast)")

    # Mode -9 Ultra
    var c_ultra = comp_ultra.compress(b)
    print("Repetitive Text Mode -9: " + String(c_ultra.uncompressed_size) + " -> " + String(c_ultra.compressed_size) + " bytes")
    var r_ultra = decomp.decompress(c_ultra.mode, Span[UInt8](c_ultra.data), c_ultra.uncompressed_size, c_ultra.checksum)
    assert_identical(b, r_ultra, "Repetitive Text Mode -9 (Ultra)")

def test_random_incompressible() raises:
    var comp = Compressor(level=1)
    var decomp = Decompressor()

    var rand_buf = List[UInt8](capacity=20000)
    for _ in range(20000):
        rand_buf.append(UInt8(random_ui64(0, 255)))

    var chunk = comp.compress(Span[UInt8](rand_buf))
    if chunk.mode != ChunkMode.RAW:
        raise Error("[FAIL] Incompressible random data was not detected as RAW!")
    print("[PASS] Incompressible data detected and stored RAW (mode 0)")

    var restored = decomp.decompress(chunk.mode, Span[UInt8](chunk.data), chunk.uncompressed_size, chunk.checksum)
    assert_identical(Span[UInt8](rand_buf), restored, "Random Incompressible Bypass")

def test_binary_bcj_ultra() raises:
    from std.io.file import open
    var comp_ultra = Compressor(level=9)
    var decomp = Decompressor()

    var bin_bytes: List[UInt8]
    with open("./mpack", "r") as f:
        bin_bytes = f.read_bytes()

    var c = comp_ultra.compress(Span[UInt8](bin_bytes))
    if c.mode != ChunkMode.ULTRA_RC_BCJ:
        raise Error("[FAIL] ELF binary was not compressed with ULTRA_RC_BCJ mode! Mode=" + String(c.mode))
    print("ELF Binary Mode -9 (Ultra RC + BCJ): " + String(c.uncompressed_size) + " -> " + String(c.compressed_size) + " bytes (" + String((Float64(c.compressed_size)/Float64(c.uncompressed_size))*100.0) + "%)")

    var r = decomp.decompress(c.mode, Span[UInt8](c.data), c.uncompressed_size, c.checksum)
    assert_identical(Span[UInt8](bin_bytes), r, "ELF Binary BCJ + UltraRC")

def main() raises:
    print("=== Running Compression & Lossless Fidelity Tests ===")
    test_boundaries()
    test_repetitive_text()
    test_random_incompressible()
    test_binary_bcj_ultra()
    print("ALL COMPRESSION LOSSLESS TESTS PASSED!\n")
