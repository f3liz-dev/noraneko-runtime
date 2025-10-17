# .github Directory Documentation

This directory contains GitHub Actions workflows, build scripts, branding assets, and patches for building the Noraneko browser runtime based on Firefox.

## Directory Structure

```
.github/
├── LICENSE                           # Mozilla Public License v2.0
├── README.md                         # This file
├── assets/                          # Build assets and branding files
│   ├── apt-fast/                    # Faster apt package manager wrapper
│   └── branding/                    # Noraneko browser branding resources
├── patches/                         # Patch files for modifying upstream Firefox
│   ├── dev/                        # Development-specific patches
│   ├── packaging/                  # Build system and packaging patches
│   └── upstream/                   # Per-file patches for upstream Firefox code
├── scripts/                        # Build and PGO profiling scripts
│   └── firefox-profileserver/      # PGO profile generation tool
└── workflows/                      # GitHub Actions workflow definitions
    ├── scripts/                    # Build helper scripts
    ├── mozconfigs/                 # Mozilla build configuration files
    └── *.yml                       # Workflow definition files
```

## Workflows Overview

### Main Build Workflows

1. **[daily-build.yml](workflows/DOCS-daily-build.md)** - Orchestrates daily scheduled builds for all platforms
2. **[common-build.yml](workflows/DOCS-common-build.md)** - Shared build logic for all platforms (reusable workflow)
3. **[wrapper-build-linux.yml](workflows/DOCS-wrapper-build-linux.md)** - Linux-specific build wrapper with PGO support
4. **[wrapper-build-windows.yml](workflows/DOCS-wrapper-build-windows.md)** - Windows-specific build wrapper with PGO support

### PGO (Profile-Guided Optimization) Workflows

5. **[generate-pgo-profile-linux.yml](workflows/DOCS-generate-pgo-profile-linux.md)** - Generates PGO profiles for Linux builds
6. **[generate-pgo-profile-windows.yml](workflows/DOCS-generate-pgo-profile-windows.md)** - Generates PGO profiles for Windows builds

### Maintenance Workflows

7. **[cleanup-large-caches.yml](workflows/DOCS-cleanup-large-caches.md)** - Manages GitHub Actions cache storage
8. **[misc-pull-upstream.yml](workflows/DOCS-misc-pull-upstream.md)** - Syncs upstream Firefox changes
9. **[autodiff-per-file-pr.yml](workflows/DOCS-autodiff-per-file-pr.md)** - Automates patch file generation from PRs

## Build Process Overview

### Standard Build Flow
```
daily-build.yml
    ├─→ wrapper-build-windows.yml
    │       └─→ common-build.yml (Windows)
    │
    └─→ wrapper-build-linux.yml (x86_64 & aarch64)
            └─→ common-build.yml (Linux)
```

### PGO-Enabled Build Flow (3-Stage Process)
```
wrapper-build-*.yml (with pgo: true)
    │
    ├─→ Stage 1: common-build.yml (pgo_mode: generate)
    │   • Builds browser with profiling instrumentation
    │   • Output: instrumented browser package
    │
    ├─→ Stage 2: generate-pgo-profile-*.yml
    │   • Runs instrumented browser with test workloads
    │   • Collects runtime profiling data (.profraw files)
    │   • Merges profiles into merged.profdata
    │   • Output: merged.profdata + en-US.log (JAR access log)
    │
    └─→ Stage 3: common-build.yml (pgo_mode: use)
        • Builds optimized browser using collected profiles
        • Output: final optimized browser package
```

## Key Build Artifacts

### Generated During Build
- **Browser packages**: `noraneko-{platform}-{arch}-moz-artifact.{zip|tar.xz}`
- **dist/host**: Tools for creating MAR (Mozilla Archive) update files
- **application.ini**: Browser application metadata

### PGO-Related Artifacts
- **merged.profdata**: Merged LLVM profile data from instrumented runs
- **en-US.log**: JAR file access log for optimizing startup performance
- ***.profraw**: Raw profile data files (intermediate, merged into profdata)

## Build Configuration

### Platform-Specific mozconfigs
- **linux-x86_64.mozconfig**: Linux 64-bit x86 build configuration
- **linux-aarch64.mozconfig**: Linux 64-bit ARM build configuration  
- **windows-x86_64.mozconfig**: Windows 64-bit build configuration

### Common Configuration Elements
- App name: `noraneko`
- Branding: `browser/branding/noraneko-unofficial`
- Target architectures: x86_64 (all platforms), aarch64 (Linux only)
- Compiler cache: sccache for fast incremental builds
- Telemetry: Disabled
- Chrome format: Flat (performance optimization)

## Scripts

### Build Scripts
- **[setup-noraneko.sh](scripts/DOCS-setup-noraneko.md)**: Configures mozconfig and branding for build
- **[build-and-package.sh](scripts/DOCS-build-and-package.md)**: Executes mach build and packages artifacts
- **[setup-rust.sh](scripts/DOCS-setup-rust.md)**: Installs Rust toolchain with correct version for PGO
- **[allocate-swap.sh](scripts/DOCS-allocate-swap.md)**: Manages swap space and frees disk space
- **[bootstrap_mozilla.sh](scripts/DOCS-bootstrap_mozilla.md)**: Sets up Mozilla build environment

### PGO Profile Generation
- **[profileserver.py](scripts/DOCS-firefox-profileserver.md)**: Python script that runs Firefox with test workloads to generate PGO profiles

## Patches Directory

The `patches/` directory contains modifications to upstream Firefox code:

### patch/upstream/
Per-file patches generated from PR changes. Each patch modifies a specific upstream file:
- Naming: `{path-to-file-with-slashes-replaced-by-dashes}.patch`
- Applied during build before compilation
- Generated automatically by autodiff-per-file-pr.yml workflow

### patches/dev/
Development-specific patches for debugging and development features.

### patches/packaging/
Patches to build system and packaging configuration.

## Assets

### Branding (assets/branding/noraneko-unofficial/)
Complete branding package for Noraneko:
- Application icons (various sizes and formats: .ico, .icns, .png)
- Visual assets for Windows installer and tiles
- About page logos and wordmarks
- Localized brand strings

### apt-fast (assets/apt-fast/)
Faster apt package manager wrapper using parallel downloads (not currently used in workflows).

## Dependencies & Prerequisites

### System Requirements
- **Linux runners**: Ubuntu-latest with 30GB swap space
- **Windows runners**: Windows-latest with Mozilla Build environment
- **Build time**: 2-4 hours per platform (standard), 6-8 hours (PGO-enabled)

### Required Tools (Auto-installed)
- **Rust 1.86.0**: For LLVM 19 compatibility in PGO builds
- **LLVM 19**: For PGO profile data processing (llvm-profdata)
- **sccache**: Compiler cache for incremental builds
- **Node.js**: For workflow scripts
- **Python 3.11+**: For Mozilla build scripts and PGO profiling

### Execution Order Requirements
1. Swap allocation → build starts
2. Rust setup → Mozilla bootstrap
3. Patches apply → `mach configure`
4. PGO Stage 1 → PGO Stage 2 → PGO Stage 3

## Data Flow Between Jobs

### Artifacts Uploaded & Downloaded
```
common-build.yml (Stage 1) 
    → uploads: noraneko-{platform}-{arch}-moz-artifact
    
generate-pgo-profile-*.yml (Stage 2)
    → downloads: noraneko-{platform}-{arch}-moz-artifact
    → uploads: {platform}-{arch}-profile-generate-output (merged.profdata + en-US.log)
    
common-build.yml (Stage 3)
    → downloads: {platform}-{arch}-profile-generate-output
    → uploads: final optimized noraneko-{platform}-{arch}-moz-artifact
```

### State Transformations
1. **Source → Patched Source**: Patches from `.github/patches/upstream/` applied
2. **Patched Source → Object Files**: Compilation with sccache
3. **Object Files → Instrumented Binary**: Stage 1 PGO build adds profiling hooks
4. **Instrumented Binary + Workloads → Profile Data**: Stage 2 collects runtime data
5. **Profile Data + Source → Optimized Binary**: Stage 3 uses profiles for optimization
6. **Optimized Binary → Package**: Final browser archive (zip/tar.xz)

## Architecture Variations

### Platform Differences

**Linux**:
- Builds in Xvfb virtual display (headless X server)
- Supports both x86_64 and aarch64 architectures
- Uses Docker containers for aarch64 cross-compilation
- Output format: `.tar.xz`

**Windows**:
- Builds on native Windows runners
- Only x86_64 architecture supported
- Requires Mozilla Build environment (MSYS2-based)
- Output format: `.zip`

**Cross-compilation (Linux aarch64)**:
- Runs on macOS runners with Docker for ARM64 emulation
- Uses Debian Bookworm container with platform: linux/arm64
- Requires QEMU for ARM64 instruction emulation

## Timing & Synchronization

### Critical Timing
- **Xvfb startup**: 3-second delay ensures display is ready before Firefox starts
- **PGO timeout multiplier**: 5x normal timeout (MOZ_PGO_TIMEOUT_MULTIPLIER=5)
- **Profile generation**: 1200-second (20 minute) timeout for browser workloads
- **Swap allocation**: Must complete before large compilations begin

### Parallelization
- **Daily builds**: Windows, Linux x86_64, and Linux aarch64 run in parallel
- **Within build**: Mach uses `(nproc * 3/4)` parallel jobs
- **PGO stages**: Must run sequentially (Stage 1 → 2 → 3)

## Cache Strategy

### What Gets Cached
- **sccache**: Compiled object files (automatic via sccache-action)
- **Python packages**: uv cache for PGO profile generation dependencies
- **Rust artifacts**: Cargo incremental compilation disabled (CARGO_INCREMENTAL=0)

### Cache Cleanup
- **Automatic**: cleanup-large-caches.yml runs daily at 2 AM UTC
- **Threshold**: Removes caches larger than 1MB (configurable)
- **Effect**: Maintains usage below GitHub's 10GB cache limit

## Upstream Sync Strategy

### Automatic Sync (misc-pull-upstream.yml)
- **Schedule**: Daily at 11:40 AM UTC (8:40 PM JST)
- **Source**: mozilla-firefox/firefox release branch
- **Process**:
  1. Clone upstream Firefox release branch (depth 1)
  2. Sync files via rsync (excluding .github/, noraneko/, branding)
  3. Validate existing patches still apply
  4. Create or update PR with changes
  5. Track version changes (MAJOR/MINOR/PATCH)

### Patch Compatibility
- Patches validated with `git apply --check --ignore-space-change`
- Failed patches listed in PR description
- PR updated incrementally as upstream changes accumulate

## Bot Automation (F3liz Bot)

### autodiff-per-file-pr.yml
**Trigger**: Comment `@f3liz-bot patch` on a PR

**Process**:
1. Generates per-file patches for all modified upstream files
2. Stores patches in `.github/patches/upstream/`
3. Reverts source file changes (keeps only patches)
4. Validates patches apply cleanly before committing

**Patch removal**: `@f3liz-bot patch rm=file1,file2` removes specified patches

**Effect**: Maintains separation between Noraneko-specific changes and upstream modifications

## License

All GitHub Actions workflows and scripts in this repository are licensed under the Mozilla Public License v2.0. See [LICENSE](LICENSE) for full text.

## Additional Documentation

For detailed documentation on specific workflows and scripts, see the individual documentation files linked in the sections above.
