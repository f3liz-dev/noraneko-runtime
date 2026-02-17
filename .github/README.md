# nya!

GitHub Actions workflows, build scripts, branding, and patches for Noraneko browser (Firefox-based).

## Directory Structure

- **workflows/** - GitHub Actions workflow definitions and helper scripts
- **scripts/** - Build and PGO profiling scripts
- **assets/** - Branding files and build assets
- **patches/** - Patches for upstream Firefox code (dev, packaging, upstream)

## Workflows

| Workflow | Function |
|----------|----------|
| daily-build.yml | Orchestrates daily builds (all platforms) |
| common-build.yml | Core build logic (reusable) |
| wrapper-build-{linux,windows}.yml | Platform-specific build wrappers |
| generate-pgo-profile-{linux,windows}.yml | PGO profile generation |
| cleanup-large-caches.yml | Cache management |
| misc-pull-upstream.yml | Sync upstream Firefox |
| autodiff-per-file-pr.yml | Auto-generate patches from PRs |

## Build Process

**Standard**: daily-build → wrapper-build → common-build (parallel: Windows, Linux x64, Linux ARM64)

**PGO (3-stage)**:
1. Build with profiling → instrumented browser
2. Run tests → collect profiles (merged.profdata + en-US.log)
3. Rebuild with profiles → optimized browser (15-30% faster)

## Artifacts

- Browser packages: `noraneko-{platform}-{arch}-moz-artifact.{zip|tar.xz}`
- PGO profiles: `merged.profdata`, `en-US.log` (7-day retention)
- Update tools: `dist/host`, `application.ini`

## Build Scripts

| Script | Function |
|--------|----------|
| setup-noraneko.sh | Configure mozconfig and branding |
| build-and-package.sh | Execute build and package |
| setup-rust.sh | Install Rust 1.86.0 (PGO compatibility) |
| allocate-swap.sh | Allocate 30GB swap, free disk space |
| profileserver.py | Generate PGO profiles |

## Patches

- Applied during build before compilation

## Requirements

- **Runners**: Ubuntu-latest (30GB swap), Windows-latest (Mozilla Build)
- **Build time**: 2-4 hours (standard), 6-8 hours (PGO)
- **Tools**: Rust 1.86.0, LLVM 20, sccache, Python 3.11+, Node.js

## Execution Order

1. Swap allocation → 2. Rust setup → 3. Apply patches → 4. Build
- PGO: Stage 1 (generate) → Stage 2 (profile) → Stage 3 (optimize)

## Platform Variations

| Platform | Runner | Arch | Container | Output |
|----------|--------|------|-----------|--------|
| Linux | ubuntu-latest | x64, arm64 | Debian (arm64 only) | .tar.xz |
| Windows | windows-latest | x64 | None | .zip |

- Linux arm64: Docker on macOS with QEMU
- PGO stages run sequentially (Stage 1 → 2 → 3)

## Cache & Maintenance

- **sccache**: Caches compiled objects
- **Cleanup**: Daily at 2 AM UTC, removes caches >1MB
- **Upstream sync**: Daily at 11:40 AM UTC, creates/updates PR
- **Bot**: `@f3liz-bot patch` generates per-file patches from PRs

## License

Mozilla Public License v2.0. See [LICENSE](LICENSE).
