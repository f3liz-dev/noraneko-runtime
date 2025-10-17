# Daily Build Workflow Documentation

**File**: `daily-build.yml`

## Purpose

Orchestrates automated daily builds of Noraneko browser for all supported platforms. This is the entry point for scheduled and manual builds.

## Triggers

1. **Scheduled**: Daily at 6:00 AM UTC (cron: `0 6 * * *`)
2. **Manual dispatch**: Can be triggered manually with optional parameters:
   - `debug`: Enable debug build (default: true)
   - `pgo`: Enable Profile-Guided Optimization (default: true)

## Dependencies Graph

```
daily-build.yml (Entry Point)
    │
    ├─→ windows-x86_64 → wrapper-build-windows.yml
    │                         └─→ (see wrapper-build-windows.yml docs)
    │
    ├─→ linux-x86_64 → wrapper-build-linux.yml
    │                      └─→ (see wrapper-build-linux.yml docs)
    │
    └─→ linux-aarch64 → wrapper-build-linux.yml (with arch: aarch64)
                            └─→ (see wrapper-build-linux.yml docs)
```

**Execution**: All three platform builds run in parallel (no dependencies between them)

## Data Flow Between Steps

### Input Parameters
```yaml
inputs:
  debug: boolean (default: true for schedule, user-defined for manual)
  pgo: boolean (default: true for manual, false for schedule)
```

### Parameter Transformation Logic

**For Scheduled Runs** (cron trigger):
- `debug` → always `true`
- `pgo` → always `false`
- Rationale: Debug builds are faster and suitable for daily testing; PGO adds 2-4 hours per platform

**For Manual Runs** (workflow_dispatch):
- `debug` → user's choice (default: true)
- `pgo` → user's choice (default: true)
- Rationale: Manual builds allow full control for release preparation

### Outputs
This workflow doesn't produce direct outputs but coordinates three sub-workflows that produce:
- Windows x86_64 browser package
- Linux x86_64 browser package  
- Linux aarch64 browser package

Each package includes:
- Browser archive (noraneko-{platform}-{arch}-moz-artifact.{zip|tar.xz})
- dist/host tools (for MAR updates)
- application.ini metadata

## State Changes

### What This Workflow Changes
This orchestration workflow doesn't change repository state directly. All state changes happen in the called workflows:
- Artifact uploads (browser packages)
- Cache updates (sccache compilation cache)

### Inherited Repository State
- Source code at the HEAD of the branch where workflow runs
- Existing patches in `.github/patches/upstream/`
- Branding assets in `.github/assets/branding/`

## Hidden Dependencies

### Run Order Requirements
1. All three platform builds start simultaneously (parallel execution)
2. Each platform build is independent and can succeed/fail without affecting others
3. No cross-platform dependencies or artifact sharing

### Environment Requirements
- **GitHub Actions runners**: ubuntu-latest, windows-latest
- **Docker**: Required for Linux aarch64 builds (macOS runner + Docker ARM64)
- **Secrets inheritance**: All called workflows inherit repository secrets via `secrets: inherit`

### Implicit Timing Constraints
- **Scheduled run**: Starts at 6:00 AM UTC daily
  - Chosen to avoid peak usage hours
  - Completes before business hours in most timezones
- **Total runtime**: 3-5 hours for debug builds, 6-10 hours with PGO
  - Parallel execution means total = longest platform build time
  - Windows typically slowest due to toolchain overhead

## Architecture Variations

### Platform-Specific Behaviors

**Windows (x86_64 only)**:
- Uses `wrapper-build-windows.yml`
- Native Windows build environment
- MSVC toolchain

**Linux x86_64**:
- Uses `wrapper-build-linux.yml` (default arch)
- Native x86_64 build
- GNU toolchain

**Linux aarch64**:
- Uses `wrapper-build-linux.yml` (with `arch: aarch64`)
- Cross-compilation setup
- Runs on macOS runner with Docker ARM64 container
- Requires QEMU emulation

### Architecture Implementation Details
- **Windows separate**: Completely different toolchain (MSVC vs GCC/Clang)
- **Linux unified**: Same toolchain, different targets
- **aarch64 on macOS**: GitHub doesn't provide native Linux ARM64 runners; macOS + Docker is the workaround

## Process Logic

### Debug vs Release Decision
```yaml
debug: ${{ github.event.inputs.debug == 'true' || github.event_name == 'schedule' }}
```
- **Scheduled builds**: Always debug (faster, suitable for daily testing)
- **Manual builds**: User controls (allows release preparation)

### PGO Decision
```yaml
pgo: ${{ github.event.inputs.pgo == 'true' && github.event_name != 'schedule' }}
```
- **Scheduled builds**: Never PGO (too slow for daily builds)
- **Manual builds**: User controls (opt-in for optimized builds)
- **Logic**: Only enabled if manually requested AND not a scheduled run

### Independent Platform Builds
- Three platform builds are independent
- No shared artifacts between platforms during build
- Each workflow is self-contained with its own:
  - Source checkout
  - Dependency installation
  - Build execution
  - Artifact upload

### Failure Handling
- If one platform build fails, others continue
- GitHub Actions shows individual job status
- No automatic retry (must manually re-run)
- Partial success is valid (e.g., Windows succeeds, Linux fails)

## Run Name Customization

```yaml
run-name: Daily Runtime Build${{ (inputs.debug || github.event_name == 'schedule') && ' (Debug)' || '' }}
```

**Displayed names**:
- Scheduled: "Daily Runtime Build (Debug)"
- Manual debug: "Daily Runtime Build (Debug)"
- Manual release: "Daily Runtime Build"

**Purpose**: Quickly identify build type in GitHub Actions UI

## When Timing Is Critical

### Cron Schedule Choice
- **6:00 AM UTC** chosen because:
  - Low GitHub Actions runner contention
  - Completes before European business hours
  - Asian timezone developers can check results after work
  - US timezone developers can check results in morning

### Parallel Execution Benefits
- All platforms build simultaneously
- Total time = slowest platform (not sum of all)
- Efficient use of GitHub Actions concurrent job limits

## When Steps Can Be Skipped

### This workflow cannot skip steps
All three platform builds are always triggered. However, called workflows have internal skip logic:
- PGO stages skip if `pgo: false`
- Some artifact cleanup steps skip based on platform

### Conditional Execution in Called Workflows
- `wrapper-build-linux.yml`: Chooses between normal build and PGO 3-stage build
- `wrapper-build-windows.yml`: Same conditional logic as Linux
- `common-build.yml`: Executes PGO steps only when `pgo_mode` is set

## Permissions

```yaml
permissions:
  contents: write
```

**Required permissions**: 
- Called workflows upload artifacts
- Artifact upload requires write permissions
- Inherited by all sub-workflows via `secrets: inherit`

## Monitoring & Debugging

### Success Indicators
- All three jobs show green checkmarks
- Artifacts uploaded for each platform
- No error messages in logs

### Common Failure Modes
1. **Out of disk space**: allocate-swap.sh failure
2. **Compilation errors**: Source code issues or patch conflicts
3. **Timeout**: Build exceeds 6-hour GitHub Actions limit
4. **PGO profile generation**: Instrumented browser crashes during profiling

### Debug Information Location
- Job logs: Click on individual job names
- Artifacts: Download from workflow run summary
- Error details: Expand failed steps in job logs

## Related Workflows

- **wrapper-build-windows.yml**: Windows build implementation
- **wrapper-build-linux.yml**: Linux build implementation
- **common-build.yml**: Shared build logic
- **generate-pgo-profile-*.yml**: PGO profile generation (when enabled)
