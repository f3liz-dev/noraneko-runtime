#!/usr/bin/env python3
# SPDX-License-Identifier: MPL-2.0
"""Dagger CI/CD module for noraneko-runtime builds."""

import argparse
import asyncio
import os
import subprocess
import sys
import time
from pathlib import Path
from typing import TYPE_CHECKING, Any, Optional

if TYPE_CHECKING:
    import dagger

try:
    import anyio
    import dagger as dagger_module
except ImportError:
    # These will be imported when needed
    anyio = None
    dagger_module = None


# Connection retry and timeout constants
PODMAN_RETRY_BACKOFF_SECONDS = 2  # Base backoff seconds for Podman verification retries
DAGGER_RETRY_BACKOFF_SECONDS = 5  # Base backoff seconds for Dagger connection retries
CI_SESSION_TIMEOUT_SECONDS = 600  # Session timeout for Dagger in CI environments (10 minutes)

# Podman socket paths
ROOTFUL_PODMAN_SOCKET = "/run/podman/podman.sock"  # System-wide rootful Podman socket


class Config:
    """Build configuration."""

    def __init__(
        self,
        platform: str = "linux",
        arch: str = "x86_64",
        debug: bool = True,
        pgo: bool = False,
        pgo_mode: str = "",
        omnijar_compress: str = "deflate",
        output_dir: str = "./output",
    ):
        self.platform = platform
        self.arch = arch
        self.debug = debug
        self.pgo = pgo
        self.pgo_mode = pgo_mode
        self.omnijar_compress = omnijar_compress
        self.output_dir = output_dir


def verify_podman_responsive() -> bool:
    """Verify Podman is responsive by running a simple command.
    
    This ensures the Podman daemon is ready before attempting Dagger connection.
    Uses linear backoff: 2s, 4s, 6s, 8s between retries.
    
    Returns:
        True if Podman is responsive, False otherwise.
    """
    print("Verifying Podman is responsive...")
    
    max_retries = 5
    for i in range(max_retries):
        try:
            result = subprocess.run(
                ["podman", "info"],
                capture_output=True,
                timeout=30,
            )
            if result.returncode == 0:
                print("Podman is responsive.")
                return True
        except (subprocess.TimeoutExpired, FileNotFoundError):
            pass
        
        if i < max_retries - 1:
            wait_time = (i + 1) * PODMAN_RETRY_BACKOFF_SECONDS
            print(f"Podman not ready yet, waiting {wait_time}s before retry {i+2}/{max_retries}...")
            time.sleep(wait_time)
    
    print(f"ERROR: Podman is not responsive after {max_retries} retries", file=sys.stderr)
    return False


def get_podman_socket_path() -> str:
    """Get the appropriate Podman socket path.
    
    For Dagger, we prioritize rootful Podman socket as Dagger requires
    rootful container execution for proper operation.
    
    Returns:
        The Podman socket path as a URI (e.g., "unix:///run/podman/podman.sock").
    """
    # Check for rootful Podman socket first (required for Dagger)
    if Path(ROOTFUL_PODMAN_SOCKET).exists():
        return f"unix://{ROOTFUL_PODMAN_SOCKET}"
    
    # Fallback to rootless Podman socket if rootful is not available
    xdg_runtime_dir = os.getenv("XDG_RUNTIME_DIR")
    if xdg_runtime_dir:
        rootless_socket = Path(xdg_runtime_dir) / "podman" / "podman.sock"
        if rootless_socket.exists():
            return f"unix://{rootless_socket}"
    
    # Check for rootless socket using UID
    uid = os.getuid()
    rootless_socket = Path(f"/run/user/{uid}/podman/podman.sock")
    if rootless_socket.exists():
        return f"unix://{rootless_socket}"
    
    # Default to rootful path (will be created when socket is started)
    return f"unix://{ROOTFUL_PODMAN_SOCKET}"


def prepare_host() -> int:
    """Prepare a GitHub Actions host by allocating swap and freeing disk space.
    
    Returns:
        Exit code (0 for success, non-zero for failure).
    """
    print("Preparing GitHub Actions host...")
    
    script = """
        echo "Before:"
        free -h
        df -h

        # Allocate 30GB swap
        sudo swapoff /mnt/swapfile 2>/dev/null || true
        sudo rm -f /mnt/swapfile
        sudo fallocate -l 30G /mnt/swapfile
        sudo chmod 600 /mnt/swapfile
        sudo mkswap /mnt/swapfile
        sudo swapon /mnt/swapfile

        # APT cleanup
        sudo apt autoremove -y -qq
        sudo apt clean

        # Install and setup Podman
        sudo apt install -y podman || true

        # Configure Podman socket permissions BEFORE starting the service
        # Create a systemd drop-in to override socket permissions for non-root access
        # This allows the current user to interact with rootful Podman without sudo
        # Security Note: Using 0666 for socket and 0755 for directory is acceptable
        # in GitHub Actions CI environment which is:
        # - Single-user (only the runner user)
        # - Ephemeral (destroyed after each run)
        # - Isolated (no other users or services)
        # For production environments, use group-based access instead
        sudo mkdir -p /etc/systemd/system/podman.socket.d
        sudo tee /etc/systemd/system/podman.socket.d/override.conf > /dev/null <<EOF
[Socket]
SocketMode=0666
DirectoryMode=0755
EOF

        # Reload systemd configuration to pick up the drop-in
        sudo systemctl daemon-reload

        # Enable and start Podman socket in rootful mode (required for Dagger)
        # Dagger SDK requires a Docker-compatible API, which Podman provides via socket
        # The --now flag enables and starts the service
        sudo systemctl enable --now podman.socket 2>/dev/null || true

        # Wait for socket to be ready
        sleep 3

        # Ensure the socket directory is accessible to non-root users
        # This is necessary because systemd creates the directory with restrictive permissions
        sudo chmod 755 /run/podman 2>/dev/null || true

        # Verify Podman is working and accessible
        podman info > /dev/null 2>&1 || echo "Warning: Podman might not be fully configured"

        # Verify socket is accessible
        if [ -e /run/podman/podman.sock ]; then
            echo "Podman socket is ready at /run/podman/podman.sock"
            ls -la /run/podman/podman.sock
        fi

        # Remove container images and containers to free space
        podman system prune -af --volumes 2>/dev/null || true

        # Free disk space - remove large pre-installed packages
        mkdir -p /tmp/empty
        for dir in ./.git /home/linuxbrew /usr/share/dotnet /usr/local/lib/android \\
            /usr/local/graalvm /usr/local/share/powershell /usr/local/share/chromium \\
            /opt/ghc /usr/local/.ghcup /usr/local/share/boost /etc/apache2 /etc/nginx \\
            /usr/local/share/chrome_driver /usr/local/share/edge_driver \\
            /usr/local/share/gecko_driver /usr/share/java /usr/share/miniconda \\
            /usr/local/share/vcpkg /usr/share/swift \\
            /usr/share/kotlinc /usr/share/sbt /opt/microsoft/powershell \\
            /imagegeneration; do
            if [ -d "$dir" ]; then
                echo "Removing: $dir"
                sudo rsync -a --delete /tmp/empty/ "$dir/" 2>/dev/null || true
                sudo rmdir "$dir" 2>/dev/null || true
            fi
        done
        # Clean up hostedtoolcache except for Python (needed for build)
        if [ -d "/opt/hostedtoolcache" ]; then
            for subdir in /opt/hostedtoolcache/*; do
                subdir_name="$(basename "$subdir")"
                if [ -d "$subdir" ] && [ "$subdir_name" != "Python" ] && [ "$subdir_name" != "python" ]; then
                    echo "Removing: $subdir"
                    sudo rsync -a --delete /tmp/empty/ "$subdir/" 2>/dev/null || true
                    sudo rmdir "$subdir" 2>/dev/null || true
                fi
            done
        fi
        # Clean up directories with version suffixes using find
        for dir in $(find /usr/share -maxdepth 1 -type d \\( -name 'gradle-*' -o -name 'julia-*' -o -name 'az_*' \\) 2>/dev/null); do
            echo "Removing: $dir"
            sudo rsync -a --delete /tmp/empty/ "$dir/" 2>/dev/null || true
            sudo rmdir "$dir" 2>/dev/null || true
        done
        rmdir /tmp/empty 2>/dev/null || true

        echo
        echo "After:"
        free -h
        df -h
    """
    
    result = subprocess.run(["bash", "-c", script])
    return result.returncode


async def connect_dagger_with_retry(config: Optional[Any] = None) -> Any:
    """Attempt to connect to Dagger with retry logic.
    
    This handles transient connection issues common in CI environments.
    Uses linear backoff: 0s, 5s, 10s between retries.
    
    Args:
        config: Optional Dagger configuration.
    
    Returns:
        Connected Dagger client.
    
    Raises:
        Exception: If connection fails after all retries.
    """
    if dagger_module is None:
        raise ImportError("dagger-io package is required for build command")
    
    max_retries = 3
    last_err = None
    
    for i in range(max_retries):
        if i > 0:
            wait_time = i * DAGGER_RETRY_BACKOFF_SECONDS
            print(f"Retrying Dagger connection in {wait_time}s (attempt {i+1}/{max_retries})...")
            await anyio.sleep(wait_time)
        
        print("Establishing connection to Dagger Engine...")
        
        try:
            client = dagger_module.connect(config)
            print("Successfully connected to Dagger Engine.")
            return client
        except Exception as err:
            last_err = err
            print(f"Failed to connect to Dagger: {err}")
    
    raise Exception(f"Failed to connect to Dagger after {max_retries} attempts: {last_err}")


async def build(cfg: Config) -> int:
    """Build the browser using Dagger and Podman.
    
    Args:
        cfg: Build configuration.
    
    Returns:
        Exit code (0 for success, non-zero for failure).
    """
    if dagger_module is None:
        print("ERROR: dagger-io package is required for build command", file=sys.stderr)
        print("Install with: pip install -r requirements.txt", file=sys.stderr)
        return 1
    
    # Verify Podman is responsive before attempting Dagger connection
    if not verify_podman_responsive():
        return 1
    
    # Set DOCKER_HOST to use rootful Podman socket for Dagger
    # Dagger SDK uses DOCKER_HOST to connect to the container runtime
    # This works with both Docker and Podman (Podman is Docker-compatible)
    podman_socket = get_podman_socket_path()
    print(f"Using Podman socket: {podman_socket}")
    os.environ["DOCKER_HOST"] = podman_socket
    
    # Also set CONTAINER_HOST for Podman-specific tools
    os.environ["CONTAINER_HOST"] = podman_socket
    
    # Disable Dagger Cloud features to avoid connection delays
    # This prevents timeouts related to telemetry and cloud service connections
    os.environ["DAGGER_CLOUD_TOKEN"] = ""
    
    # Set a more generous session timeout
    # This helps in CI environments where container startup can be slow
    os.environ["DAGGER_SESSION_TIMEOUT"] = str(CI_SESSION_TIMEOUT_SECONDS)
    
    # Configure Dagger to log to stderr
    config = dagger_module.Config(log_output=sys.stderr)
    
    try:
        # Connect to Dagger with retry logic
        async with await connect_dagger_with_retry(config) as client:
            # Base container with dependencies using Debian 12 slim (smaller official Debian image)
            c = (
                client.container()
                .from_("debian:12-slim")
                .with_env_variable("DEBIAN_FRONTEND", "noninteractive")
                .with_exec(["apt-get", "update"])
                .with_exec(["apt-get", "install", "-y", "wget", "gnupg", "ca-certificates"])
                .with_exec(["sh", "-c", "wget -qO- https://apt.llvm.org/llvm-snapshot.gpg.key | gpg --dearmor -o /etc/apt/trusted.gpg.d/llvm.gpg"])
                .with_exec(["sh", "-c", "echo 'deb http://apt.llvm.org/bookworm/ llvm-toolchain-bookworm-19 main' >> /etc/apt/sources.list"])
                .with_exec(["apt-get", "update"])
                .with_exec([
                    "apt-get", "install", "-y",
                    "curl", "git", "python3", "python3-pip", "python3-venv",
                    "build-essential", "autoconf2.13", "yasm", "libgtk-3-dev",
                    "libxtst6", "libxrandr2", "libasound2-dev",
                    "libpango1.0-dev", "libatk1.0-dev", "libcairo-gobject2",
                    "libgdk-pixbuf2.0-dev", "libdbus-glib-1-dev", "xvfb", "mesa-utils",
                    "msitools", "llvm-19", "clang-19", "gcc-aarch64-linux-gnu", "g++-aarch64-linux-gnu",
                ])
            )
            
            # Setup Rust
            rust_targets = {
                "x86_64": "x86_64-unknown-linux-gnu",
                "aarch64": "aarch64-unknown-linux-gnu",
            }
            rust_target = rust_targets.get(cfg.arch, "x86_64-unknown-linux-gnu")
            if cfg.platform == "windows":
                rust_target = "x86_64-pc-windows-msvc"
            
            c = (
                c.with_exec(["sh", "-c", "curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y --default-toolchain 1.86.0"])
                .with_env_variable("PATH", "/root/.cargo/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin")
                .with_env_variable("CARGO_INCREMENTAL", "0")
                .with_exec(["/root/.cargo/bin/rustup", "target", "add", rust_target])
            )
            
            # Setup source and mozconfig
            source = client.host().directory(
                "../..",
                exclude=[".git", ".github/ci/", "obj-*", "*.log"],
            )
            
            mozconfig_path = f".github/workflows/mozconfigs/{cfg.platform}-{cfg.arch}.mozconfig"
            if cfg.platform == "windows":
                mozconfig_path = ".github/workflows/mozconfigs/windows-x86_64.mozconfig"
            
            additions = []
            additions.append("ac_add_options --with-branding=browser/branding/noraneko-unofficial")
            additions.append("ac_add_options --enable-chrome-format=flat")
            additions.append("ac_add_options --enable-update-channel=alpha")
            if cfg.debug:
                additions.append("ac_add_options --enable-debug")
            if cfg.pgo and cfg.pgo_mode == "generate":
                additions.append("ac_add_options --enable-profile-generate=cross")
            elif cfg.pgo and cfg.pgo_mode == "use":
                additions.append("export MOZ_LTO=cross")
                additions.append("ac_add_options --enable-profile-use=cross")
                additions.append("ac_add_options --with-pgo-profile-path=/artifacts/merged.profdata")
                additions.append("ac_add_options --with-pgo-jarlog=/artifacts/en-US.log")
            
            additions_str = "\n".join(additions)
            
            c = (
                c.with_directory("/workspace", source)
                .with_workdir("/workspace")
                .with_exec(["cp", mozconfig_path, "mozconfig"])
                .with_exec(["sh", "-c", f"echo '{additions_str}' >> mozconfig"])
                .with_exec(["sh", "-c", "cp -r .github/assets/branding/* browser/branding/"])
            )
            
            # Apply patches
            c = c.with_exec(["sh", "-c", "for p in .github/patches/upstream/*.patch; do [ -e \"$p\" ] && git apply \"$p\" || true; done"])
            
            # Bootstrap and build
            c = c.with_exec(["./mach", "--no-interactive", "bootstrap", "--application-choice", "browser"])
            
            jobs = "$(( $(nproc) * 3 / 4 ))"
            if cfg.platform == "linux":
                c = (
                    c.with_env_variable("LIBGL_ALWAYS_SOFTWARE", "1")
                    .with_exec(["sh", "-c", "xvfb-run -a -s '-screen 0 1024x768x24' ./mach configure"])
                    .with_exec(["sh", "-c", f"xvfb-run -a -s '-screen 0 1024x768x24' nice -n 10 ./mach build --jobs={jobs}"])
                    .with_exec(["sh", "-c", f"xvfb-run -a -s '-screen 0 1024x768x24' ./mach package --compress='{cfg.omnijar_compress}'"])
                )
            else:
                c = (
                    c.with_exec(["./mach", "configure"])
                    .with_exec(["sh", "-c", f"nice -n 10 ./mach build --jobs={jobs}"])
                    .with_exec(["./mach", "package", f"--compress={cfg.omnijar_compress}"])
                )
            
            # Package artifacts
            obj_dirs = {
                "linux-x86_64": "obj-x86_64-pc-linux-gnu",
                "linux-aarch64": "obj-aarch64-unknown-linux-gnu",
                "windows-x86_64": "obj-x86_64-pc-windows-msvc",
            }
            obj_dir = obj_dirs.get(f"{cfg.platform}-{cfg.arch}", "obj-x86_64-pc-linux-gnu")
            
            ext = "tar.xz" if cfg.platform == "linux" else "zip"
            artifact = f"noraneko-{cfg.platform}-{cfg.arch}-moz-artifact.{ext}"
            
            c = c.with_exec(["mkdir", "-p", "/output"])
            if cfg.platform == "windows":
                c = c.with_exec(["sh", "-c", f"mv {obj_dir}/dist/noraneko-*win64.zip /output/{artifact}"])
            else:
                c = c.with_exec(["sh", "-c", f"mv {obj_dir}/dist/noraneko-*.tar.xz /output/{artifact}"])
            c = c.with_exec(["sh", "-c", f"cp {obj_dir}/dist/bin/application.ini /output/ || true"])
            
            # Export
            output_path = Path(cfg.output_dir)
            output_path.mkdir(parents=True, exist_ok=True)
            await c.directory("/output").export(str(output_path))
            print(f"Build artifacts exported to {cfg.output_dir}")
            
            return 0
    
    except Exception as err:
        print(f"Build failed: {err}", file=sys.stderr)
        return 1


def main():
    """Main entry point."""
    parser = argparse.ArgumentParser(
        description="Dagger CI/CD module for noraneko-runtime builds",
        formatter_class=argparse.RawDescriptionHelpFormatter,
    )
    
    subparsers = parser.add_subparsers(dest="command", help="Command to run")
    
    # prepare-host command
    subparsers.add_parser("prepare-host", help="Prepare GitHub Actions host (swap, disk cleanup)")
    
    # build command
    build_parser = subparsers.add_parser("build", help="Build the browser")
    build_parser.add_argument("-platform", default="linux", choices=["linux", "windows"], help="Target platform")
    build_parser.add_argument("-arch", default="x86_64", choices=["x86_64", "aarch64"], help="Target architecture")
    build_parser.add_argument("-debug", type=bool, default=True, help="Enable debug build")
    build_parser.add_argument("-pgo", type=bool, default=False, help="Enable PGO")
    build_parser.add_argument("-pgo-mode", default="", choices=["", "generate", "use"], help="PGO mode")
    build_parser.add_argument("-omnijar-compress", default="deflate", choices=["deflate", "zstd", "lz4", "none"], help="Omni.ja compression")
    build_parser.add_argument("-output", default="./output", help="Output directory")
    
    args = parser.parse_args()
    
    if not args.command or args.command == "help":
        parser.print_help()
        return 0
    
    if args.command == "prepare-host":
        return prepare_host()
    elif args.command == "build":
        cfg = Config(
            platform=args.platform,
            arch=args.arch,
            debug=args.debug,
            pgo=args.pgo,
            pgo_mode=args.pgo_mode,
            omnijar_compress=args.omnijar_compress,
            output_dir=args.output,
        )
        return asyncio.run(build(cfg))
    else:
        print(f"Unknown command: {args.command}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
