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

This CI module uses Podman instead of Docker as the container runtime. Podman is configured to run in **rootful mode** as required by Dagger. The connection is made via the Podman socket at `/run/podman/podman.sock` using the standard `DOCKER_HOST` environment variable.

### Recent Fix: Podman Connection Issue

**Problem**: Dagger was failing with: `start engine: no driver for scheme "podman-container" found`

**Solution**: Switched from experimental `podman-container://` scheme to standard Docker-compatible socket connection. Dagger's Go SDK works seamlessly with Podman's Docker-compatible API.

### Connection Details
- Podman socket: `/run/podman/podman.sock`
- Environment variable: `DOCKER_HOST=unix:///run/podman/podman.sock`
- Mode: Rootful (required for Dagger operations)

## Dagger-for-GitHub Action

An example workflow (`EXAMPLE-dagger-for-github.yml`) demonstrates using the official `dagger/dagger-for-github@v8.2.0` action for simple Dagger operations. However, this CI module uses the Dagger Go SDK directly for better control over complex Firefox/Noraneko builds.

## Troubleshooting

### "no driver for scheme found" errors
- Ensure `DOCKER_HOST` points to a valid Unix socket
- Verify Podman socket: `sudo systemctl status podman.socket`
- Check permissions: `ls -la /run/podman/podman.sock`

### Connection timeouts
- Podman may need time to start: check `podman info`
- Increase `DAGGER_SESSION_TIMEOUT` if needed

### Build failures
- Ensure adequate disk space (see `prepare-host` cleanup)
- Verify swap is allocated: `free -h`

## References

- [Dagger Documentation](https://docs.dagger.io/)
- [Dagger Go SDK](https://docs.dagger.io/api/sdk/go)
- [dagger-for-github Action](https://github.com/dagger/dagger-for-github)
- [Podman Documentation](https://podman.io/)
