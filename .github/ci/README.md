# Noraneko Runtime Dagger CI

Dagger-based CI/CD module for building noraneko-runtime using Podman as the container runtime.

## Requirements

- Python 3.10 or later
- Podman (or Docker)
- Dagger Python SDK (installed automatically via requirements.txt)

## Usage

```bash
cd .github/ci

# Install dependencies
pip install -r requirements.txt

# Prepare GitHub Actions host (allocate swap, free disk space, setup Podman)
python main.py prepare-host

# Build the browser
python main.py build [options]
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
python main.py prepare-host

# Linux x86_64 debug build
python main.py build -platform=linux -arch=x86_64 -debug

# Linux aarch64 release build
python main.py build -platform=linux -arch=aarch64 -debug=false

# PGO profile generation
python main.py build -platform=linux -pgo -pgo-mode=generate
```

## Container Runtime

This CI module uses Podman instead of Docker as the container runtime. Podman is configured to run in **rootful mode** as required by Dagger. The connection is made via the Podman socket at `/run/podman/podman.sock` using the standard `DOCKER_HOST` environment variable.

### Podman Integration in GitHub Actions

The Dagger Python SDK connects to Podman using the Docker-compatible API. There is no special `podman-container://` scheme - instead, we use the standard Docker socket protocol with Podman:

1. **Socket Configuration**: Podman provides a Docker-compatible socket at `/run/podman/podman.sock`
2. **Environment Variable**: Set `DOCKER_HOST=unix:///run/podman/podman.sock`
3. **Dagger Connection**: The Dagger SDK automatically uses the `DOCKER_HOST` to connect to the container runtime

This approach works because:
- Podman implements the Docker API specification
- Dagger SDK is designed to work with any Docker-compatible runtime
- No special configuration or custom schemes are needed

### Container Runtime Usage

The Python code automatically:
1. Detects the Podman socket path (rootful or rootless)
2. Sets `DOCKER_HOST` environment variable
3. Sets `CONTAINER_HOST` for Podman-specific tools
4. Connects Dagger to Podman transparently

Example from the code:
```python
podman_socket = get_podman_socket_path()  # Returns "unix:///run/podman/podman.sock"
os.environ["DOCKER_HOST"] = podman_socket
os.environ["CONTAINER_HOST"] = podman_socket
# Dagger SDK now uses Podman automatically
```

### Recent Fixes

#### Podman Socket Permission Issue (Latest)

**Problem**: Dagger was failing with: `permission denied while trying to connect to the Docker daemon socket at unix:///run/podman/podman.sock`

**Root Cause**: The socket was being created by systemd with default permissions (0660, owned by root:root), and the directory `/run/podman/` was created with mode 0700 (accessible only by root). Attempting to chmod the socket file after creation didn't work reliably due to systemd socket management and SELinux/AppArmor restrictions, and even with correct socket permissions, the directory permissions prevented non-root access.

**Solution**: Use a systemd drop-in file to configure both socket and directory permissions BEFORE they are created. The `prepare-host` command now creates `/etc/systemd/system/podman.socket.d/override.conf` to set `SocketMode=0666` (world-readable/writable socket) and `DirectoryMode=0755` (world-readable directory with owner-only write). Additionally, after socket creation, we explicitly chmod the directory to 0755 to ensure it's accessible, as systemd may still create it with restrictive permissions in some cases.

**Security Note**: The 0666 socket permissions are acceptable in GitHub Actions CI because the environment is single-user, ephemeral, and isolated. For production environments, group-based access control would be more appropriate.

#### Podman Connection Scheme Issue

**Problem**: Dagger was failing with: `start engine: no driver for scheme "podman-container" found`

**Solution**: Switched from experimental `podman-container://` scheme to standard Docker-compatible socket connection. Dagger's Go SDK works seamlessly with Podman's Docker-compatible API.

### Connection Details
- Podman socket: `/run/podman/podman.sock`
- Environment variable: `DOCKER_HOST=unix:///run/podman/podman.sock`
- Mode: Rootful (required for Dagger operations)
- Socket permissions: 0666 (rw-rw-rw-) via systemd drop-in
- Directory permissions: 0755 (rwxr-xr-x) via systemd drop-in + fallback chmod
- Security: Permissive settings acceptable for ephemeral CI environments only

## Dagger-for-GitHub Action

An example workflow (`EXAMPLE-dagger-for-github.yml`) demonstrates using the official `dagger/dagger-for-github@v8.2.0` action for simple Dagger operations. However, this CI module uses the Dagger Go SDK directly for better control over complex Firefox/Noraneko builds.

## Troubleshooting

### "permission denied" errors on socket
- Ensure `prepare-host` was run to configure socket permissions
- The systemd drop-in should exist: `ls -la /etc/systemd/system/podman.socket.d/override.conf`
- Verify socket permissions: `ls -la /run/podman/podman.sock` (should show 0666 or srw-rw-rw-)
- Restart socket if needed: `sudo systemctl restart podman.socket`

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
