# Common Build Workflow Documentation

**File**: `common-build.yml`

## Purpose

Shared build logic for all platforms (Linux, Windows). This is a reusable workflow that handles the actual compilation, packaging, and artifact management. It's the core build engine called by platform-specific wrapper workflows.

## Triggers

```yaml
on:
  workflow_call:  # Only callable by other workflows
```

This workflow cannot be triggered directly. It must be called from:
- `wrapper-build-linux.yml`
- `wrapper-build-windows.yml`

## Dependencies Graph

```
common-build.yml (Single Job: "build")
    │
    ├─ Setup Steps (Parallel preparation)
    │   ├─→ Setup Node.js
    │   └─→ Checkout repository
    │
    ├─ Patch Application
    │   └─→ Apply upstream patches
    │
    ├─ Build Environment Setup (Sequential)
    │   ├─→ Setup sccache (compiler cache)
    │   ├─→ Setup Rust toolchain (platform/arch specific)
    │   └─→ Allocate swap space (prevents OOM)
    │
    ├─ PGO Profile Download (Conditional: pgo_mode == 'use')
    │   └─→ Download artifact from Stage 2
    │
    ├─ Configuration & Build (Sequential)
    │   ├─→ Setup noraneko configuration (mozconfig + branding)
    │   └─→ Build and package (mach configure → mach build → mach package)
    │
    ├─ Artifact Cleanup (Platform-specific)
    │   ├─→ Clean Windows artifacts (if platform == windows)
    │   ├─→ Clean Linux x86_64 artifacts (if platform == linux && arch == x86_64)
    │   └─→ Clean Linux aarch64 artifacts (if platform == linux && arch == aarch64)
    │
    └─ Artifact Upload (Parallel uploads)
        ├─→ Upload build artifact (browser package)
        ├─→ Upload PGO profile generation package (if pgo_mode == 'generate' && Windows)
        ├─→ Upload dist/host (for MAR updates)
        └─→ Upload application.ini
```

## Data Flow Between Steps

### Input Parameters

```yaml
inputs:
  platform: string [linux|windows|mac] (required)
  arch: string [x86_64|aarch64] (required)
  debug: boolean (required, default: true)
  release: boolean (default: true) - Not currently used
  code-coverage: boolean (default: false) - Not currently used
  pgo: boolean (default: false)
  pgo_mode: string ["generate"|"use"|""] (default: "")
  pgo_artifact_name: string (default: "")
  MOZ_BUILD_DATE: string (default: "") - Build date override for reproducible builds
```

### Step Output Dependencies

**Critical dependency chain**:
```
Checkout → Apply patches → Setup Rust → Setup noraneko → Build
```

**PGO-specific chain**:
```
(Stage 1) Build with pgo_mode=generate → Upload instrumented browser
    ↓
(Stage 2) generate-pgo-profile-*.yml downloads instrumented browser
    ↓
(Stage 2) generates merged.profdata + en-US.log → Upload profiles
    ↓
(Stage 3) Download profiles → Build with pgo_mode=use → Upload optimized browser
```

### Environment Variables Flow

**Set in setup-noraneko.sh, used in build-and-package.sh**:
- `MOZ_BUILD_DATE`: Propagated through both steps for reproducible builds

**Set for sccache (both setup-noraneko and build-and-package)**:
- `SCCACHE_GHA_ENABLED=on`: Enables GitHub Actions cache backend
- `SCCACHE_MAX_FRAME_LENGTH=1048576`: Increases frame size for large compilation units

### Artifact Data Flow

**Standard build**:
```
build-and-package.sh
    → Creates: ~/output/noraneko-{platform}-{arch}-moz-artifact.{zip|tar.xz}
    → Upload: "noraneko-{platform}-{arch}-moz-artifact"
```

**PGO Stage 1** (generate):
```
build-and-package.sh (with ac_add_options --enable-profile-generate=cross)
    → Creates: Instrumented browser with profiling hooks
    → Upload: "noraneko-{platform}-{arch}-moz-artifact" (instrumented)
    → Upload: "noraneko-windows-x86_64-profile-generate-mode-package" (Windows only, copy)
```

**PGO Stage 3** (use):
```
Download: {platform}-{arch}-profile-generate-output (merged.profdata + en-US.log)
    → Place in: ~/artifacts/
build-and-package.sh (with --enable-profile-use=cross + --with-pgo-profile-path)
    → Creates: Optimized browser using profile data
    → Upload: "noraneko-{platform}-{arch}-moz-artifact" (optimized, replaces previous)
```

## State Changes

### File System Transformations

**1. Source Code → Patched Source** (Apply upstream patches)
```bash
for patch in .github/patches/upstream/*.patch; do
  git apply --verbose "$patch"
done
```
- **Why this exists**: Maintains upstream compatibility while applying Noraneko-specific changes
- **State after**: Source tree includes all modifications from patch files

**2. Patched Source → Configured Build** (Setup noraneko configuration)
```bash
# Copies appropriate mozconfig for platform/arch
cp .github/workflows/mozconfigs/{platform}-{arch}.mozconfig mozconfig

# Installs branding assets
cp -r .github/assets/branding/* ./browser/branding/

# Appends configuration to mozconfig
echo "ac_add_options --with-branding=browser/branding/noraneko-unofficial" >> mozconfig
```
- **State after**: 
  - `mozconfig` file exists at repo root
  - Branding files copied to `browser/branding/`
  - Build directory ready for `mach configure`

**3. Configured Build → Object Files** (Build and package)
```bash
./mach configure  # Generates build system
./mach build      # Compiles source → object files
./mach package    # Object files → browser archive
```
- **State after**:
  - Linux: `obj-{arch}-*-linux-gnu/dist/noraneko-*.tar.xz`
  - Windows: `obj-x86_64-pc-windows-msvc/dist/noraneko-*win64.zip`
  - Compilation artifacts in obj-* directory
  - ~/.cargo removed to save space

**4. Object Files → Packaged Artifacts** (Artifact packaging)
```bash
mkdir -p ~/output
mv obj-*/dist/noraneko-*.{zip|tar.xz} ~/output/
cp obj-*/dist/bin/application.ini ./nora-application.ini
```
- **State after**:
  - Browser package in ~/output/
  - application.ini copied for MAR generation
  - Original obj-* directory remains (for dist/host tools)

### Directory Structure Created

**During build**:
```
{repo_root}/
├── mozconfig (created by setup-noraneko.sh)
├── obj-{target-triplet}/ (created by mach configure)
│   ├── dist/
│   │   ├── bin/ (browser executable and libraries)
│   │   ├── host/ (build tools for MAR generation)
│   │   └── noraneko-*.{zip|tar.xz} (final package)
│   └── [compiled objects and build artifacts]
├── nora-application.ini (created by build-and-package.sh)
└── ~/output/
    └── noraneko-{platform}-{arch}-moz-artifact.{zip|tar.xz}
```

**For PGO builds**:
```
~/artifacts/ (created by Download PGO artifact step)
├── merged.profdata (LLVM profile data)
└── en-US.log (JAR access log)
```

## Hidden Dependencies

### Tool Dependencies (Auto-installed)

**setup-rust.sh**:
- Installs Rust 1.86.0 (specific version for LLVM 19 compatibility)
- Adds platform-specific target:
  - Windows: `x86_64-pc-windows-msvc`
  - Linux x86_64: `x86_64-unknown-linux-gnu`
  - Linux aarch64: `aarch64-unknown-linux-gnu`
- Sets `CARGO_INCREMENTAL=0` (disables incremental compilation for PGO)

**setup-noraneko.sh**:
- Installs `msitools` (for Windows installer packaging on Linux)
- Runs `./mach bootstrap` (downloads Mozilla build dependencies)

**allocate-swap.sh**:
- Allocates 30GB swap space (prevents OOM during linking)
- Removes large unused directories (frees ~30GB disk space)

### Platform-Specific Prerequisites

**Linux**:
- Xvfb (virtual display for headless build)
- mesa-utils (software OpenGL rendering)
- rsync (for efficient directory cleanup)

**Windows**:
- Native Windows runner (no containerization)
- MSVC toolchain (installed by mach bootstrap)
- Windows SDK (installed by mach bootstrap)

**Linux aarch64** (cross-compilation):
- Docker with ARM64 platform support
- QEMU (for ARM instruction emulation)
- Cross-compilation toolchain (aarch64-linux-gnu)

### Execution Order Requirements

**Critical sequence**:
1. **Checkout must complete before Apply patches**
   - Patches applied to repository files
   
2. **Apply patches must complete before Setup Rust**
   - Ensures correct source state for dependency calculation
   
3. **Setup Rust must complete before Allocate swap**
   - Rust installation uses disk space; swap allocation needs accurate free space

4. **Allocate swap must complete before Setup noraneko**
   - mach bootstrap downloads large files; needs swap space

5. **Setup noraneko must complete before Build**
   - Creates mozconfig required by mach configure

**PGO-specific sequence**:
```
For pgo_mode='use':
  Download PGO artifact → Setup noraneko (configures PGO paths) → Build
  
  If artifact download fails:
    Build fails immediately (cannot proceed without profile data)
```

### Why Artifact Cleanup Exists

**Problem**: GitHub Actions artifacts are immutable once uploaded with a name
- Multiple builds (or PGO stages) want to upload with same artifact name
- Without cleanup, upload fails with "artifact already exists"

**Solution**: Delete existing artifacts before uploading new ones
```yaml
- name: Clean existing Windows artifacts
  if: inputs.platform == 'windows'
  uses: geekyeggo/delete-artifact@v5
  with:
    name: |
      noraneko-windows-x86_64-moz-artifact
      windows-x86_64-dist-host
      windows-x86_64-application-ini
```

**When this matters**:
- PGO Stage 1 uploads instrumented browser
- PGO Stage 3 wants to upload optimized browser with same name
- Without cleanup, Stage 3 upload fails

## Architecture Variations

### Platform-Specific Build Commands

**Linux**:
```bash
export LIBGL_ALWAYS_SOFTWARE=1  # Software rendering for headless
xvfb-run -a -s "-screen 0 1024x768x24" ./mach configure
xvfb-run -a -s "-screen 0 1024x768x24" nice -n 10 ./mach build --jobs=$MOZ_NUM_JOBS
xvfb-run -a -s "-screen 0 1024x768x24" ./mach package
```
- **Why Xvfb**: Some build steps require X11 display (even for headless)
- **Why nice -n 10**: Reduces priority to avoid starving system processes
- **Jobs**: (nproc * 3/4) to leave resources for other tasks

**Windows**:
```bash
./mach configure
nice -n 10 ./mach build --jobs=$MOZ_NUM_JOBS
./mach package
```
- **No Xvfb**: Windows has native windowing system
- **Same nice/jobs logic**: Prevents resource exhaustion

### PGO Mode Differences

**pgo_mode='generate'**:
```bash
# In mozconfig:
ac_add_options --enable-profile-generate=cross
```
- **Output**: Browser with profiling instrumentation
- **Size**: ~20-30% larger due to instrumentation code
- **Performance**: ~50% slower due to profiling overhead
- **Purpose**: Collects execution data during Stage 2

**pgo_mode='use'**:
```bash
# In mozconfig:
export MOZ_LTO=cross
ac_add_options --enable-profile-use=cross
ac_add_options --with-pgo-profile-path=~/artifacts/merged.profdata
ac_add_options --with-pgo-jarlog=~/artifacts/en-US.log
```
- **Output**: Optimized browser using profile data
- **Size**: Normal (instrumentation removed)
- **Performance**: ~15-30% faster than non-PGO build
- **Purpose**: Final optimized build for distribution

### Why 'cross' PGO Mode

**cross vs default**:
- `--enable-profile-generate=cross`: Generates portable profile data
- `--enable-profile-use=cross`: Can use profile data from different machine
- **Why needed**: Stage 1 and Stage 3 may run on different runners
- **Alternative**: `--enable-lto` (Link-Time Optimization) without cross would require same hardware

## Process Logic

### Submodule Checkout Strategy

```yaml
submodules: >-
  ${{ inputs.platform == 'mac' && 'recursive' || 'true' }}
```

**Meaning**:
- macOS: Recursive submodules (includes nested submodules)
- Others: Non-recursive (only immediate submodules)

**Why this difference**:
- macOS builds may need additional submodules for frameworks
- Linux/Windows: Flatter dependency structure

### Parallel Job Calculation

```bash
export MOZ_NUM_JOBS=$(( $(nproc) * 3 / 4 ))
```

**Examples**:
- 4 cores → 3 jobs
- 8 cores → 6 jobs
- 16 cores → 12 jobs

**Why 75% instead of 100%**:
- Leaves resources for system processes
- Prevents build failures due to memory exhaustion
- Reduces chance of timeout due to resource contention

### Artifact Overwrite Strategy

```yaml
- name: Upload dist/host for MAR
  uses: actions/upload-artifact@v4
  with:
    overwrite: true  # Allows replacing existing artifact
```

**Why overwrite is needed**:
- dist/host contains build tools (e.g., mar tool for update packages)
- Multiple builds (PGO stages) need to upload this
- Overwrite allows latest version to replace previous

## When Timing Is Critical

### Swap Allocation First
```yaml
- name: Allocate swap space
  run: ./.github/workflows/scripts/allocate-swap.sh "${{ inputs.arch }}"
```

**Why early**: 
- Large C++ compilations can exceed RAM (especially during linking)
- Swap prevents OOM killer from terminating build
- Must happen before heavy compilation starts

**Time cost**: ~5 minutes to allocate 30GB swap

### sccache Setup Early
```yaml
- name: Setup sccache
  uses: mozilla-actions/sccache-action@v0.0.9
```

**Why early**:
- Must be available before first compilation
- Caches compilation results for future builds
- Dramatically reduces incremental build time (hours → minutes)

**Time saved**: 50-80% on repeated builds with warm cache

### Rust Setup Before Bootstrap
```yaml
- name: Setup Rust toolchain
- name: Setup noraneko configuration (runs mach bootstrap)
```

**Why ordered**:
- mach bootstrap checks Rust version
- If wrong version installed, bootstrap may install its own
- Installing correct version first prevents duplicate downloads

## When Steps Can Be Skipped

### Conditional Artifact Cleanup

```yaml
- name: Clean existing Windows artifacts
  if: inputs.platform == 'windows'
  
- name: Clean existing Linux x86_64 artifacts
  if: inputs.platform == 'linux' && inputs.arch == 'x86_64'
  
- name: Clean existing Linux aarch64 artifacts
  if: inputs.platform == 'linux' && inputs.arch == 'aarch64'
```

**Only one cleanup runs**: Matches current platform/arch

### Conditional PGO Upload

```yaml
- name: Upload PGO profile generation package
  if: >-
    inputs.pgo_mode == 'generate' &&
    inputs.platform == 'windows' &&
    inputs.arch == 'x86_64'
```

**Why Windows-only**:
- Windows PGO profile generation has different artifact name
- Linux uses standard artifact name
- This is a duplicate upload with alternate name for Windows PGO Stage 2

### Conditional PGO Download

```yaml
- name: Download PGO artifact
  if: inputs.pgo_mode == 'use' && inputs.pgo_artifact_name != ''
```

**Only Stage 3 downloads**: Stage 1 and normal builds skip

## Common Failure Points

### 1. Out of Disk Space
**When**: During linking or packaging
**Why**: Object files can exceed 50GB
**Solution**: allocate-swap.sh frees ~30GB
**Detection**: Error message contains "No space left on device"

### 2. Patch Application Failure
**When**: After checkout
**Why**: Upstream changed file that patch modifies
**Solution**: Update patch files via autodiff-per-file-pr.yml
**Detection**: "patch does not apply"

### 3. PGO Profile Missing
**When**: Stage 3 (pgo_mode='use')
**Why**: Stage 2 failed or artifact expired (7-day retention)
**Solution**: Re-run full PGO pipeline (Stage 1 → 2 → 3)
**Detection**: "Artifact not found" in Download PGO artifact step

### 4. Timeout
**When**: Build exceeds 6 hours
**Why**: Cold cache + large codebase
**Solution**: Enable sccache (automatic in this workflow)
**Detection**: GitHub Actions "The job running on runner... has exceeded the maximum execution time of 360 minutes"

## Related Workflows

- **wrapper-build-linux.yml**: Calls this workflow for Linux builds
- **wrapper-build-windows.yml**: Calls this workflow for Windows builds
- **generate-pgo-profile-linux.yml**: Uses artifacts from Stage 1
- **generate-pgo-profile-windows.yml**: Uses artifacts from Stage 1
