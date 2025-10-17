# Generate PGO Profile (Linux) Workflow Documentation

**File**: `generate-pgo-profile-linux.yml`

## Purpose

Generates Profile-Guided Optimization (PGO) data by running an instrumented Firefox/Noraneko browser through a series of performance tests. This is Stage 2 of the 3-stage PGO build process.

## What PGO Does (Non-Technical)

Profile-Guided Optimization makes the browser faster by:
1. **Stage 1**: Build browser with tracking code ("which code runs most often?")
2. **Stage 2 (THIS WORKFLOW)**: Run browser through realistic tasks, recording what happens
3. **Stage 3**: Rebuild browser with optimizations based on recorded data

**Result**: 15-30% faster browser because compiler optimizes the "hot paths" (most-used code).

## Triggers

```yaml
on:
  workflow_call:  # Only callable by wrapper-build-linux.yml
```

Called from:
- `wrapper-build-linux.yml` (Stage 2 of PGO process)

## Dependencies Graph

```
generate-pgo-profile-linux.yml (Single Job)
    │
    ├─ Prerequisites (Parallel)
    │   ├─→ Checkout repository (for test scripts)
    │   └─→ Download browser artifact (instrumented browser from Stage 1)
    │
    ├─ System Setup (Sequential)
    │   ├─→ Install system dependencies (GTK, X11, audio, graphics libs)
    │   ├─→ Setup uv (fast Python package manager)
    │   ├─→ Setup Python 3.13
    │   └─→ Prepare build directories
    │
    ├─ LLVM Tools Setup (Critical for profile merging)
    │   ├─→ Install LLVM 19 (llvm-profdata-19)
    │   ├─→ Copy arch-specific profdata tool
    │   └─→ Create wrapper script (auto-detects architecture)
    │
    ├─ Browser Installation (Sequential)
    │   ├─→ Extract browser artifact (tar.xz or zip)
    │   ├─→ Locate and install browser (Ruby script finds binary)
    │   └─→ Find browser binary path (sets output variable)
    │
    ├─ Profile Generation Environment
    │   ├─→ Sync uv dependencies (install mozbase libraries)
    │   └─→ Start Xvfb (virtual display for headless GUI)
    │
    ├─ Profile Generation (The Core Step)
    │   └─→ Generate PGO profile data (run profileserver.py)
    │       ├─ Starts HTTP servers (port 8888, 8000)
    │       ├─ Creates Firefox profile with test preferences
    │       ├─ Runs browser: http://localhost:8888/index.html
    │       ├─ Browser executes performance tests
    │       ├─ Generates *.profraw files (raw profile data)
    │       ├─ Merges with llvm-profdata → merged.profdata
    │       └─ Generates en-US.log (JAR file access patterns)
    │
    ├─ Cleanup
    │   └─→ Stop Xvfb (always runs even if profile generation fails)
    │
    ├─ Verification
    │   └─→ Verify generated profile data (check files exist and non-empty)
    │
    └─ Upload Results
        └─→ Upload profile artifacts (merged.profdata + en-US.log)
```

## Data Flow Between Steps

### Input Parameters

```yaml
inputs:
  browser-artifact-name: string (required)
    # Example: "noraneko-linux-x86_64-moz-artifact"
    
  artifact-path: string (default: /tmp/artifact)
    # Where to extract browser archive
    
  runner: string (default: ubuntu-latest)
    # For x86_64: ubuntu-latest
    # For aarch64: macos-latest (needs ARM64 Docker)
    
  target-arch: string (default: x86_64)
    # x86_64 or aarch64
    
  upload-artifact-name: string (optional)
    # Default: "{browser-artifact-name}-profile-generate-output"
```

### Critical Data Transformations

**1. Browser Archive → Installed Browser**
```
Input: noraneko-linux-x86_64-moz-artifact.tar.xz (in ~/artifacts/)
    ↓ [Extract step]
~/artifacts/noraneko/  (extracted directory structure)
    ↓ [Locate and install step - Ruby script]
obj-firefox/dist/firefox/  (installed browser ready to run)
    ↓ [Find browser binary step]
Binary path: obj-firefox/dist/firefox/noraneko (stored in step output)
```

**2. Instrumented Browser Run → Profile Data**
```
Browser binary with profiling hooks
    ↓ [Run with profileserver.py]
*.profraw files (raw profile data, multiple files)
    ↓ [llvm-profdata merge]
merged.profdata (single unified profile)
    +
en-US.log (JAR file access log)
    ↓ [Upload step]
Artifact: {arch}-profile-generate-output (uploaded to GitHub)
```

### Environment Variables That Matter

**During profile generation**:
```yaml
MOZ_FETCHES_DIR: /tmp
  # Base directory for Mozilla tools
  
JARLOG_FILE: en-US.log
  # Output file for JAR access logging
  
LLVM_PROFDATA: ${{ env.CLANG_TOOLS_DIR }}/bin/llvm-profdata
  # Path to profdata merging tool
  
DISPLAY: :99
  # Virtual display for Xvfb
  
MOZ_PGO_TIMEOUT_MULTIPLIER: 5
  # Increases timeouts by 5x (profile generation is slower)
  
MOZ_DISABLE_CONTENT_SANDBOX: 1
MOZ_DISABLE_GMP_SANDBOX: 1
  # Disables sandboxing (simplifies headless environment)
```

### Step Outputs Used by Later Steps

```yaml
# Set by "Find browser binary path" step
steps.find-binary.outputs.binary-path
  # Example: "obj-firefox/dist/firefox/noraneko"
  # Used by: "Generate PGO profile data" step
```

## State Changes

### File System Before This Workflow
```
/home/runner/work/noraneko-runtime/noraneko-runtime/
├── .github/
│   └── scripts/firefox-profileserver/
│       ├── profileserver.py
│       └── pyproject.toml
└── [source code]
```

### File System After Extraction
```
/tmp/artifact/ (inputs.artifact-path)
├── noraneko-linux-x86_64-moz-artifact.tar.xz (downloaded)
└── noraneko/ (extracted)
    ├── noraneko (or firefox, firefox-bin) - browser executable
    ├── omni.ja (browser code archive)
    ├── libxul.so (rendering engine)
    └── [other browser files]

obj-firefox/dist/firefox/ (BROWSER_DIST_PATH)
├── [copied from extracted directory]
└── [ready to execute]
```

### File System After Profile Generation
```
/home/runner/work/noraneko-runtime/noraneko-runtime/ (workspace root)
├── default_12345_random_67890.profraw (example, multiple files)
├── default_12346_random_67891.profraw
├── merged.profdata (merged profile data) ← UPLOADED
├── en-US.log (JAR access log) ← UPLOADED
└── [source code and scripts remain]
```

### What Gets Uploaded
```
Artifact: "noraneko-linux-x86_64-profile-generate-output"
├── merged.profdata (5-50 MB, binary LLVM profile data)
└── en-US.log (1-5 MB, text file with JAR access patterns)

Retention: 7 days (configurable in workflow)
```

## Hidden Dependencies

### Why Ruby Scripts Are Used

**Locate and install browser** (Step 14):
```ruby
# Ruby has better file searching and handling than bash
binary_names = ['noraneko', 'noraneko-bin', 'firefox', 'firefox-bin']

# Searches recursively for any of these binary names
Dir.glob('**/*').each do |path|
  if File.file?(path) && binary_names.any? { |name| File.basename(path) == name }
    browser_dir = File.dirname(path)
    break
  end
end

FileUtils.cp_r("#{browser_dir}/.", browser_dist_path)
```

**Why not bash**:
- More robust file searching
- Better error handling
- Simpler recursive directory operations
- Handles edge cases (spaces in paths, symlinks, etc.)

### Why llvm-profdata Wrapper Script Exists

**Problem**: Different architectures need different binaries
- x86_64 → llvm-profdata-x86_64
- aarch64 → llvm-profdata-arm64

**Solution**: Wrapper script auto-detects architecture
```bash
#!/bin/sh
PROFDATA_NAME="llvm-profdata-x86_64"
if [ "$(uname -m)" = "aarch64" ]; then
  PROFDATA_NAME="llvm-profdata-arm64"
fi
exec "$SCRIPT_DIR/../$PROFDATA_NAME" "$@"
```

**Why this matters**:
- Same script works on both architectures
- Stage 3 build references generic `llvm-profdata` command
- Wrapper redirects to correct binary automatically

### System Dependencies Explained

**Critical for running Firefox headlessly**:
```yaml
libgtk-3-0          # GTK3 for UI rendering
libdbus-glib-1-2    # IPC for browser components
libxt6, libx11-xcb1 # X11 libraries for windowing
libasound2, libpulse0 # Audio support (even headless)
libgl1, libgbm1     # OpenGL/graphics
xvfb                # Virtual X server
fonts-liberation    # Text rendering
```

**Why audio libs in headless mode**:
- Firefox initializes audio subsystem even without output
- Missing audio libs cause startup failures
- Not actually used, but must be present

### Container Platform Selection

```yaml
container:
  image: debian:bookworm-slim
  options: --platform ${{ inputs.target-arch == 'aarch64' && 'linux/arm64' || 'linux/amd64' }}
```

**For x86_64**:
- Runs on ubuntu-latest runner (x86_64)
- Container: linux/amd64 (native)
- No emulation needed

**For aarch64**:
- Runs on macos-latest runner (x86_64 or ARM64)
- Container: linux/arm64 (may require QEMU emulation)
- Docker handles emulation transparently

**Why Debian Bookworm**:
- Stable, long-term support
- Has LLVM 19 in repositories
- Minimal image size (300MB vs 1GB+ for Ubuntu)

## Architecture Variations

### x86_64 vs aarch64 Execution

**x86_64 path**:
```
ubuntu-latest runner (x86_64)
  → Docker container (linux/amd64)
    → Native execution (no emulation)
      → Profile generation completes in ~20 minutes
```

**aarch64 path**:
```
macos-latest runner (Apple Silicon or Intel)
  → Docker Desktop for Mac
    → Docker container (linux/arm64)
      → QEMU emulation if on Intel, native if Apple Silicon
        → Profile generation completes in ~30-40 minutes
```

**Performance difference**:
- x86_64: Fast (native)
- aarch64 on Apple Silicon: Fast (native ARM64)
- aarch64 on Intel Mac: Slow (QEMU emulation overhead)

### Why Not Native aarch64 Runners

**GitHub doesn't provide**:
- Native Linux aarch64 runners
- Only macOS ARM64 runners (different OS)

**Workaround**:
- Use macOS runner + Docker + Linux container
- Provides Linux environment for aarch64 build/test

## Process Logic

### Browser Binary Discovery Strategy

**Fallback hierarchy** (Locate and install browser step):
1. Search for binary by name: `noraneko`, `noraneko-bin`, `firefox`, `firefox-bin`
2. If not found, search for directory: contains "noraneko" or "firefox"
3. If still not found, fail with error

**Why fallback needed**:
- Different build configurations create different binary names
- Upstream Firefox may name it "firefox"
- Noraneko build may name it "noraneko"
- Debug builds may add "-bin" suffix

### Profile Generation Test Suite

**What profileserver.py does**:
1. **Initialize browser profile** (first run):
   ```javascript
   data:text/html,<script>Quitter.quit()</script>
   ```
   - Creates profile directory
   - Initializes preferences
   - Quits immediately (setup only)

2. **Run performance tests** (second run):
   ```
   http://localhost:8888/index.html
   ```
   - Serves from `build/pgo/index.html` in source tree
   - Includes Speedometer 3.0 benchmark
   - Tests:
     - Page rendering
     - JavaScript execution
     - DOM manipulation
     - CSS styling
     - Async operations
   - Runs for ~10-15 minutes

3. **Collect profile data**:
   - Browser writes `default_*_random_*.profraw` files
   - Each file = profile data from one browser process
   - Multiple processes (main, content, GPU) = multiple files

4. **Merge profiles**:
   ```bash
   llvm-profdata merge -o merged.profdata *.profraw
   ```
   - Combines all .profraw files
   - Resolves conflicts (same function profiled multiple times)
   - Outputs single unified profile

### Xvfb Usage Pattern

```bash
# Start Xvfb in background
Xvfb :99 -screen 0 1024x768x24 &
echo "XVFB_PID=$!" >> $GITHUB_ENV
sleep 3  # Wait for startup

# ... profile generation ...

# Always stop Xvfb (even if profile generation fails)
kill $XVFB_PID 2>/dev/null || true
```

**Why sleep 3**:
- Xvfb takes 1-2 seconds to initialize
- Starting browser before Xvfb ready = connection error
- 3 seconds is conservative safety margin

**Why kill in separate step with if: always()**:
- Ensures cleanup even if profile generation fails
- Prevents orphaned Xvfb processes
- `|| true` prevents failure if already dead

### Profile Data Verification

```ruby
['merged.profdata', 'en-US.log'].each do |f|
  unless File.exist?(f)
    puts "ERROR: #{f} not found"
    exit 1
  end
end

if File.zero?('merged.profdata')
  puts "ERROR: merged.profdata is empty"
  exit 1
end
```

**Why verification needed**:
- Profile generation can "succeed" but produce no data
- Empty profdata causes Stage 3 build to fail mysteriously
- Better to fail fast with clear error message

**Common causes of empty profdata**:
- Browser crashed during profiling
- Insufficient permissions to write .profraw files
- Disk space exhausted during profile generation

## When Timing Is Critical

### Xvfb Startup Delay
```bash
sleep 3  # Critical timing requirement
```
- **Too short**: Browser fails to connect to display
- **Too long**: Wastes CI time
- **3 seconds**: Tested empirically as reliable

### Profile Generation Timeout
```yaml
MOZ_PGO_TIMEOUT_MULTIPLIER: 5
```
- **Default timeout**: ~2 minutes per test
- **With multiplier**: ~10 minutes per test
- **Why needed**: Instrumented browser is 50% slower
- **Total time**: ~15-20 minutes for full test suite

### uv Dependency Installation
```yaml
- name: Sync uv dependencies
  working-directory: .github/scripts/firefox-profileserver
  run: uv sync
```
- **Time**: 1-2 minutes (first run), seconds (cached)
- **What it installs**: mozbase libraries (mozrunner, mozprofile, etc.)
- **Why uv not pip**: 10-100x faster dependency resolution

## When Steps Can Be Skipped

### Optional Steps
**None** - All steps are required for successful profile generation

### Steps That May Fail Without Breaking Workflow

**Stop Xvfb**:
```yaml
if: always()
run: kill $XVFB_PID 2>/dev/null || true
```
- Runs even if previous steps failed
- Failure ignored (`|| true`)
- Purpose: Cleanup only, doesn't affect results

## Common Failure Points

### 1. Browser Binary Not Found
**Error**: "No browser binary found"
**Causes**:
- Artifact corrupted during download
- Wrong artifact name passed to workflow
- Unexpected directory structure in artifact
**Solution**: Check artifact contents, verify naming

### 2. Display Connection Failed
**Error**: "Gtk-WARNING **: cannot open display: :99"
**Causes**:
- Xvfb not started
- DISPLAY variable not set
- Insufficient sleep after Xvfb start
**Solution**: Increase sleep duration, verify Xvfb process

### 3. Empty Profile Data
**Error**: "ERROR: merged.profdata is empty"
**Causes**:
- Browser crashed during profiling
- Tests didn't generate enough profile data
- llvm-profdata failed to merge
**Solution**: Check browser logs, verify test execution

### 4. llvm-profdata Not Found
**Error**: "command not found: llvm-profdata"
**Causes**:
- LLVM 19 installation failed
- Wrapper script not created
- PATH not set correctly
**Solution**: Verify LLVM installation, check wrapper script

### 5. Missing System Libraries
**Error**: "error while loading shared libraries: libgtk-3.so.0"
**Causes**:
- System dependencies installation failed
- Container using wrong image
**Solution**: Verify apt install step completed, check container image

## Output Artifacts

### merged.profdata
**Format**: Binary LLVM profile data
**Size**: 5-50 MB (varies by test coverage)
**Contains**:
- Function execution counts
- Branch taken/not-taken statistics
- Value profiling data (for indirect calls)
**Used by**: Stage 3 build (--with-pgo-profile-path)

### en-US.log
**Format**: Text file, one line per JAR file accessed
**Size**: 1-5 MB
**Contains**:
```
chrome://browser/content/browser.js
chrome://global/content/commonDialog.js
resource://gre/modules/AppConstants.jsm
...
```
**Purpose**: Optimizes JAR file ordering for faster startup
**Used by**: Stage 3 build (--with-pgo-jarlog)

## Related Workflows

- **wrapper-build-linux.yml**: Calls this workflow (Stage 2 orchestration)
- **common-build.yml**: Stage 1 (creates instrumented browser), Stage 3 (uses profile data)
- **generate-pgo-profile-windows.yml**: Windows equivalent of this workflow
