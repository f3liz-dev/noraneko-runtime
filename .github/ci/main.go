// SPDX-License-Identifier: MPL-2.0
// Dagger CI/CD module for noraneko-runtime builds.
package main

import (
	"context"
	"flag"
	"fmt"
	"os"
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
		fmt.Print(`Usage: go run . build [options]

Options:
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

	if err := build(context.Background(), cfg); err != nil {
		fmt.Fprintf(os.Stderr, "Error: %v\n", err)
		os.Exit(1)
	}
}

func build(ctx context.Context, cfg Config) error {
	client, err := dagger.Connect(ctx, dagger.WithLogOutput(os.Stderr))
	if err != nil {
		return err
	}
	defer client.Close()

	// Base container with dependencies
	c := client.Container().From("ubuntu:22.04").
		WithEnvVariable("DEBIAN_FRONTEND", "noninteractive").
		WithExec([]string{"apt-get", "update"}).
		WithExec([]string{"apt-get", "install", "-y",
			"curl", "wget", "git", "python3", "python3-pip", "python3-venv",
			"build-essential", "autoconf2.13", "yasm", "libgtk-3-dev",
			"libgconf-2-dev", "libxtst6", "libxrandr2", "libasound2-dev",
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
		WithEnvVariable("PATH", "/root/.cargo/bin:$PATH").
		WithEnvVariable("CARGO_INCREMENTAL", "0").
		WithExec([]string{"/root/.cargo/bin/rustup", "target", "add", rustTarget})

	// Setup source and mozconfig
	source := client.Host().Directory("..", dagger.HostDirectoryOpts{
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
		WithExec([]string{"cp", "-r", ".github/assets/branding/", "browser/branding/"})

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
