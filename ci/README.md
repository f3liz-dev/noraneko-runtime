# Noraneko Runtime Dagger CI/CD

This directory contains the Dagger-based CI/CD pipelines for building noraneko-runtime. The pipelines refactor the existing GitHub Actions workflows into reusable, testable Dagger modules.

## Overview

The Dagger module provides containerized build pipelines that can be run:
- Locally for development and testing
- In GitHub Actions for CI/CD
- In any environment with Docker/Dagger installed

## Quick Start

### Prerequisites

1. **Go 1.22+**: Required for running the Dagger module
2. **Docker**: Required by Dagger for container execution
3. **Dagger CLI** (optional): For advanced Dagger features

### Installation

```bash
# Install Dagger CLI (optional)
curl -fsSL https://dl.dagger.io/dagger/install.sh | sh
```

### Running Builds

```bash
cd ci

# Build for Linux x86_64 with debug
go run . build -platform=linux -arch=x86_64 -debug

# Build for Linux aarch64 without debug
go run . build -platform=linux -arch=aarch64 -debug=false

# Build with PGO profile generation
go run . build -platform=linux -arch=x86_64 -pgo -pgo-mode=generate

# Build with PGO profile usage (requires profile artifacts)
go run . build -platform=linux -arch=x86_64 -pgo -pgo-mode=use
```

## Build Options

| Option | Default | Description |
|--------|---------|-------------|
| `-platform` | `linux` | Target platform: `linux`, `windows` |
| `-arch` | `x86_64` | Target architecture: `x86_64`, `aarch64` |
| `-debug` | `true` | Enable debug build |
| `-pgo` | `false` | Enable Profile-Guided Optimization |
| `-pgo-mode` | `` | PGO mode: `generate` or `use` |
| `-omnijar-compress` | `deflate` | Compression algorithm: `deflate`, `zstd`, `lz4`, `none` |
| `-output` | `./output` | Output directory for artifacts |

## Architecture

### Module Structure

```
ci/
├── main.go          # Main Dagger module with pipeline definitions
├── go.mod           # Go module definition
├── go.sum           # Go dependencies lock file
└── README.md        # This file
```

### Pipeline Stages

1. **Base Container**: Ubuntu 22.04 with build dependencies
2. **Rust Setup**: Installs and configures Rust toolchain
3. **Noraneko Setup**: Configures mozconfig and branding
4. **Patch Application**: Applies upstream patches
5. **Bootstrap**: Runs Mozilla bootstrap process
6. **Build**: Compiles the browser
7. **Package**: Creates distributable artifacts

### PGO Workflow

Profile-Guided Optimization (PGO) uses a three-stage process:

1. **Stage 1 (Generate)**: Build with profiling instrumentation
2. **Stage 2 (Profile)**: Run the instrumented build to collect profiles
3. **Stage 3 (Use)**: Rebuild using collected profile data

## GitHub Actions Workflows

### dagger-build.yml
Single platform/architecture build with manual trigger.

### dagger-daily-build.yml
Full daily build workflow supporting:
- Linux x86_64 and aarch64 builds
- Optional PGO optimization
- Scheduled builds (every 3 days at 6:00 UTC)
- Manual dispatch with customizable options

## Development

### Testing Changes

```bash
cd ci

# Run go vet
go vet ./...

# Build without running
go build -o /dev/null .

# Test help output
go run . help
```

### Adding New Pipelines

1. Add new methods to the `CI` struct in `main.go`
2. Add CLI command handling in the `main()` function
3. Update the workflow files to call the new command

## Comparison with Original Workflows

| Feature | Original (YAML) | Dagger (Go) |
|---------|-----------------|-------------|
| Local testing | Limited | Full support |
| Type safety | None | Compile-time checks |
| Reusability | Workflow references | Go functions |
| Debugging | GitHub logs only | Local debugging |
| Portability | GitHub Actions only | Any container runtime |

## Troubleshooting

### Common Issues

1. **Docker not running**: Ensure Docker daemon is started
2. **Permission errors**: Run with appropriate user permissions
3. **OOM errors**: Increase Docker memory limit or use swap

### Logs

For verbose logging:
```bash
DAGGER_LOG_FORMAT=plain go run . build ...
```

## License

SPDX-License-Identifier: MPL-2.0
