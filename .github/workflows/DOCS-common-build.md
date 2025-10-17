# Common Build Workflow

**File**: `common-build.yml`

## Function

Core reusable build workflow - compiles and packages browser for any platform.

## Parameters

- `platform`: linux|windows|mac
- `arch`: x86_64|aarch64
- `debug`: boolean (default: true)
- `pgo`: boolean (default: false)
- `pgo_mode`: "" | "generate" | "use"
- `pgo_artifact_name`: Profile artifact name (for use mode)
- `MOZ_BUILD_DATE`: Optional for reproducible builds

## Build Steps

1. Checkout → Apply patches
2. Setup: sccache, Rust, swap allocation
3. Download PGO profiles (if pgo_mode=use)
4. Configure: setup-noraneko.sh
5. Build: build-and-package.sh
6. Upload artifacts

## PGO Modes

**generate**: Build with `--enable-profile-generate=cross` → instrumented browser
**use**: Build with `--enable-profile-use=cross` + profile paths → optimized browser

## Platform Differences

**Linux**:
- Runs in Xvfb (virtual X display)
- Supports x64 + arm64
- Output: `.tar.xz`

**Windows**:
- Native build
- x64 only
- Output: `.zip`

## Artifacts

- Browser package: `noraneko-{platform}-{arch}-moz-artifact`
- dist/host: MAR update tools
- application.ini: Metadata

## Timing

- Swap allocation: Before build
- Rust setup: Before bootstrap
- PGO stages: Sequential (1 → 2 → 3)
- Build: (nproc * 3/4) parallel jobs

## Common Failures

| Error | Cause | Fix |
|-------|-------|-----|
| Out of disk | 50GB+ objects | allocate-swap.sh |
| Patch fails | Upstream changes | Update patch |
| PGO missing | Stage 2 failed | Re-run pipeline |
| Timeout | Cold cache | sccache (auto) |
