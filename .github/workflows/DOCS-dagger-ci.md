# Dagger CI/CD Documentation

## Overview

The Dagger-based CI/CD system provides an alternative to the traditional YAML-based GitHub Actions workflows. It offers:

- **Local testing**: Run builds on your machine before pushing
- **Type safety**: Compile-time checks for pipeline logic
- **Portability**: Same pipelines work in any container runtime
- **Debuggability**: Full Go debugging support

## Files

| File | Purpose |
|------|---------|
| `ci/main.go` | Main Dagger module with all pipeline logic |
| `ci/README.md` | Detailed usage documentation |
| `dagger-build.yml` | Single platform build workflow |
| `dagger-daily-build.yml` | Full daily build with PGO support |

## Comparison with YAML Workflows

### Original YAML Structure
```
daily-build.yml
  ├── wrapper-build-linux.yml
  │     └── common-build.yml
  │           ├── scripts/setup-rust.sh
  │           ├── scripts/setup-noraneko.sh
  │           └── scripts/build-and-package.sh
  └── wrapper-build-windows.yml
        └── common-build.yml
```

### Dagger Structure
```
ci/main.go
  ├── CI.baseContainer()      - Ubuntu with dependencies
  ├── CI.setupRust()          - Rust toolchain
  ├── CI.setupNoraneko()      - mozconfig + branding
  ├── CI.applyPatches()       - Upstream patches
  ├── CI.bootstrap()          - Mozilla bootstrap
  ├── CI.build()              - Compile + package
  └── CI.packageArtifact()    - Export artifacts
```

## Quick Start

```bash
# From repository root
cd ci

# Run a build
go run . build -platform=linux -arch=x86_64

# With options
go run . build \
  -platform=linux \
  -arch=aarch64 \
  -debug=false \
  -pgo=true \
  -pgo-mode=generate
```

## PGO Workflow

The Dagger pipelines support the same 3-stage PGO workflow:

1. **Stage 1**: `go run . build -pgo -pgo-mode=generate`
2. **Stage 2**: Profile collection (handled by workflow)
3. **Stage 3**: `go run . build -pgo -pgo-mode=use`

## Workflow Dispatch

### dagger-build.yml

Manual trigger for single builds:
- Platform: linux/windows
- Architecture: x86_64/aarch64  
- Debug: true/false
- PGO: true/false
- Compression: deflate/zstd/lz4/none

### dagger-daily-build.yml

Scheduled + manual trigger:
- Runs every 3 days at 6:00 UTC
- Builds Linux x86_64 and aarch64
- Optional PGO optimization
- Same options as manual build

## Migration from YAML

The existing YAML workflows remain functional. The Dagger workflows provide an alternative approach that can be used alongside or as a replacement.

### When to use YAML workflows
- Existing CI/CD that works
- Simple changes to build configuration
- Platform-specific features

### When to use Dagger workflows
- Local development and testing
- Complex build logic
- Debugging pipeline issues
- Consistent builds across environments

## Troubleshooting

### Docker Issues
```bash
# Ensure Docker is running
docker info

# Check Docker resources (macOS/Windows)
# Increase memory in Docker Desktop settings
```

### Build Failures
```bash
# Verbose logging
DAGGER_LOG_FORMAT=plain go run . build ...

# Check Go compilation
go build -o /dev/null .
go vet ./...
```

### Common Errors

| Error | Solution |
|-------|----------|
| Docker not found | Start Docker daemon |
| Permission denied | Check Docker socket permissions |
| OOM killed | Increase Docker memory or use swap |
| Dagger connect failed | Check Docker is running |

## License

SPDX-License-Identifier: MPL-2.0
