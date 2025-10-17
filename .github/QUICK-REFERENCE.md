# Quick Reference Guide - .github Directory

This is a quick reference for understanding the .github directory structure and workflow execution. For detailed explanations, see the individual documentation files.

## TL;DR - What Each Workflow Does

| Workflow | What It Does | When It Runs | Output |
|----------|--------------|--------------|---------|
| **daily-build.yml** | Orchestrates daily builds for all platforms | Daily 6 AM UTC | Browser packages (Win/Linux x64/ARM64) |
| **common-build.yml** | Core build engine (reusable) | Called by wrapper workflows | Compiled browser + artifacts |
| **wrapper-build-linux.yml** | Linux build orchestration | Called by daily-build | Linux browser packages |
| **wrapper-build-windows.yml** | Windows build orchestration | Called by daily-build | Windows browser packages |
| **generate-pgo-profile-linux.yml** | Creates PGO optimization data (Linux) | PGO builds only (Stage 2) | merged.profdata + en-US.log |
| **generate-pgo-profile-windows.yml** | Creates PGO optimization data (Windows) | PGO builds only (Stage 2) | merged.profdata + en-US.log |
| **cleanup-large-caches.yml** | Deletes large GitHub Actions caches | Daily 2 AM UTC | Freed cache space |
| **misc-pull-upstream.yml** | Syncs Firefox upstream changes | Daily 11:40 AM UTC | PR with upstream updates |
| **autodiff-per-file-pr.yml** | Generates patch files from PR changes | On `@f3liz-bot patch` comment | Per-file .patch files |

## Build Flow Diagrams

### Standard Build (Debug, No PGO)
```
User triggers daily-build.yml
    │
    ├──→ Windows: wrapper-build-windows.yml → common-build.yml
    │              (2-3 hours)
    │
    ├──→ Linux x64: wrapper-build-linux.yml → common-build.yml
    │               (2-3 hours)
    │
    └──→ Linux ARM64: wrapper-build-linux.yml → common-build.yml
                      (3-4 hours, slower due to emulation)

Total time: ~4 hours (parallel)
Output: 3 browser packages
```

### PGO Build (3-Stage Pipeline)
```
User triggers with pgo: true
    │
    └──→ wrapper-build-*.yml
            │
            ├─ Stage 1: common-build.yml (pgo_mode: generate)
            │   Build browser with profiling instrumentation
            │   Output: Instrumented browser
            │   Time: 2-3 hours
            │
            ├─ Stage 2: generate-pgo-profile-*.yml
            │   Run instrumented browser with tests
            │   Collect execution profiles
            │   Output: merged.profdata + en-US.log
            │   Time: 20-30 minutes
            │
            └─ Stage 3: common-build.yml (pgo_mode: use)
                Rebuild browser with optimization data
                Output: Optimized browser (15-30% faster)
                Time: 2-3 hours

Total time: ~5-7 hours per platform
Output: Optimized browser package
```

## File Flow - What Happens to Files

### During Build
```
1. Source checkout
   ├─ git clone repo → /home/runner/work/noraneko-runtime/

2. Apply patches
   ├─ .github/patches/upstream/*.patch → Modified source tree

3. Configure
   ├─ .github/workflows/mozconfigs/{platform}-{arch}.mozconfig → mozconfig
   ├─ .github/assets/branding/* → browser/branding/

4. Compile
   ├─ Source → obj-{triplet}/dist/bin/ (compiled browser)
   ├─ obj-{triplet}/dist/bin/application.ini → nora-application.ini
   └─ obj-{triplet}/dist/host/ (MAR tools)

5. Package
   ├─ obj-{triplet}/dist/bin/ → noraneko-{platform}-{arch}-moz-artifact.{zip|tar.xz}
   └─ Upload to GitHub Actions artifacts

6. Cleanup
   └─ rm -rf ~/.cargo (save 1-2 GB)
```

### During PGO Profile Generation
```
1. Download instrumented browser
   ├─ Artifact: noraneko-{platform}-{arch}-moz-artifact → /tmp/artifact/

2. Extract and install
   ├─ /tmp/artifact/*.{zip|tar.xz} → obj-firefox/dist/firefox/

3. Generate profiles
   ├─ Run browser with tests → *.profraw files
   └─ llvm-profdata merge *.profraw → merged.profdata

4. Upload profiles
   └─ merged.profdata + en-US.log → Artifact: {platform}-{arch}-profile-generate-output
```

## Environment Variables Quick Reference

### Build-Related
```bash
# Mozilla build
MOZ_BUILD_DATE       # Override build date (reproducible builds)
MOZ_NUM_JOBS         # Parallel build jobs (default: nproc * 3/4)

# Compiler cache (sccache)
SCCACHE_GHA_ENABLED=on              # Use GitHub Actions cache
SCCACHE_MAX_FRAME_LENGTH=1048576    # Max frame size

# Build optimization
CARGO_INCREMENTAL=0  # Disable Rust incremental compilation (for PGO)
```

### PGO-Related
```bash
# Profile generation
LLVM_PROFDATA              # Path to llvm-profdata tool
JARLOG_FILE=en-US.log      # JAR access log output
MOZ_FETCHES_DIR            # Base directory for tools

# Runtime behavior
MOZ_PGO_TIMEOUT_MULTIPLIER=5  # 5x normal timeouts
MOZ_DISABLE_CONTENT_SANDBOX=1 # Disable sandboxing (headless)
MOZ_DISABLE_GMP_SANDBOX=1     # Disable GMP sandboxing

# Display (Linux)
DISPLAY=:99              # Xvfb virtual display
LIBGL_ALWAYS_SOFTWARE=1  # Software OpenGL rendering
```

## Critical Timing Requirements

| Step | Timing | Why |
|------|--------|-----|
| Xvfb startup | 3 seconds | Display must be ready before browser starts |
| Swap allocation | Before build | Prevents OOM during linking |
| PGO profile generation | 20 minutes | Instrumented browser is slow |
| PGO timeout multiplier | 5x | Instrumented code has overhead |
| Cache cleanup | 2 AM UTC | After nightly builds, before morning |
| Upstream sync | 11:40 AM UTC | After Firefox releases, evening in Japan |

## Artifact Lifetimes

| Artifact | Retention | Size | Purpose |
|----------|-----------|------|---------|
| Browser packages | 90 days (default) | 100-200 MB | Final distributable |
| PGO profiles | 7 days | 5-50 MB | Input to Stage 3 build |
| dist/host tools | 90 days | 10-20 MB | MAR update package creation |
| application.ini | 90 days | <1 MB | Browser metadata |

## Resource Requirements

### Disk Space
```
Free space needed:
- Standard build: 30-40 GB
- PGO build: 40-50 GB
- After swap allocation script: +30 GB free

Breakdown:
- Source code: 3 GB
- Build artifacts: 15-25 GB
- sccache: 5-10 GB
- Swap: 30 GB
```

### Memory
```
Recommended:
- Standard build: 8 GB RAM + 30 GB swap
- PGO build: 16 GB RAM + 30 GB swap

Peak usage during linking: 20-30 GB
```

### CPU
```
Parallel jobs: (nproc * 3/4)
- 4 cores → 3 jobs
- 8 cores → 6 jobs
- 16 cores → 12 jobs

Build time:
- Cold cache: 2-4 hours
- Warm cache: 30-60 minutes
```

## Common Failure Patterns

### 1. Out of Disk Space
**Symptoms**: "No space left on device" during linking
**Fix**: allocate-swap.sh frees ~30 GB
**Prevention**: Always run swap allocation before build

### 2. Patch Application Failure
**Symptoms**: "patch does not apply"
**Cause**: Upstream changed file that patch modifies
**Fix**: Update patch file or remove conflicting patch
**Detection**: misc-pull-upstream.yml validates patches

### 3. PGO Profile Missing
**Symptoms**: Stage 3 fails with "Artifact not found"
**Cause**: Stage 2 failed or artifact expired (7 days)
**Fix**: Re-run full PGO pipeline (Stage 1 → 2 → 3)

### 4. Timeout
**Symptoms**: Job exceeds 6-hour limit
**Cause**: Cold cache + slow disk I/O
**Fix**: sccache caches compilation (automatic)

### 5. Empty PGO Profile
**Symptoms**: merged.profdata exists but is 0 bytes
**Cause**: Browser crashed during profiling
**Fix**: Check Xvfb setup, increase timeouts

## Quick Commands

### Manually Trigger Builds
```bash
# Standard debug build (all platforms)
gh workflow run daily-build.yml

# PGO-optimized build (specific platform)
gh workflow run wrapper-build-linux.yml \
  -f debug=false \
  -f pgo=true

# Test build (single platform, debug)
gh workflow run wrapper-build-windows.yml \
  -f debug=true \
  -f pgo=false
```

### Cache Management
```bash
# List caches (dry run)
gh workflow run cleanup-large-caches.yml \
  -f dry_run=true \
  -f size_threshold_mb=1

# Delete large caches
gh workflow run cleanup-large-caches.yml \
  -f dry_run=false \
  -f size_threshold_mb=10
```

### Upstream Sync
```bash
# Manual sync
gh workflow run misc-pull-upstream.yml

# Check for sync PRs
gh pr list --label sync
```

### Patch Management
```bash
# Generate patches from PR
# (Comment on PR with: @f3liz-bot patch)

# Remove specific patches
# (Comment: @f3liz-bot patch rm=file1,file2)

# Validate patches
for patch in .github/patches/upstream/*.patch; do
  git apply --check "$patch" || echo "Failed: $patch"
done
```

## Architecture Matrix

| Platform | Architectures | Runner | Container | Cross-compile |
|----------|---------------|--------|-----------|---------------|
| Linux | x86_64, aarch64 | ubuntu-latest / macos-latest | Debian Bookworm | aarch64 only |
| Windows | x86_64 | windows-latest | None | No |
| macOS | (Not implemented) | - | - | - |

### Why These Choices
- **Linux x86_64**: Native build on ubuntu-latest (fast)
- **Linux aarch64**: Docker ARM64 on macOS (GitHub has no native Linux ARM64 runners)
- **Windows**: Native build (no containerization needed on Windows)
- **macOS**: Not yet implemented (requires different toolchain setup)

## Workflow Triggers Summary

| Workflow | Schedule | Manual | Auto (workflow_call) |
|----------|----------|--------|----------------------|
| daily-build.yml | ✅ 6:00 AM UTC | ✅ | ❌ |
| common-build.yml | ❌ | ❌ | ✅ (reusable only) |
| wrapper-build-*.yml | ❌ | ✅ | ✅ |
| generate-pgo-profile-*.yml | ❌ | ❌ | ✅ (PGO Stage 2) |
| cleanup-large-caches.yml | ✅ 2:00 AM UTC | ✅ | ❌ |
| misc-pull-upstream.yml | ✅ 11:40 AM UTC | ✅ | ✅ |
| autodiff-per-file-pr.yml | ❌ | ❌ | ✅ (on PR comment) |

## Key File Locations

### Source Repository
```
.github/
├── workflows/
│   ├── *.yml                    # Workflow definitions
│   ├── DOCS-*.md                # This documentation
│   ├── scripts/                 # Build helper scripts
│   │   ├── setup-noraneko.sh
│   │   ├── build-and-package.sh
│   │   ├── setup-rust.sh
│   │   ├── allocate-swap.sh
│   │   └── bootstrap_mozilla.sh
│   └── mozconfigs/              # Platform-specific build configs
│       ├── linux-x86_64.mozconfig
│       ├── linux-aarch64.mozconfig
│       └── windows-x86_64.mozconfig
├── scripts/
│   └── firefox-profileserver/   # PGO profile generation
│       ├── profileserver.py
│       └── pyproject.toml
├── assets/
│   ├── branding/                # Noraneko branding assets
│   └── apt-fast/                # Fast apt wrapper (unused)
└── patches/
    ├── upstream/                # Per-file patches (auto-generated)
    ├── dev/                     # Development patches
    └── packaging/               # Build system patches
```

### Build Artifacts (During Execution)
```
~/output/
└── noraneko-{platform}-{arch}-moz-artifact.{zip|tar.xz}

obj-{triplet}/
├── dist/
│   ├── bin/           # Compiled browser
│   ├── host/          # Build tools
│   └── noraneko-*.    # Package (before moving to ~/output)
└── [build artifacts]

~/artifacts/           # Downloaded from previous stage (PGO)
├── merged.profdata
└── en-US.log
```

## Permissions Required

| Workflow | contents | actions | pull-requests |
|----------|----------|---------|---------------|
| daily-build.yml | write | - | - |
| common-build.yml | read | - | - |
| cleanup-large-caches.yml | read | write | - |
| misc-pull-upstream.yml | write | - | write |
| autodiff-per-file-pr.yml | write | - | write |

## External Dependencies

### Mozilla Infrastructure
- **mozilla-firefox/firefox**: Upstream source repository
- **Mozilla Build**: Windows toolchain (downloaded by workflow)
- **mozbase**: Python libraries for PGO profiling
- **sccache**: Compiler cache (via mozilla-actions/sccache-action)

### GitHub Actions
- **actions/checkout**: Repository checkout
- **actions/upload-artifact**: Artifact storage
- **actions/download-artifact**: Artifact retrieval
- **geekyeggo/delete-artifact**: Artifact cleanup
- **astral-sh/setup-uv**: Fast Python package manager

### System Packages
- **Rust**: 1.86.0 (specific for LLVM 19 compatibility)
- **LLVM**: 19 (llvm-profdata for PGO)
- **GTK**: 3.0 (GUI library for Firefox)
- **X11**: Virtual display support (Xvfb)

## Version Pinning Strategy

### Strictly Pinned
- **Rust**: 1.86.0 (setup-rust.sh)
  - Required for LLVM 19 compatibility in PGO builds
  
### Latest Stable
- **Node.js**: latest (actions/setup-node@v4)
- **Python**: 3.13 (Linux PGO), 3.11 (Windows PGO)
- **LLVM**: 19 (install-llvm-action)

### Upstream Controlled
- **Firefox**: release branch HEAD (always latest release)
- **mozbase**: From Firefox source tree (tied to Firefox version)

## Need More Details?

- **Workflow specifics**: See DOCS-{workflow-name}.md in .github/workflows/
- **Build configuration**: See mozconfigs/ files
- **Script details**: See inline comments in .github/workflows/scripts/
- **General overview**: See .github/README.md (this directory)

## Contributing to Documentation

When adding new workflows or scripts:
1. Add entry to .github/README.md overview
2. Create DOCS-{name}.md following the template
3. Update this Quick Reference if adding new concepts
4. Keep examples realistic and test them before documenting
