# Linux Build Robustness and Architecture Support

This document describes the robust Linux build system implemented for the Noraneko runtime, focusing on multi-architecture support and Profile-Guided Optimization (PGO) builds.

## Overview

The Linux build system has been redesigned to provide:

1. **Multi-Architecture Support**: Native builds for x86_64 and aarch64 (ARM64)
2. **Robust PGO Implementation**: Multi-stage PGO builds with profile collection on target architecture
3. **Build Isolation**: Separate stages for different build phases to improve reliability
4. **Cross-Compilation Support**: Ability to build for different architectures
5. **Enhanced Error Handling**: Better error reporting and recovery mechanisms

## Architecture Support

### Supported Architectures

- **x86_64**: Standard x86 64-bit architecture (Intel/AMD)
- **aarch64**: ARM 64-bit architecture (ARM64)

### Native vs Cross-Compilation

The build system automatically detects whether native compilation or cross-compilation is needed:

- **Native builds**: When host architecture matches target architecture
- **Cross-compilation**: When building for a different architecture than the host

### Runner Selection

The workflow automatically selects appropriate runners based on target architecture:

- **x86_64 builds**: `ubuntu-latest` (x86_64 runners)
- **aarch64 builds**: `ubuntu-22.04-arm` (ARM64 runners when available)

## PGO Build Process

### Overview

Profile-Guided Optimization (PGO) is implemented as a three-stage process:

1. **Stage 1 - Profile Generation Build**: Build the browser with profile instrumentation
2. **Stage 2 - Profile Collection**: Run the instrumented browser to collect profiles
3. **Stage 3 - Optimized Build**: Build the final optimized browser using collected profiles

### Stage Details

#### Stage 1: Profile Generation Build

```yaml
build-pgo-stage1:
  uses: ./.github/workflows/common-build.yml
  with:
    platform: linux
    arch: ${{ inputs.arch }}
    debug: ${{ inputs.debug }}
    pgo: true
    pgo_mode: 'generate'
```

This stage produces an instrumented binary that collects profile data during execution.

#### Stage 2: Profile Collection

```yaml
collect-profiles:
  needs: build-pgo-stage1
  uses: ./.github/workflows/generate_pgo_profile.yml
  with:
    browser-artifact-name: noraneko-linux-${{ inputs.arch }}-moz-artifact
    artifact-path: /home/runner/artifact
    runner: ${{ (inputs.arch == 'aarch64') && 'ubuntu-22.04-arm' || 'ubuntu-latest' }}
    target-arch: ${{ inputs.arch }}
    profile-mode: generate
```

This stage runs the instrumented browser through various workloads to collect profile data. The key improvement is that profile collection happens on the same architecture as the target.

#### Stage 3: Final Optimized Build

```yaml
build-pgo-final:
  needs: collect-profiles
  uses: ./.github/workflows/common-build.yml
  with:
    platform: linux
    arch: ${{ inputs.arch }}
    debug: ${{ inputs.debug }}
    pgo: true
    pgo_mode: 'use'
    pgo_artifact_name: noraneko-linux-${{ inputs.arch }}-profile-generate-output
```

This stage builds the final optimized binary using the collected profile data.

## Build Robustness Features

### Error Handling

1. **Timeout Protection**: Profile collection has a 10-minute timeout to prevent infinite hangs
2. **Graceful Failures**: Each stage can fail independently without affecting other builds
3. **Resource Cleanup**: Proper cleanup of temporary resources (Xvfb processes, etc.)

### Environment Isolation

1. **Separate Job Environments**: Each stage runs in a fresh environment
2. **Artifact-Based Communication**: Stages communicate through well-defined artifacts
3. **Architecture-Specific Runners**: Use appropriate runners for each architecture

### Validation and Verification

1. **Artifact Validation**: Verify artifacts are properly created and have expected structure
2. **Binary Verification**: Check that browser binaries are executable and have correct metadata
3. **Profile Data Validation**: Ensure profile data files are generated correctly

## Supporting Scripts

### bootstrap_mozilla.sh

Sets up the Mozilla build environment with architecture-specific configuration:

- Installs required system dependencies
- Configures cross-compilation toolchains when needed
- Sets up Rust targets for the target architecture
- Bootstraps the Mozilla build system

### build_artifact.sh

Handles artifact creation and packaging:

- Detects object directories based on platform/architecture
- Packages build outputs with consistent naming
- Validates artifact integrity
- Generates metadata for build tracking

### generate_pgo_profile.yml

Advanced PGO profile collection workflow:

- Supports both Linux and Windows (future expansion)
- Architecture-aware binary detection
- Robust error handling with proper cleanup
- Headless browser execution for CI environments

## Workflow Usage

### Manual Dispatch

```yaml
workflow_dispatch:
  inputs:
    debug:
      type: boolean
      required: true
    pgo:
      description: 'Enable Profile-Guided Optimization (PGO)'
      type: boolean
      default: false
      required: true
    arch:
      description: 'Target architecture'
      type: choice
      options:
        - x86_64
        - aarch64
      default: x86_64
      required: true
```

### Workflow Call

```yaml
workflow_call:
  inputs:
    debug:
      type: boolean
      required: true
    pgo:
      type: boolean
      default: false
      required: true
    arch:
      type: string
      default: x86_64
      required: false
```

## Benefits

### Performance Improvements

1. **Native PGO**: Profile collection on target architecture provides better optimization data
2. **Architecture-Specific Optimization**: Builds are optimized for their target platform
3. **Reduced Build Times**: Parallel execution of independent stages

### Reliability Improvements

1. **Isolated Stages**: Failures in one stage don't affect others
2. **Better Error Reporting**: Detailed logging and error context
3. **Automatic Cleanup**: Proper resource management prevents build environment pollution

### Maintainability

1. **Modular Design**: Each component has a specific responsibility
2. **Reusable Components**: Scripts and workflows can be reused across different contexts
3. **Clear Documentation**: Well-documented processes and configurations

## Future Enhancements

1. **Additional Architectures**: Support for more architectures (e.g., RISC-V)
2. **Build Caching**: Implement intelligent caching to reduce build times
3. **Parallel PGO**: Run multiple profile collection workloads in parallel
4. **Dynamic Runner Selection**: Automatically select the best available runners
5. **Build Analytics**: Collect and analyze build performance metrics