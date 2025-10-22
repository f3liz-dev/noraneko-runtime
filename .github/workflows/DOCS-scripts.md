# Build Scripts

Scripts in `.github/workflows/scripts/`.

## Overview

| Script | Function |
|--------|----------|
| setup-noraneko.sh | Configure mozconfig, branding, mach bootstrap |
| build-and-package.sh | Compile and package browser |
| setup-rust.sh | Install Rust 1.86.0 |
| allocate-swap.sh | Allocate 30GB swap, free disk |

## setup-noraneko.sh

**Parameters**: platform, arch, debug, pgo, pgo_mode, pgo_artifact_name, MOZ_BUILD_DATE

**Steps**:
1. Copy mozconfig for platform/arch
2. Install branding → `browser/branding/`
3. Configure sccache, debug, PGO
4. Update URL → GitHub releases
5. Run `./mach bootstrap`

**PGO config**:
- Generate: `--enable-profile-generate=cross`
- Use: `--enable-profile-use=cross --with-pgo-profile-path=~/artifacts/merged.profdata`

## build-and-package.sh

**Parameters**: platform, arch, MOZ_BUILD_DATE, omnijar_compress

**Steps**:
1. Calculate jobs: `MOZ_NUM_JOBS=$(nproc * 3/4)`
2. Set `JAR_COMPRESSION` env var for omnijar compression (deflate|zstd|lz4|none)
3. Linux: Run in Xvfb, `LIBGL_ALWAYS_SOFTWARE=1`
4. `./mach configure` → `./mach build` → `./mach package`
5. Clean `~/.cargo` (saves 1-2GB)
6. Package → `~/output/noraneko-{platform}-{arch}-moz-artifact.{zip|tar.xz}`

**Timing**: 2-3 hours (cold), 30-60 min (warm cache)

## setup-rust.sh

**Parameters**: platform, arch, pgo_artifact_name

**Function**:
- Install Rust 1.86.0 for PGO builds (LLVM 19 compat)
- Add platform target (x86_64-pc-windows-msvc, x86_64-unknown-linux-gnu, aarch64-unknown-linux-gnu)
- Set `CARGO_INCREMENTAL=0`

## allocate-swap.sh

**Steps**:
1. Recreate swap: 30GB at `/mnt/swapfile`
2. Clean packages: `apt autoremove`, `apt clean`
3. Remove unused dirs (rsync method): dotnet, android, chromium, etc. (~25-30GB freed)

**Timing**: ~5 minutes
**Result**: +30GB swap, +30GB free disk

## Execution Order

```
1. Checkout → 2. Apply patches → 3. Setup sccache
→ 4. Setup Rust → 5. Allocate swap → 6. Setup noraneko → 7. Build
```

## Common Issues

| Issue | Fix |
|-------|-----|
| "rustc not found" | Check setup-rust.sh output |
| "No space left" | Run allocate-swap.sh |
| "mozconfig not found" | Check setup-noraneko.sh output |
| "Package not found" | Check obj-*/dist/ directory |
| PGO profile mismatch | Ensure Rust 1.86.0 for LLVM 19 |

## Testing Locally

```bash
# Setup
git clone https://github.com/f3liz-dev/noraneko-runtime
cd noraneko-runtime
for patch in .github/patches/upstream/*.patch; do git apply "$patch"; done

# Run scripts
./.github/workflows/scripts/setup-rust.sh linux x86_64
./.github/workflows/scripts/allocate-swap.sh
./.github/workflows/scripts/setup-noraneko.sh linux x86_64 true false "" "" ""
./.github/workflows/scripts/build-and-package.sh linux x86_64 "" deflate

# Check results
ls -lh ~/output/
cat nora-application.ini
```
