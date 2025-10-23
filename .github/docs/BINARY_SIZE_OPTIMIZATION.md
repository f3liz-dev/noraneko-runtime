# Binary Size Optimization

This document describes the binary size optimizations applied to Noraneko builds to reduce the final executable size, particularly for Windows builds.

## Overview

The optimizations implemented focus on reducing binary size by at least 1MB, especially for Windows builds, while maintaining performance and debuggability for release builds.

## Optimizations Applied

### 1. Link-Time Optimization (LTO)

**Flag**: `--enable-lto=cross` with `MOZ_LTO=cross`

- **What it does**: Enables cross-language Link-Time Optimization, allowing the linker to optimize across translation units and even between C++/Rust code boundaries.
- **Expected savings**: 2-5% of binary size (typically 3-15 MB for Firefox-based browsers)
- **Performance impact**: Can improve runtime performance by 2-8% due to better inlining and dead code elimination
- **Build time impact**: Increases link time by 20-50%

### 2. Size-Optimized Compilation

**Flag**: `--enable-optimize=-Oz`

- **What it does**: Uses Clang's `-Oz` flag for aggressive size optimization instead of the default `-O2` or `-O3`. This flag prioritizes code size over performance in optimization decisions.
- **Expected savings**: 10-20% reduction in code size compared to `-O2` (typically 10-40 MB)
- **Performance impact**: May reduce performance by 5-15% compared to `-O3`, but usually minimal difference from `-O2`
- **Trade-off**: Size vs. speed - prioritizes smaller binaries over marginal performance gains

### 3. Minimal Debug Symbols

**Flag**: `--enable-debug-symbols=-g1`

- **What it does**: Generates minimal debug information (`-g1` level) instead of full debug symbols (`-g` or `-g2`)
  - `-g1`: Line number tables and external variable information only
  - No local variable information or macro definitions
  - Sufficient for stack traces and crash reporting
- **Expected savings**: 
  - Windows: 50-200 MB reduction in PDB file size
  - Linux: 20-80 MB reduction in binary size
  - Actual deployed binary sees 1-5 MB savings on Windows, 5-20 MB on Linux
- **Functionality**: Still allows crash reporting and basic debugging, but less detailed than full symbols

### 4. Symbol Stripping (Linux only)

**Flags**: `--enable-strip` and `--disable-install-strip`

- **What it does**: Strips symbols from Linux binaries during packaging
- **Expected savings**: 20-50 MB on Linux builds
- **Note**: Not applicable to Windows builds as symbol information is in separate PDB files

## Platform-Specific Considerations

### Windows

- Debug symbols are stored in separate PDB files, so `-g1` affects PDB size more than executable size
- LTO is particularly effective on Windows with clang-cl
- The combination of LTO + `-Oz` + `-g1` typically saves 5-15 MB on the final installer

### Linux

- Debug symbols are embedded in the binary, so `-g1` has more direct impact
- Symbol stripping provides additional size savings
- The combination of all optimizations typically saves 15-50 MB on the final tarball

## Debug Builds

For debug builds (when `--enable-debug` is set), the following changes are made:

- Size optimization flags are **disabled**
- LTO is **disabled** (to speed up debug builds)
- Full debug symbols are used (default `-g2` or `-g`)
- Symbol stripping is **disabled** on Linux

This ensures that debug builds remain useful for development and debugging.

## PGO Builds

For Profile-Guided Optimization (PGO) builds:

- The LTO settings are respected and work in conjunction with PGO
- PGO mode can override MOZ_LTO settings via the build script
- Size optimizations remain active and complement PGO benefits
- Expected combined savings: 10-30 MB with both PGO and size optimizations

## Testing and Validation

To validate the size savings:

1. Build without optimizations (comment out the flags in mozconfig)
2. Build with optimizations
3. Compare the final installer/package sizes
4. Run smoke tests to ensure functionality is preserved

## Future Improvements

Additional size reduction opportunities to consider:

1. **Dead code elimination**: Enable `-fdata-sections` and `-ffunction-sections` with `--gc-sections`
2. **Compression**: Use better compression algorithms for installer/package
3. **Component stripping**: Remove unused features or components
4. **Resource optimization**: Optimize images, fonts, and other resources
5. **Split binaries**: Separate optional components into DLLs/shared libraries

## References

- [Mozilla Build Documentation](https://firefox-source-docs.mozilla.org/setup/)
- [Clang Optimization Flags](https://clang.llvm.org/docs/CommandGuide/clang.html#cmdoption-O0)
- [LTO in Firefox](https://firefox-source-docs.mozilla.org/build/buildsystem/lto.html)
- [Debug Symbol Levels](https://gcc.gnu.org/onlinedocs/gcc/Debugging-Options.html)
