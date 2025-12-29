# Noraneko Runtime Dagger CI

Dagger-based CI/CD module for building noraneko-runtime using Podman as the container runtime.

## Usage

```bash
cd .github/ci

# Prepare GitHub Actions host (allocate swap, free disk space, setup Podman)
go run . prepare-host

# Build the browser
go run . build [options]
```

## Commands

| Command | Description |
|---------|-------------|
| `prepare-host` | Prepare GitHub Actions host (swap, disk cleanup, Podman setup) |
| `build` | Build the browser using Podman containers |

## Build Options

| Flag | Default | Description |
|------|---------|-------------|
| `-platform` | linux | Target: linux, windows |
| `-arch` | x86_64 | Architecture: x86_64, aarch64 |
| `-debug` | true | Enable debug build |
| `-pgo` | false | Enable PGO |
| `-pgo-mode` | - | generate or use |
| `-omnijar-compress` | deflate | deflate, zstd, lz4, none |
| `-output` | ./output | Output directory |

## Examples

```bash
# Prepare host before building (important for GitHub Actions)
# This installs and configures Podman
go run . prepare-host

# Linux x86_64 debug build
go run . build -platform=linux -arch=x86_64 -debug

# Linux aarch64 release build
go run . build -platform=linux -arch=aarch64 -debug=false

# PGO profile generation
go run . build -platform=linux -pgo -pgo-mode=generate
```

## Container Runtime

This CI module uses Podman instead of Docker as the container runtime. Dagger is configured to connect to the Podman socket at `unix:///run/podman/podman.sock` via the `_EXPERIMENTAL_DAGGER_RUNNER_HOST` environment variable.
