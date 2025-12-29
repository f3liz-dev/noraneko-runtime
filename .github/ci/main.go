// SPDX-License-Identifier: MPL-2.0
// Dagger CI/CD module for noraneko-runtime builds.
package main

import (
	"context"
	"flag"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"strings"

	"dagger.io/dagger"
)

type Platform string
type Arch string

const (
	Linux   Platform = "linux"
	Windows Platform = "windows"
	X86_64  Arch     = "x86_64"
	Aarch64 Arch     = "aarch64"
)

type Config struct {
	Platform, PGOMode, OmnijarCompress, OutputDir string
	Arch                                          Arch
	Debug, PGO                                    bool
}

func main() {
	if len(os.Args) < 2 || os.Args[1] == "help" || os.Args[1] == "-h" {
		fmt.Print(`Usage: go run . <command> [options]

Commands:
  build          Build the browser
  prepare-host   Prepare GitHub Actions host (swap, disk cleanup)

Build Options:
  -platform      linux|windows (default: linux)
  -arch          x86_64|aarch64 (default: x86_64)
  -debug         Enable debug (default: true)
  -pgo           Enable PGO (default: false)
  -pgo-mode      generate|use
  -omnijar-compress  deflate|zstd|lz4|none (default: deflate)
  -output        Output directory (default: ./output)
`)
		return
	}

	cmd := os.Args[1]
	var err error

	switch cmd {
	case "prepare-host":
		err = prepareHost()
	case "build":
		fs := flag.NewFlagSet("build", flag.ExitOnError)
		cfg := Config{Platform: "linux", OmnijarCompress: "deflate", OutputDir: "./output", Arch: X86_64, Debug: true}
		fs.StringVar(&cfg.Platform, "platform", "linux", "")
		arch := fs.String("arch", "x86_64", "")
		fs.BoolVar(&cfg.Debug, "debug", true, "")
		fs.BoolVar(&cfg.PGO, "pgo", false, "")
		fs.StringVar(&cfg.PGOMode, "pgo-mode", "", "")
		fs.StringVar(&cfg.OmnijarCompress, "omnijar-compress", "deflate", "")
		fs.StringVar(&cfg.OutputDir, "output", "./output", "")
		fs.Parse(os.Args[2:])
		cfg.Arch = Arch(*arch)
		err = build(context.Background(), cfg)
	default:
		fmt.Fprintf(os.Stderr, "Unknown command: %s\n", cmd)
		os.Exit(1)
	}

	if err != nil {
		fmt.Fprintf(os.Stderr, "Error: %v\n", err)
		os.Exit(1)
	}
}

// getPodmanSocketPath returns the appropriate Podman socket path.
// It checks for rootless Podman socket first ($XDG_RUNTIME_DIR/podman/podman.sock),
// then falls back to rootful Podman socket (/run/podman/podman.sock).
func getPodmanSocketPath() string {
	// Check for rootless Podman socket (most common in GitHub Actions)
	if xdgDir := os.Getenv("XDG_RUNTIME_DIR"); xdgDir != "" {
		rootlessSocket := filepath.Join(xdgDir, "podman", "podman.sock")
		if _, err := os.Stat(rootlessSocket); err == nil {
			return fmt.Sprintf("unix://%s", rootlessSocket)
		}
	}

	// Check for rootless socket using UID
	uid := os.Getuid()
	rootlessSocket := fmt.Sprintf("/run/user/%d/podman/podman.sock", uid)
	if _, err := os.Stat(rootlessSocket); err == nil {
		return fmt.Sprintf("unix://%s", rootlessSocket)
	}

	// Fallback to rootful Podman socket
	rootfulSocket := "/run/podman/podman.sock"
	if _, err := os.Stat(rootfulSocket); err == nil {
		return fmt.Sprintf("unix://%s", rootfulSocket)
	}

	// Default to rootless path (will be created when socket is started)
	if xdgDir := os.Getenv("XDG_RUNTIME_DIR"); xdgDir != "" {
		return fmt.Sprintf("unix://%s/podman/podman.sock", xdgDir)
	}
	return fmt.Sprintf("unix:///run/user/%d/podman/podman.sock", os.Getuid())
}

// prepareHost prepares a GitHub Actions host by allocating swap and freeing disk space.
func prepareHost() error {
	fmt.Println("Preparing GitHub Actions host...")

	// Run the allocate-swap.sh script
	script := `
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

		# Enable and start Podman socket (rootless for non-root user)
		# First try user socket (most common in GitHub Actions)
		systemctl --user enable --now podman.socket 2>/dev/null || true
		
		# If user socket didn't work, try system socket as fallback
		if ! systemctl --user is-active --quiet podman.socket 2>/dev/null; then
			sudo systemctl enable --now podman.socket 2>/dev/null || true
		fi

		# Wait for socket to be ready
		sleep 2

		# Verify Podman is working
		podman info > /dev/null 2>&1 || echo "Warning: Podman might not be fully configured"

		# Remove container images and containers to free space (use podman instead of docker)
		podman system prune -af --volumes 2>/dev/null || true

		# Free disk space - remove large pre-installed packages
		mkdir -p /tmp/empty
		for dir in ./.git /home/linuxbrew /usr/share/dotnet /usr/local/lib/android \
			/usr/local/graalvm /usr/local/share/powershell /usr/local/share/chromium \
			/opt/ghc /usr/local/.ghcup /usr/local/share/boost /etc/apache2 /etc/nginx \
			/usr/local/share/chrome_driver /usr/local/share/edge_driver \
			/usr/local/share/gecko_driver /usr/share/java /usr/share/miniconda \
			/usr/local/share/vcpkg /usr/share/swift \
			/usr/share/kotlinc /usr/share/sbt /opt/microsoft/powershell \
			/imagegeneration; do
			if [ -d "$dir" ]; then
				echo "Removing: $dir"
				sudo rsync -a --delete /tmp/empty/ "$dir/" 2>/dev/null || true
				sudo rmdir "$dir" 2>/dev/null || true
			fi
		done
		# Clean up hostedtoolcache except for Go (needed for build)
		if [ -d "/opt/hostedtoolcache" ]; then
			for subdir in /opt/hostedtoolcache/*; do
				if [ -d "$subdir" ] && [ "$(basename "$subdir")" != "go" ]; then
					echo "Removing: $subdir"
					sudo rsync -a --delete /tmp/empty/ "$subdir/" 2>/dev/null || true
					sudo rmdir "$subdir" 2>/dev/null || true
				fi
			done
		fi
		# Clean up directories with version suffixes using find
		for dir in $(find /usr/share -maxdepth 1 -type d \( -name 'gradle-*' -o -name 'julia-*' -o -name 'az_*' \) 2>/dev/null); do
			echo "Removing: $dir"
			sudo rsync -a --delete /tmp/empty/ "$dir/" 2>/dev/null || true
			sudo rmdir "$dir" 2>/dev/null || true
		done
		rmdir /tmp/empty 2>/dev/null || true

		echo
		echo "After:"
		free -h
		df -h
	`

	cmd := exec.Command("bash", "-c", script)
	cmd.Stdout = os.Stdout
	cmd.Stderr = os.Stderr
	return cmd.Run()
}

func build(ctx context.Context, cfg Config) error {
	// Detect and configure Dagger to use the correct Podman socket path
	podmanSocket := getPodmanSocketPath()
	fmt.Printf("Using Podman socket: %s\n", podmanSocket)
	os.Setenv("_EXPERIMENTAL_DAGGER_RUNNER_HOST", podmanSocket)

	client, err := dagger.Connect(ctx, dagger.WithLogOutput(os.Stderr))
	if err != nil {
		return err
	}
	defer client.Close()

	// Base container with dependencies using Debian 12 slim (smaller official Debian image)
	c := client.Container().From("debian:12-slim").
		WithEnvVariable("DEBIAN_FRONTEND", "noninteractive").
		WithExec([]string{"apt-get", "update"}).
		WithExec([]string{"apt-get", "install", "-y", "wget", "gnupg", "ca-certificates"}).
		WithExec([]string{"sh", "-c", "wget -qO- https://apt.llvm.org/llvm-snapshot.gpg.key | gpg --dearmor -o /etc/apt/trusted.gpg.d/llvm.gpg"}).
		WithExec([]string{"sh", "-c", "echo 'deb http://apt.llvm.org/bookworm/ llvm-toolchain-bookworm-19 main' >> /etc/apt/sources.list"}).
		WithExec([]string{"apt-get", "update"}).
		WithExec([]string{"apt-get", "install", "-y",
			"curl", "git", "python3", "python3-pip", "python3-venv",
			"build-essential", "autoconf2.13", "yasm", "libgtk-3-dev",
			"libxtst6", "libxrandr2", "libasound2-dev",
			"libpango1.0-dev", "libatk1.0-dev", "libcairo-gobject2",
			"libgdk-pixbuf2.0-dev", "libdbus-glib-1-dev", "xvfb", "mesa-utils",
			"msitools", "llvm-19", "clang-19", "gcc-aarch64-linux-gnu", "g++-aarch64-linux-gnu",
		})

	// Setup Rust
	rustTarget := map[Arch]string{X86_64: "x86_64-unknown-linux-gnu", Aarch64: "aarch64-unknown-linux-gnu"}[cfg.Arch]
	if cfg.Platform == "windows" {
		rustTarget = "x86_64-pc-windows-msvc"
	}
	c = c.WithExec([]string{"sh", "-c", "curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y --default-toolchain 1.86.0"}).
		WithEnvVariable("PATH", "/root/.cargo/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin").
		WithEnvVariable("CARGO_INCREMENTAL", "0").
		WithExec([]string{"/root/.cargo/bin/rustup", "target", "add", rustTarget})

	// Setup source and mozconfig
	source := client.Host().Directory("../..", dagger.HostDirectoryOpts{
		Exclude: []string{".git", ".github/ci/", "obj-*", "*.log"},
	})

	mozconfigPath := fmt.Sprintf(".github/workflows/mozconfigs/%s-%s.mozconfig", cfg.Platform, cfg.Arch)
	if cfg.Platform == "windows" {
		mozconfigPath = ".github/workflows/mozconfigs/windows-x86_64.mozconfig"
	}

	var additions strings.Builder
	additions.WriteString("ac_add_options --with-branding=browser/branding/noraneko-unofficial\n")
	additions.WriteString("ac_add_options --enable-chrome-format=flat\n")
	additions.WriteString("ac_add_options --enable-update-channel=alpha\n")
	if cfg.Debug {
		additions.WriteString("ac_add_options --enable-debug\n")
	}
	if cfg.PGO && cfg.PGOMode == "generate" {
		additions.WriteString("ac_add_options --enable-profile-generate=cross\n")
	} else if cfg.PGO && cfg.PGOMode == "use" {
		additions.WriteString("export MOZ_LTO=cross\nac_add_options --enable-profile-use=cross\n")
		additions.WriteString("ac_add_options --with-pgo-profile-path=/artifacts/merged.profdata\n")
		additions.WriteString("ac_add_options --with-pgo-jarlog=/artifacts/en-US.log\n")
	}

	c = c.WithDirectory("/workspace", source).WithWorkdir("/workspace").
		WithExec([]string{"cp", mozconfigPath, "mozconfig"}).
		WithExec([]string{"sh", "-c", fmt.Sprintf("echo '%s' >> mozconfig", additions.String())}).
		WithExec([]string{"sh", "-c", "cp -r .github/assets/branding/* browser/branding/"})

	// Apply patches
	c = c.WithExec([]string{"sh", "-c", `
		for p in .github/patches/upstream/*.patch; do [ -e "$p" ] && git apply "$p" || true; done
	`})

	// Bootstrap and build
	c = c.WithExec([]string{"./mach", "--no-interactive", "bootstrap", "--application-choice", "browser"})

	jobs := "$(( $(nproc) * 3 / 4 ))"
	if cfg.Platform == "linux" {
		c = c.WithEnvVariable("LIBGL_ALWAYS_SOFTWARE", "1").
			WithExec([]string{"sh", "-c", "xvfb-run -a -s '-screen 0 1024x768x24' ./mach configure"}).
			WithExec([]string{"sh", "-c", fmt.Sprintf("xvfb-run -a -s '-screen 0 1024x768x24' nice -n 10 ./mach build --jobs=%s", jobs)}).
			WithExec([]string{"sh", "-c", fmt.Sprintf("xvfb-run -a -s '-screen 0 1024x768x24' ./mach package --compress='%s'", cfg.OmnijarCompress)})
	} else {
		c = c.WithExec([]string{"./mach", "configure"}).
			WithExec([]string{"sh", "-c", fmt.Sprintf("nice -n 10 ./mach build --jobs=%s", jobs)}).
			WithExec([]string{"./mach", "package", fmt.Sprintf("--compress=%s", cfg.OmnijarCompress)})
	}

	// Package artifacts
	objDir := map[string]string{
		"linux-x86_64":   "obj-x86_64-pc-linux-gnu",
		"linux-aarch64":  "obj-aarch64-unknown-linux-gnu",
		"windows-x86_64": "obj-x86_64-pc-windows-msvc",
	}[fmt.Sprintf("%s-%s", cfg.Platform, cfg.Arch)]

	ext := "tar.xz"
	if cfg.Platform == "windows" {
		ext = "zip"
	}
	artifact := fmt.Sprintf("noraneko-%s-%s-moz-artifact.%s", cfg.Platform, cfg.Arch, ext)

	c = c.WithExec([]string{"mkdir", "-p", "/output"})
	if cfg.Platform == "windows" {
		c = c.WithExec([]string{"sh", "-c", fmt.Sprintf("mv %s/dist/noraneko-*win64.zip /output/%s", objDir, artifact)})
	} else {
		c = c.WithExec([]string{"sh", "-c", fmt.Sprintf("mv %s/dist/noraneko-*.tar.xz /output/%s", objDir, artifact)})
	}
	c = c.WithExec([]string{"sh", "-c", fmt.Sprintf("cp %s/dist/bin/application.ini /output/ || true", objDir)})

	// Export
	if err := os.MkdirAll(cfg.OutputDir, 0755); err != nil {
		return err
	}
	_, err = c.Directory("/output").Export(ctx, cfg.OutputDir)
	if err != nil {
		return err
	}
	fmt.Printf("Build artifacts exported to %s\n", cfg.OutputDir)
	return nil
}
