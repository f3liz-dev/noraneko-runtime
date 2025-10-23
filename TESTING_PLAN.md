# Testing Plan for Binary Size Optimizations

This document outlines the testing strategy to verify the binary size optimizations implemented in Noraneko Runtime.

## Automated Testing via CI

The changes can be tested through the existing GitHub Actions workflows:

### 1. Normal Build Test (Without PGO)

To test the optimizations on a normal build:

1. Go to Actions → "Windows Build" (or Linux Build)
2. Click "Run workflow"
3. Set parameters:
   - `debug`: false (unchecked)
   - `pgo`: false (unchecked)
   - `omnijar_compress`: deflate (or zstd for additional compression)
4. Run the workflow

**Expected results:**
- Build completes successfully
- Binary size is reduced compared to previous builds (without these optimizations)
- No debug symbols in the output
- JS shell is not included in the package

### 2. PGO Build Test

To test compatibility with PGO:

1. Go to Actions → "Windows Build" (or Linux Build)
2. Click "Run workflow"
3. Set parameters:
   - `debug`: false (unchecked)
   - `pgo`: true (checked)
   - `omnijar_compress`: deflate
4. Run the workflow

**Expected results:**
- All three PGO stages complete successfully:
  - Stage 1: Profile generation (LTO should be automatically disabled)
  - Stage 2: Profile collection
  - Stage 3: Final build with profile use (LTO should be enabled)
- Final binary size is optimized
- No build errors related to LTO/PGO conflicts

## Manual Verification

### Before and After Size Comparison

To measure the actual size reduction:

1. **Baseline build**: Use a build from before these changes were applied
2. **Optimized build**: Use a build with these changes
3. Compare:
   - Total installer/archive size
   - Extracted application directory size
   - Individual binary sizes (noraneko.exe, xul.dll, etc.)

### Size Measurement Commands

**Windows:**
```powershell
# Measure installer size
Get-Item noraneko-*.zip | Select-Object Name, Length

# Measure extracted size
Get-ChildItem -Recurse noraneko\ | Measure-Object -Property Length -Sum
```

**Linux:**
```bash
# Measure archive size
ls -lh noraneko-*.tar.xz

# Measure extracted size
du -sh noraneko/
```

### Expected Size Reductions

Based on the optimizations applied:

| Optimization | Expected Reduction | Notes |
|--------------|-------------------|-------|
| LTO | 10-30% | Varies by code structure |
| Debug symbols removal | 20-40% of debug size | Only if debug symbols were present |
| -Os optimization | 5-15% | Compared to -O2 |
| JS shell removal | 10-20 MB | Fixed size |

**Total expected reduction**: 30-100 MB for a typical ~200-300 MB browser

### Functionality Testing

After building with optimizations, verify core functionality:

1. **Startup Test**
   - Browser launches successfully
   - No crash on startup
   - Main window displays correctly

2. **Basic Browsing**
   - Can navigate to websites
   - Pages render correctly
   - JavaScript works
   - Media playback works

3. **Extensions**
   - Can install extensions
   - Extensions function correctly

4. **Performance**
   - Measure page load times (compare with baseline)
   - Run Speedometer or similar benchmarks
   - Verify acceptable performance (within 5% of baseline)

5. **Update Mechanism**
   - Check for updates works
   - Update download and installation works

## Validation Checklist

- [ ] Normal Windows build completes without errors
- [ ] Normal Linux x86_64 build completes without errors
- [ ] Normal Linux aarch64 build completes without errors
- [ ] PGO Windows build completes all stages
- [ ] Binary size is reduced by at least 1MB (Windows)
- [ ] Binary size is reduced on Linux builds
- [ ] Debug symbols are not present in release builds
- [ ] JS shell is not included in packages
- [ ] Browser launches and runs correctly
- [ ] No significant performance regression (<5%)
- [ ] All core features work correctly
- [ ] Update mechanism functions properly

## Rollback Plan

If any critical issues are discovered:

1. The changes are isolated to specific configuration files:
   - `.github/workflows/mozconfigs/*.mozconfig`
   - `.github/assets/config/moz.configure`

2. To rollback:
   - Revert the commits
   - Or manually restore the previous settings:
     - Remove `--enable-lto=cross`
     - Remove `--disable-debug-symbols`
     - Remove `export MOZ_OPTIMIZE_FLAGS="-Os"`
     - Restore `export MOZ_PACKAGE_JSSHELL=1`

3. Individual optimizations can be disabled independently for debugging:
   - Comment out `--enable-lto=cross` if LTO causes issues
   - Comment out `--disable-debug-symbols` if debugging is needed
   - Restore `-O2` if performance issues occur
   - Restore JS shell if needed for testing

## Performance Regression Testing

If performance issues are suspected:

1. **Benchmark Tests**
   - Speedometer 3.0
   - JetStream
   - MotionMark
   - WebXPRT

2. **Comparison**
   - Run benchmarks on baseline build (without optimizations)
   - Run benchmarks on optimized build (with -Os and LTO)
   - Calculate percentage difference
   - Acceptable threshold: <5% slower

3. **Real-world Tests**
   - Page load times on popular websites
   - Scrolling performance
   - Video playback smoothness
   - JavaScript-heavy applications

## Reporting Issues

If issues are found during testing:

1. **Build Failures**
   - Capture full build log
   - Note which stage failed (configure, compile, link, package)
   - Check if issue is LTO-related, optimization-related, or other

2. **Runtime Issues**
   - Capture browser console errors
   - Note steps to reproduce
   - Check if issue reproduces with individual optimizations disabled

3. **Performance Regressions**
   - Provide benchmark numbers (before/after)
   - Note which benchmark or real-world scenario shows regression
   - Test with individual optimizations to identify culprit

## Continuous Monitoring

After deployment:

1. Monitor binary sizes in CI builds
2. Track any user reports of performance issues
3. Compare telemetry data (if available) with previous versions
4. Monitor crash reports for any optimization-related issues

## Success Criteria

The optimization is considered successful if:

1. ✅ Binary size reduced by at least 1MB on Windows
2. ✅ Binary size reduced on all platforms
3. ✅ All builds complete successfully
4. ✅ No functional regressions
5. ✅ Performance impact is minimal (<5% slower on benchmarks)
6. ✅ PGO builds work correctly
7. ✅ No increase in crash rate
