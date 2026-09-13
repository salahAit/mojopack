# MojoPack (`mpack` & `unmpack`)

**MojoPack** is an ultra-fast, modern file archiver and lossless data compression suite written 100% in **native Mojo**. Engineered from first principles for high-performance computing, systems programming, and self-extracting deployment (SFX), MojoPack combines bare-metal CPU saturation, explicit value ownership, AVX2 SIMD vectorization, x86-64 machine-code pre-filtering, and a context-adaptive Binary Range Coder.

> **Author**: Salah AIT AMOKRANE  
> **Language**: Native Mojo 1.0.0 (Zero C/C++/Python Runtime Dependencies)  
> **Documentation**: Comprehensive 24-Page Technical Manual available in [`DOCS/mojopack_developer_guide.pdf`](DOCS/mojopack_developer_guide.pdf)

---

## Key Architectural Features

- **Vectorized SIMD Match Finder**: 32-byte parallel comparisons using native `unsafe_load[width=32]()`, `pack_bits()`, and hardware trailing-zero count (`count_trailing_zeros`) for single-cycle match boundary identification.
- **x86-64 BCJ Machine-Code Filter**: Automatic ELF and PE header detection with forward/inverse normalization of relative `CALL` (`0xE8`) and `JMP` (`0xE9`) instruction displacements ($dest = src \pm (i + 5)$), closing the executable compression gap to LZMA2 / `7-Zip`.
- **LZMA-Style Markov Range Coder**: 
  - 12-state Markov state transition engine.
  - 4-register LRU repeated offset cache (`rep0`, `rep1`, `rep2`, `rep3`).
  - Context-adaptive Binary Range Coder with 11-bit fixed-point probabilities.
  - 64-slot logarithmic position modeling and 3-tier length trees.
- **Strict Stack Allocation (`InlineArray`)**: Zero dynamic heap allocations in hot encoding/decoding loops, eliminating garbage collection pauses and allocator lock contention.
- **Zero-Copy POSIX Direct Streaming**: Input packaging and output extraction bypass high-level memory streams, writing directly between disk file descriptors and memory buffers via libc `openat(AT_FDCWD)`, `read()`, `write()`, and `chmod()`.
- **Full Multi-Threaded Concurrency**:
  - Multi-threaded parallel chunk compression via Mojo's `TaskGroup` runtime.
  - Multi-threaded parallel chunk decompression in both `mpack x` and `unmpack`.
  - Parallel chunk integrity testing in `mpack t`.
- **Ultra-Lean Standalone Unpacker (`unmpack`)**: A stripped 46.8 KB standalone decompressor header for Self-Extracting Bundles (SFX), completely decoupled from compressor search trees.
- **Data Integrity & Security**: Built-in 64-bit XXH3 checksums per block, path sanitization against directory traversal (`Zip Slip`), and full POSIX permission preservation.

---

## Codebase Structure

```
.
├── mojopack/                # Core compression engine package
│   ├── __init__.mojo        # Package exports
│   ├── checksum.mojo        # Vectorized XXH3-64 and IEEE 802.3 CRC32
│   ├── bitstream.mojo       # 64-bit BitWriter & BitReader
│   ├── match_finder.mojo    # SIMD AVX2 sliding-window match finder (HC4)
│   ├── entropy.mojo         # Shannon estimator, Huffman, and Binary Range Coder
│   ├── compressor.mojo      # Adaptive Fast LZ, Ultra Range Coder, Decompressor
│   ├── container.mojo       # Deterministic .mpk container, parallel solid decompression
│   ├── pipeline.mojo        # Multi-threaded chunk compression pipeline (TaskGroup)
│   ├── cli.mojo             # Zero-copy CLI parser and streaming handlers
│   └── filters/
│       └── bcj.mojo         # x86/x86-64 BCJ relative branch displacement filter
├── mpack.mojo               # Full archiver & compressor CLI entry point
├── unmpack.mojo             # Standalone ultra-lean decompressor (SFX header)
├── mpack                    # Native ELF 64-bit full archiver executable (190 KB)
├── unmpack                  # Native ELF 64-bit unpacker executable (46.8 KB)
├── DOCS/
│   └── mojopack_developer_guide.typ  # Comprehensive Typst technical documentation
├── tests/
│   ├── test_checksum.mojo   # CRC32 and XXH3-64 test suite
│   ├── test_compression.mojo# Byte-for-byte lossless roundtrip fidelity tests
│   └── test_archive.mojo    # Integration test (Create, List, Test, Extract, cmp)
├── LICENSE                  # MIT Open Source License
├── .gitattributes           # Linguist documentation overrides (100% Mojo)
├── .gitignore               # Build artifact exclusions (ignores *.pdf, cache, etc.)
└── README.md
```

---

## Binary Container Format (`.mpk`)

MojoPack uses a deterministic binary wire format:

```
[4 Bytes: Magic "MPK1"]
[4 Bytes: Header Flags (Reserved)]
[4 Bytes: Chunks Count (N)]
[8 Bytes: Total Archive Metadata Offset]
[Chunk 0: Compressed Payload Block]
├─ [1 Byte: Chunk Mode (0=RAW, 1=FAST, 2=ULTRA, 3=ULTRA_RC, 4=ULTRA_RC_BCJ)]
├─ [4 Bytes: Chunk Uncompressed Size]
├─ [4 Bytes: Chunk Compressed Size]
├─ [8 Bytes: XXH3-64 Checksum]
└─ [Payload Bytes...]
[Chunk 1 .. N-1...]
[Solid Archive Metadata Table]:
├─ [4 Bytes: Total File Count (M)]
├─ For each file [0 .. M-1]:
│   ├─ [2 Bytes: Relative Path Length (L)]
│   ├─ [L Bytes: Sanitized UTF-8 Relative Path]
│   ├─ [8 Bytes: Uncompressed Size]
│   ├─ [8 Bytes: Solid Stream Offset]
│   ├─ [4 Bytes: POSIX st_mode Permissions]
│   └─ [8 Bytes: POSIX Modification Timestamp]
[8 Bytes: Footer Magic "EOF_MPK\0"]
```

---

## Installation & Compilation

### Requirements
- Linux x86-64
- [Mojo 1.0.0+](https://modular.com/max/mojo)

### 1. Build the Full Archiver (`mpack`)
```bash
mojo build mpack.mojo -o mpack \
  -Xlinker -z -Xlinker noseparate-code \
  -Xlinker --gc-sections \
  -Xlinker -s

strip -R .comment -R .note.gnu.build-id -R .note.ABI-tag -R .note.gnu.property mpack
```
*Resulting binary size: **190 KB**.*

### 2. Build the Ultra-Lean Standalone Unpacker (`unmpack`)
```bash
mojo build unmpack.mojo -o unmpack \
  -Xlinker -z -Xlinker noseparate-code \
  -Xlinker --gc-sections \
  -Xlinker -s

strip -R .comment -R .note.gnu.build-id -R .note.ABI-tag -R .note.gnu.property unmpack
```
*Resulting binary size: **46.8 KB** (total code sections: 41.9 KB).*

---

## Command-Line Usage

### Full Archiver (`mpack`)

```bash
# 1. Create Archive (Fast Mode -1, default):
./mpack c archive.mpk /path/to/files_or_directories

# 2. Create Archive (Ultra High-Ratio Mode -9 with BCJ & Range Coder):
./mpack c -9 archive.mpk /path/to/files_or_directories

# 3. Extract Archive (Multi-Threaded Parallel Decompression):
./mpack x archive.mpk -o ./extracted_folder

# 4. List Archive Contents (Zero-Decompression Metadata Scan):
./mpack l archive.mpk

# 5. Test Archive Integrity (Parallel Checksum Verification):
./mpack t archive.mpk

# 6. Benchmark Throughput:
./mpack b /path/to/test_payload
```

### Standalone Unpacker (`unmpack`)

```bash
# Extract to current directory:
./unmpack archive.mpk

# Extract to a specified destination directory:
./unmpack archive.mpk -o /path/to/destination
```

---

## Performance & Compression Benchmarks

### Real-World Benchmark: 197.8 MB Executable Binary (`cwefdSystem`)
Hardware: AMD Ryzen 12-Thread CPU, PCIe NVMe SSD, Ubuntu Linux.

| Operation | Command | Execution Time | Throughput | Archive Size / Ratio |
| :--- | :--- | :--- | :--- | :--- |
| **Fast Compression** | `./mpack c` | **0.473 s** | **398.7 MB/s** | 114.9 MB (58.1%) |
| **Ultra Compression** | `./mpack c -9` | **1.378 s** | **137.0 MB/s** | **82.0 MB (41.5%)** |
| **Parallel Integrity Test** | `./mpack t` | **0.794 s** | 24 Chunks OK | --- |
| **Fast Unpack** | `./unmpack` | **0.085 s** | **2,211.0 MB/s** | 100% Bit-Exact |
| **Ultra Unpack (`unmpack`)** | `./unmpack` | **0.547 s** | **343.0 MB/s** | 100% Bit-Exact |
| **Ultra Extract (`mpack x`)**| `./mpack x` | **0.858 s** | **220.0 MB/s** | 100% Bit-Exact |

*Historical note: Initial unoptimized ultra compression took 80.18 s; modern MojoPack delivers a **58.2x speedup** (down to 1.37 s) while retaining maximum compression density.*

### Bit-Exact Lossless Verification
All extractions are verified byte-for-byte against the original input using the POSIX `cmp` utility:
```bash
cmp /tmp/extracted_file /path/to/original_file
# Output: 100% BIT-FOR-BIT IDENTICAL
```

---

## Constructing Self-Extracting Bundles (SFX)

Because `unmpack` is an ultra-lean (46.8 KB) standalone executable with zero dependencies, you can produce self-extracting archives by directly concatenating `unmpack` and any `.mpk` archive:

```bash
# 1. Compress payload with ultra ratio:
./mpack c -9 payload.mpk ./my_application

# 2. Concatenate unpacker header with payload:
cat unmpack payload.mpk > my_installer
chmod +x my_installer

# 3. Running my_installer will unpack the payload automatically:
./my_installer -o /opt/my_application
```

---

## Running the Automated Test Suite

```bash
# 1. Checksums (Vectorized CRC32 & XXH3-64)
mojo run -I . tests/test_checksum.mojo

# 2. Lossless Compression Fidelity & Boundary Conditions
mojo run -I . tests/test_compression.mojo

# 3. Archive Integration (Create, List, Parallel Test, Extract, cmp)
mojo run -I . tests/test_archive.mojo
```

---

## Technical Documentation

A comprehensive **24-page engineering manual** written in **Typst** is available in the [`DOCS/`](DOCS/) folder:
- PDF: [`DOCS/mojopack_developer_guide.pdf`](DOCS/mojopack_developer_guide.pdf)
- Typst Source: [`DOCS/mojopack_developer_guide.typ`](DOCS/mojopack_developer_guide.typ)

To recompile the documentation:
```bash
typst compile DOCS/mojopack_developer_guide.typ DOCS/mojopack_developer_guide.pdf
```

---

## License & Attribution

Authored and Architected by **Salah AIT AMOKRANE** (2026).  
Released under the MIT License.
