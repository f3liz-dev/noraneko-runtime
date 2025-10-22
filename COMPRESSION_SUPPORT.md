# Compression Algorithm Support for omni.ja

This document describes the implementation of LZ4 and ZSTD compression algorithm support for JAR/ZIP archives in the Noraneko Runtime.

## Summary

This implementation adds support for modern compression algorithms (LZ4 and ZSTD) to the Mozilla JAR archive format, enabling better performance and compression ratios for omni.ja files.

### Supported Compression Methods

| Method | ID | Description | Status |
|--------|-----|-------------|--------|
| STORED | 0 | No compression | ✓ Existing |
| DEFLATE | 8 | Standard ZIP compression | ✓ Existing |
| LZ4 | 99 | Fast compression/decompression | ✓ **New** |
| ZSTD | 93 | High compression ratios | ✓ **New** |

## Implementation Details

### Files Modified

1. **modules/libjar/zipstruct.h**
   - Added LZ4 (99) and ZSTD (93) compression method constants

2. **python/mozbuild/mozpack/mozjar.py**
   - Added JAR_LZ4 and JAR_ZSTD constants
   - Updated `Deflater` class for LZ4/ZSTD compression
   - Updated `JarFileReader` class for LZ4/ZSTD decompression
   - Added optional imports for `lz4.frame` and `zstandard` libraries

3. **modules/libjar/nsZipArchive.h**
   - Added `zstd.h` include
   - Added `ZSTD_DStream*` member to `nsZipCursor` class

4. **modules/libjar/nsZipArchive.cpp**
   - Added `lz4.h` and `zstd.h` includes
   - Updated `nsZipCursor` constructor/destructor for ZSTD
   - Implemented LZ4 and ZSTD decompression in `ReadOrCopy()`
   - Updated `nsZipItemPtr_base` to recognize new compression methods

5. **modules/libjar/moz.build**
   - Added local includes for LZ4 and ZSTD header paths

6. **python/mozbuild/mozpack/test/test_mozjar.py**
   - Added unit tests for new compression methods

## Usage Examples

### Command Line (mach package)

The build system now supports command-line flags to choose the compression method for omni.ja:

```bash
# Package with ZSTD compression (best compression ratio)
./mach package --compress=zstd

# Package with LZ4 compression (fastest decompression)
./mach package --compress=lz4

# Package with standard DEFLATE compression
./mach package --compress=deflate

# Package with no compression
./mach package --compress=none

# Multi-locale packaging also supports compression
./mach package-multi-locale --locales ja de fr --compress=zstd
```

### Python (Build/Packaging)

```python
from mozpack.mozjar import JarWriter, JAR_ZSTD, JAR_LZ4

# Create a JAR with ZSTD compression
with JarWriter(file='omni.ja', compress=JAR_ZSTD, compress_level=9) as jar:
    jar.add('modules/file.js', open('file.js', 'rb'))

# Create a JAR with LZ4 compression
with JarWriter(file='omni.ja', compress=JAR_LZ4) as jar:
    jar.add('modules/file.js', open('file.js', 'rb'))
```

### C++ (Browser Runtime)

The browser automatically detects and decompresses LZ4/ZSTD compressed files:

```cpp
RefPtr<nsZipArchive> archive = nsZipArchive::OpenArchive(file);
nsZipItem* item = archive->GetItem("modules/file.js");
// Decompression happens transparently regardless of compression method
```

## Dependencies

### Build Tools (Python)
Optional packages for creating compressed archives:
```bash
pip install lz4
pip install zstandard
```

If not installed, the build system gracefully falls back to DEFLATE compression.

### Browser Runtime (C++)
Required libraries (already included in the tree):
- **LZ4**: `mozglue/static/lz4/`
- **ZSTD**: `third_party/zstd/`

## Testing

Run the Python tests:
```bash
./mach python-test python/mozbuild/mozpack/test/test_mozjar.py
```

Or run the standalone test:
```bash
python3 /tmp/test_compression.py
```

## Performance Characteristics

### Compression Ratios (approximate)
- **STORED**: 1.0x (no compression)
- **LZ4**: 1.5-2.5x (fast decompression)
- **DEFLATE**: 2-5x (balanced)
- **ZSTD**: 2-6x (excellent compression)

### Speed
- **LZ4**: Fastest decompression (3-5x faster than DEFLATE)
- **ZSTD**: Good decompression speed, best compression ratio
- **DEFLATE**: Slower than both LZ4 and ZSTD

### Recommendations
- **LZ4**: Best for frequently accessed files where startup speed is critical
- **ZSTD**: Best for distribution where file size matters
- **DEFLATE**: Good default for backward compatibility

## Backward Compatibility

✓ Full backward compatibility maintained:
- Existing STORED and DEFLATE compressed JARs continue to work
- Browsers without this patch can't read LZ4/ZSTD compressed files
- Build tools default to DEFLATE when LZ4/ZSTD libraries unavailable

## Security Considerations

- All decompression operations include bounds checking
- CRC32 verification is performed on decompressed data
- Buffer sizes are validated before decompression
- Invalid or corrupted compressed data returns errors safely

## Technical Notes

### Compression Method IDs
- **ZSTD (93)**: Uses official PKWARE-assigned method ID
- **LZ4 (99)**: Uses custom method ID (not in ZIP specification)

### ZSTD Compression in C++
The current implementation only includes ZSTD decompression in the browser runtime. Compression is handled by Python build tools using the `zstandard` package. This is intentional to:
- Reduce browser binary size
- Keep compression complexity in build-time tools
- Simplify runtime code

### LZ4 Frame Format
The Python implementation uses LZ4 frame format (`lz4.frame`) for better compatibility and error detection.

## Future Enhancements

Potential improvements for future work:

1. **Performance Benchmarking**
   - Measure real-world startup time impact
   - Compare file sizes with actual omni.ja contents
   - Profile CPU usage during decompression

2. **Build System Integration**
   - ✓ Add command-line flags to choose compression method (implemented via `--compress` flag)
   - Auto-select best compression based on file type
   - Create hybrid archives (different compression per file)

3. **Optimization**
   - Consider making ZSTD the default for distribution builds
   - Use LZ4 for development builds (faster iteration)
   - Implement parallel decompression for large files

4. **Tooling**
   - Add compression method detection to existing JAR inspection tools
   - Create conversion utility for re-compressing existing JARs
   - Add compression statistics to build logs

## References

- [PKWARE ZIP File Format Specification](https://pkware.cachefly.net/webdocs/casestudies/APPNOTE.TXT)
- [LZ4 Official Site](https://lz4.github.io/lz4/)
- [Zstandard Official Site](https://facebook.github.io/zstd/)
- [Mozilla JAR Format Documentation](https://developer.mozilla.org/en-US/docs/Mozilla/Projects/JAR)

## Authors

Implementation by GitHub Copilot for the Noraneko Runtime project.

## License

This implementation is covered by the Mozilla Public License 2.0 (MPL-2.0), consistent with the rest of the Noraneko Runtime codebase.
