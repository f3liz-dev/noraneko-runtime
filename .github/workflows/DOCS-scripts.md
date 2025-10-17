# Build Scripts Documentation

This document explains all build and helper scripts in the `.github/workflows/scripts/` directory.

## Overview

| Script | Purpose | Called By | Critical? |
|--------|---------|-----------|-----------|
| **setup-noraneko.sh** | Configure build environment | common-build.yml | ✅ Yes |
| **build-and-package.sh** | Compile and package browser | common-build.yml | ✅ Yes |
| **setup-rust.sh** | Install Rust toolchain | common-build.yml | ✅ Yes |
| **allocate-swap.sh** | Allocate swap and free disk | common-build.yml | ✅ Yes |
| **bootstrap_mozilla.sh** | Setup Mozilla build dependencies | (Not currently used) | ❌ No |

## setup-noraneko.sh

**Purpose**: Configures the build environment by setting up mozconfig, branding, and running Mozilla bootstrap.

### Parameters
```bash
$1: platform (linux|mac|windows)
$2: arch (x86_64|aarch64)
$3: debug (true|false)
$4: pgo (true|false)
$5: pgo_mode ("generate"|"use"|"")
$6: pgo_artifact_name (string, for "use" mode)
$7: MOZ_BUILD_DATE (optional, for reproducible builds)
```

### What It Does

#### 1. Copy Platform-Specific mozconfig
```bash
if [[ "$PLATFORM" == "windows" ]]; then
  cp ./.github/workflows/mozconfigs/windows-x86_64.mozconfig mozconfig
elif [[ "$PLATFORM" == "linux" ]]; then
  if [[ "$ARCH" == "aarch64" ]]; then
    cp ./.github/workflows/mozconfigs/linux-aarch64.mozconfig mozconfig
  else
    cp ./.github/workflows/mozconfigs/linux-x86_64.mozconfig mozconfig
  fi
fi
```

**Result**: `mozconfig` file created at repository root

#### 2. Install Branding Assets
```bash
cp -r ./.github/assets/branding/* ./browser/branding/
```

**Copies**:
- Icons (various sizes and formats)
- Installer graphics
- About page logos
- Localized brand strings

**Result**: Branding files available at `browser/branding/noraneko-unofficial/`

#### 3. Configure Branding in mozconfig
```bash
echo "ac_add_options --with-branding=browser/branding/noraneko-unofficial" >> mozconfig
echo "ac_add_options --enable-chrome-format=flat" >> mozconfig
```

**Flat chrome format effects**:
- Faster startup (omni.ja not unpacked every time)
- Standard for modern Firefox builds
- Better for development builds

#### 4. Install msitools (Windows Installer Support)
```bash
sudo apt install msitools -y
```

**Function on Linux runners**:
- Cross-compiling Windows builds on Linux
- Creates MSI installer packages
- Windows builds run on Linux with cross-compilation tools

#### 5. Configure sccache (Compiler Cache)
```bash
{
  echo "mk_add_options 'export RUSTC_WRAPPER=/opt/hostedtoolcache/sccache/0.10.0/x64/sccache'"
  echo "mk_add_options 'export CCACHE_CPP2=yes'"
  echo "ac_add_options --with-ccache=/opt/hostedtoolcache/sccache/0.10.0/x64/sccache"
  echo "mk_add_options 'export SCCACHE_GHA_ENABLED=on'"
  echo "mk_add_options 'export SCCACHE_MAX_FRAME_LENGTH=1048576'"
} >> mozconfig
```

**sccache configuration**:
- `mozilla-actions/sccache-action@v0.0.9` installs to specific location
- Hardcoded path ensures consistent cache location across runs
- GHA_ENABLED integrates with GitHub Actions cache

#### 6. Configure Debug Build
```bash
if [[ "$DEBUG" == "true" ]]; then
  echo "ac_add_options --enable-debug" >> mozconfig
fi
```

**Debug build effects**:
- Includes debugging symbols
- No optimization (faster compile, slower runtime)
- Easier to debug crashes
- ~2-3x larger binary size

#### 7. Configure PGO
```bash
if [[ "$PGO" == "true" ]]; then
  if [[ "$PGO_MODE" == "generate" ]]; then
    echo 'ac_add_options --enable-profile-generate=cross' >> mozconfig
  elif [[ "$PGO_MODE" == "use" && -n "$PGO_ARTIFACT_NAME" ]]; then
    echo 'export MOZ_LTO=cross' >> mozconfig
    echo 'ac_add_options --enable-profile-use=cross' >> mozconfig
    echo 'ac_add_options --with-pgo-profile-path=$(echo ~)/artifacts/merged.profdata' >> mozconfig
    echo 'ac_add_options --with-pgo-jarlog=$(echo ~)/artifacts/en-US.log' >> mozconfig
  fi
fi
```

**PGO mode effects**:

**generate**:
- Adds profiling instrumentation
- Browser collects execution data at runtime
- Slower execution (~50% overhead)
- Larger binary (profiling code included)

**use**:
- Uses collected profiles for optimization
- Enables LTO (Link-Time Optimization)
- Optimizes hot paths (frequently executed code)
- 15-30% faster final binary

#### 8. Configure Update Channel
```bash
echo "ac_add_options --enable-update-channel=alpha" >> mozconfig
```

**Update channels**:
- **alpha**: Development builds (this project)
- **beta**: Pre-release testing
- **release**: Stable public releases
- **nightly**: Daily automated builds

#### 9. Modify Update URL
```bash
sed -i 's|https://@MOZ_APPUPDATE_HOST@/update/6/%PRODUCT%/...|https://github.com/nyanrus/noraneko/releases/download/%CHANNEL%/%BUILD_TARGET%.update.xml|g' ./build/application.ini.in
```

**Update URL modification**:
- Default points to Mozilla update servers
- Noraneko updates hosted on GitHub releases
- Format: `https://github.com/{owner}/{repo}/releases/download/{channel}/{platform}.update.xml`

#### 10. Run Mozilla Bootstrap
```bash
./mach --no-interactive bootstrap --application-choice browser
```

**What bootstrap does**:
- Downloads Mozilla build dependencies
- Installs Python packages (mozbase)
- Sets up Rust targets
- Configures build environment
- Downloads clang/llvm if needed

**Time**: 5-15 minutes (first run), seconds (subsequent runs with cache)

### Hidden Dependencies

**Requires**:
- Git repository checkout
- Internet connection (for mach bootstrap)
- sudo access (for apt install)
- Python 3.x
- Rust (installed by setup-rust.sh first)

**Creates**:
- `mozconfig` at repository root
- `browser/branding/` populated with assets
- `~/.mozbuild/` (Mozilla build state)

### Error Handling

**No error handling** - Script fails on any error (`set -e`)

**Common failures**:
1. **Missing mozconfig source**: Wrong platform/arch combination
2. **mach bootstrap fails**: Network issues or dependency conflicts
3. **apt install fails**: Package not available or permission denied

---

## build-and-package.sh

**Purpose**: Executes the Mozilla build system and packages the compiled browser.

### Parameters
```bash
$1: platform (linux|mac|windows)
$2: arch (x86_64|aarch64)
$3: MOZ_BUILD_DATE (optional, for reproducible builds)
```

### What It Does

#### 1. Calculate Parallel Jobs
```bash
export MOZ_NUM_JOBS=$(( $(nproc) * 3 / 4 ))
```

**Examples**:
- 4 cores → 3 jobs
- 8 cores → 6 jobs
- 16 cores → 12 jobs

**Resource allocation**:
- Leaves CPU for system processes
- Prevents memory exhaustion
- Reduces I/O contention

#### 2. Platform-Specific Build Commands

**Linux**:
```bash
sudo apt-get install -y xvfb mesa-utils
export LIBGL_ALWAYS_SOFTWARE=1
xvfb-run -a -s "-screen 0 1024x768x24" ./mach configure
xvfb-run -a -s "-screen 0 1024x768x24" nice -n 10 ./mach build --jobs=$MOZ_NUM_JOBS
xvfb-run -a -s "-screen 0 1024x768x24" ./mach package
```

**Xvfb function**:
- Some build steps need X11 display (even headless)
- Xvfb provides virtual display
- `-a`: Automatically choose display number
- `-s "-screen 0 1024x768x24"`: Virtual screen configuration

**LIBGL_ALWAYS_SOFTWARE effect**:
- Forces software OpenGL rendering
- No GPU required (headless environment)
- Prevents GPU driver issues

**nice -n 10 effect**:
- Reduces process priority
- Prevents starving system processes
- Still gets most CPU time but yields to higher priority tasks

**Windows/Mac**:
```bash
./mach configure
nice -n 10 ./mach build --jobs=$MOZ_NUM_JOBS
./mach package
```

**No Xvfb**: Native windowing system available

#### 3. Build Process Details

**mach configure**:
- Reads `mozconfig` file
- Detects system capabilities
- Generates build system files
- Creates `obj-{triplet}/` directory
- Time: 2-5 minutes

**mach build**:
- Compiles C++, Rust, JavaScript
- Links libraries
- Processes resources
- Uses sccache for caching
- Time: 30 minutes (warm cache) to 3 hours (cold cache)

**mach package**:
- Assembles compiled files
- Creates browser archive (zip/tar.xz)
- Generates installation files
- Time: 5-10 minutes

#### 4. Cleanup
```bash
rm -rf ~/.cargo
```

**Cleanup rationale**:
- Saves 1-2 GB disk space
- Rust artifacts not needed after build
- ~/.cargo includes downloaded crates
- Build already complete

#### 5. Package Artifacts
```bash
mkdir -p ~/output

ARTIFACT_NAME="noraneko-${PLATFORM}-${ARCH}-moz-artifact"

if [[ "$PLATFORM" == "windows" ]]; then
  mv obj-x86_64-pc-windows-msvc/dist/noraneko-*win64.zip ~/output/${ARTIFACT_NAME}.zip
  cp ./obj-x86_64-pc-windows-msvc/dist/bin/application.ini ./nora-application.ini || true
elif [[ "$PLATFORM" == "linux" ]]; then
  if [[ "$ARCH" == "aarch64" ]]; then
    mv obj-aarch64-unknown-linux-gnu/dist/noraneko-*.tar.xz ~/output/${ARTIFACT_NAME}.tar.xz
    cp ./obj-aarch64-unknown-linux-gnu/dist/bin/application.ini ./nora-application.ini || true
  else
    mv obj-x86_64-pc-linux-gnu/dist/noraneko-*.tar.xz ~/output/${ARTIFACT_NAME}.tar.xz
    cp obj-x86_64-pc-linux-gnu/dist/bin/application.ini ./nora-application.ini || true
  fi
fi
```

**Artifact structure**:
```
~/output/
└── noraneko-{platform}-{arch}-moz-artifact.{zip|tar.xz}

./nora-application.ini (at repo root)
```

**application.ini**:
- Browser metadata (version, build ID, etc.)
- Used by MAR (Mozilla Archive) tool for updates
- Copied to repo root for easy artifact upload

### Hidden Dependencies

**Requires**:
- `mozconfig` file (created by setup-noraneko.sh)
- Source code (checked out)
- Rust toolchain (installed by setup-rust.sh)
- Disk space: 30-40 GB free
- Memory: 8 GB + swap

**Creates**:
- `obj-{triplet}/` directory (15-25 GB)
- Browser package in ~/output/
- application.ini at repo root

### Error Handling

**No error handling** - Script fails on any error (`set -e`)

**Common failures**:
1. **Out of memory**: Linking fails (need swap)
2. **Out of disk space**: Build artifacts fill disk
3. **Compilation error**: Source code issue or missing dependency
4. **Package not found**: Build succeeded but package creation failed

---

## setup-rust.sh

**Purpose**: Installs the correct Rust version and target for the platform/architecture.

### Parameters
```bash
$1: platform (linux|mac|windows)
$2: arch (x86_64|aarch64) - optional for some platforms
$3: pgo_artifact_name - optional, determines Rust version for PGO
```

### What It Does

#### 1. Determine Rust Version
```bash
if [[ "$PLATFORM" == "windows" ]]; then
  if [[ -n "$PGO_ARTIFACT_NAME" ]]; then
    rustup default 1.86.0  # For LLVM 19 compatibility
  fi
  rustup target add x86_64-pc-windows-msvc
```

**Rust version for PGO**:
- Rust 1.86.0 compiled with LLVM 19
- PGO uses llvm-profdata from LLVM 19
- Version mismatch causes profile format errors
- Reference: https://github.com/rust-lang/rust/commits/master/src/llvm-project

**Standard builds**: Use latest Rust (no version specified)

#### 2. Install Platform Targets

**Windows**:
```bash
rustup target add x86_64-pc-windows-msvc
```

**Linux x86_64**:
```bash
rustup default 1.86.0
rustup target add x86_64-unknown-linux-gnu
```

**Linux aarch64**:
```bash
rustup default 1.86.0
rustup target add aarch64-unknown-linux-gnu
```

#### 3. Verify and Configure
```bash
rustc --version --verbose
export CARGO_INCREMENTAL=0
```

**CARGO_INCREMENTAL=0**:
- Disables incremental compilation
- Required for PGO builds (profile data changes)
- Slightly slower builds but ensures correct PGO profiles

### Hidden Dependencies

**Requires**:
- `rustup` installed (GitHub Actions runner has it)
- Internet connection (downloads Rust toolchains)

**Creates**:
- `~/.rustup/` (Rust installation)
- `~/.cargo/` (Cargo registry and binaries)

---

## allocate-swap.sh

**Purpose**: Allocates 30GB swap space and frees disk space by removing unused system files.

### What It Does

#### 1. Show Initial State
```bash
echo "Before:"
free -h
df -h
```

**Output example**:
```
              total        used        free
Mem:           7.7G        2.0G        5.7G
Swap:          4.0G        0.0G        4.0G

Filesystem      Size  Used Avail Use%
/dev/sda1        84G   20G   64G  24%
```

#### 2. Recreate Swap File
```bash
sudo swapoff /mnt/swapfile          # Disable existing swap
sudo rm /mnt/swapfile               # Remove old swap file
sudo fallocate -l 30G /mnt/swapfile # Allocate 30GB quickly
sudo chmod 600 /mnt/swapfile        # Secure permissions
sudo mkswap /mnt/swapfile           # Format as swap
sudo swapon /mnt/swapfile           # Enable new swap
```

**Swap configuration**:
- 30GB provides headroom for Firefox linking (20-25 GB memory usage)
- 8 GB RAM + 30 GB swap = 38 GB total
- Comfortable margin for peak usage

**fallocate vs dd**:
- `fallocate`: Instant (reserves space without writing)
- `dd`: 5-10 minutes (writes zeros to fill file)
- Both create swap file, fallocate much faster

#### 3. Clean Package Manager
```bash
sudo apt autoremove -y -qq  # Remove unused packages
sudo apt clean              # Clear package cache
```

**Frees**: 500 MB - 2 GB

#### 4. Remove Large System Directories
```bash
# Optimized removal using rsync method
mkdir -p /tmp/empty

remove_dir() {
    local dir="$1"
    if [ -d "$dir" ]; then
        echo "Removing: $dir"
        sudo rsync -a --delete /tmp/empty/ "$dir/" 2>/dev/null
        sudo rmdir "$dir" 2>/dev/null
    fi
}
```

**rsync deletion method**:
- `rm -rf /huge/directory`: Very slow (processes each file)
- `rsync --delete /empty/ /huge/`: Fast (batch deletion)
- Can save 10-20 minutes on large directories

**Directories removed**:
```bash
./git                        # ~1 GB
/home/linuxbrew             # ~500 MB
/usr/share/dotnet           # ~2 GB
/usr/local/lib/android      # ~8 GB
/usr/local/graalvm          # ~1 GB
/usr/local/share/powershell # ~200 MB
/usr/local/share/chromium   # ~500 MB
/opt/ghc                    # ~5 GB
/usr/local/share/boost      # ~2 GB
/etc/apache2                # ~50 MB
/etc/nginx                  # ~50 MB
/usr/local/share/chrome_driver  # ~20 MB
/usr/local/share/edge_driver    # ~20 MB
/usr/local/share/gecko_driver   # ~10 MB
/usr/share/java             # ~1 GB
/usr/share/miniconda        # ~3 GB
/usr/local/share/vcpkg      # ~1 GB
```

**Total freed**: ~25-30 GB

#### 5. Show Final State
```bash
echo "After:"
free -h
df -h
```

**Output example**:
```
              total        used        free
Mem:           7.7G        2.0G        5.7G
Swap:           30G        0.0G         30G

Filesystem      Size  Used Avail Use%
/dev/sda1        84G   20G   94G  18%
```

**Result**: +30 GB swap, +30 GB free disk space

### Script Execution Timing

**Execution order**:
```
1. Checkout repository
2. Apply patches
3. Setup sccache
4. Setup Rust
5. Allocate swap ← Runs here
6. Setup noraneko (mach bootstrap)
7. Build
```

**Sequencing**:
- Runs before mach bootstrap (which downloads ~2-3 GB dependencies)
- Runs before build (linking step can use 20+ GB memory)
- Too late to allocate swap during build

**Timing**:
- mach bootstrap needs free disk space
- Swap not needed yet (no compilation)
- Linking step requires swap (prevents OOM killer)

**Duration**: ~5 minutes to allocate 30GB swap

### Hidden Dependencies

**Requires**:
- sudo access (for swap operations and directory removal)
- /mnt/ directory (standard on GitHub Actions runners)
- rsync (for fast directory removal)

**Does not require**:
- Any other script completion
- Source code checkout
- Build environment setup

---

## bootstrap_mozilla.sh

**Purpose**: Alternative bootstrap script for setting up Mozilla build environment. **Not currently used in workflows.**

### What It Would Do (If Used)

This script is more comprehensive than the workflow's inline bootstrap:

1. **Detect architecture** (x86_64 or aarch64)
2. **Setup cross-compilation** (if host != target arch)
3. **Install system dependencies** (GTK, X11, audio, etc.)
4. **Install Rust** (if not present)
5. **Add Rust targets** (for cross-compilation)
6. **Setup Python venv** (isolated Python environment)
7. **Run mach bootstrap** (Mozilla dependencies)
8. **Setup LLVM tools** (for PGO)
9. **Export environment variables** (for subsequent scripts)

### Current Usage Status

**Current approach**:
- Workflows handle each step individually
- More granular control
- Easier to debug specific step failures
- Can cache individual steps

**Alternative if this script were used**:
- Single script for entire environment setup
- Harder to cache individual steps
- Failure in late step requires re-running entire script

**Potential use case**:
- Local development setup
- Docker image creation
- Alternative CI systems

---

## Script Execution Order in Workflows

```
common-build.yml execution order:

1. Checkout repository
2. Apply upstream patches
3. Setup sccache
4. setup-rust.sh         ← Rust toolchain
5. allocate-swap.sh      ← Swap and disk space
6. setup-noraneko.sh     ← Build configuration
7. build-and-package.sh  ← Compilation
8. Upload artifacts
```

**Dependencies**:
- setup-rust.sh → Provides Rust for mach bootstrap (in setup-noraneko.sh)
- allocate-swap.sh → Provides swap for build (in build-and-package.sh)
- setup-noraneko.sh → Creates mozconfig for build (in build-and-package.sh)

**Parallel possibilities**:
- setup-rust.sh and allocate-swap.sh could run in parallel (no dependencies)
- Currently sequential for simplicity

---

## Common Issues and Solutions

### Issue: "rustc not found" during build
**Cause**: setup-rust.sh didn't run or failed
**Solution**: Check setup-rust.sh output, ensure rustup available

### Issue: "No space left on device" during linking
**Cause**: allocate-swap.sh didn't run or swap not enabled
**Solution**: Verify swap is active (`free -h`), check disk space (`df -h`)

### Issue: "mozconfig not found" during mach configure
**Cause**: setup-noraneko.sh didn't run or failed
**Solution**: Check setup-noraneko.sh output, verify mozconfig exists

### Issue: "Package not found" after build
**Cause**: mach package failed or package in unexpected location
**Solution**: Check obj-*/dist/ directory, verify build completed

### Issue: PGO profile format mismatch
**Cause**: Rust version doesn't match LLVM version
**Solution**: Ensure setup-rust.sh installs Rust 1.86.0 for PGO builds

---

## Testing Scripts Locally

### Setup
```bash
# Clone repository
git clone https://github.com/f3liz-dev/noraneko-runtime
cd noraneko-runtime

# Apply patches (if needed)
for patch in .github/patches/upstream/*.patch; do
  git apply "$patch"
done
```

### Run Scripts
```bash
# Setup Rust (required first)
./.github/workflows/scripts/setup-rust.sh linux x86_64

# Allocate swap (requires sudo)
./.github/workflows/scripts/allocate-swap.sh

# Configure build
./.github/workflows/scripts/setup-noraneko.sh linux x86_64 true false "" "" ""

# Build (will take 2-4 hours)
./.github/workflows/scripts/build-and-package.sh linux x86_64
```

### Check Results
```bash
# Verify package created
ls -lh ~/output/

# Verify application.ini
cat nora-application.ini

# Check build logs
less obj-x86_64-pc-linux-gnu/dist/bin/firefox.log
```

---

## Related Documentation

- **common-build.yml**: Workflow that calls these scripts
- **QUICK-REFERENCE.md**: Quick command reference
- **README.md**: Overall .github directory overview
