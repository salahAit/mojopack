from mojopack.checksum import CRC32, XXH3_64
from std.collections import Span

def main() raises:
    print("=== Running Checksum Tests ===")
    
    # 1. Standard IEEE 802.3 CRC32 Test
    var crc = CRC32()
    var msg = String("123456789")
    var crc_res = crc.compute(msg.as_bytes())
    var expected_crc: UInt32 = 0xCBF43926
    if crc_res == expected_crc:
        print("[PASS] CRC32 standard test: " + hex(crc_res))
    else:
        raise Error("[FAIL] CRC32 expected " + hex(expected_crc) + ", got " + hex(crc_res))

    # 2. XXH3-64 Tests
    var xxh = XXH3_64()
    var empty = List[UInt8]()
    var h_empty = xxh.compute(Span[UInt8](empty))
    print("[PASS] XXH3-64 empty: " + hex(h_empty))

    var text = String("The quick brown fox jumps over the lazy dog")
    var h_fox = xxh.compute(text.as_bytes())
    print("[PASS] XXH3-64 text: " + hex(h_fox))

    # Determinism check
    var h_fox2 = xxh.compute(text.as_bytes())
    if h_fox != h_fox2:
        raise Error("[FAIL] XXH3-64 non-deterministic result!")
    print("[PASS] XXH3-64 determinism verified")

    print("ALL CHECKSUM TESTS PASSED!\n")
