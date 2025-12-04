// SPDX-License-Identifier: MPL-2.0
// Package main provides Dagger-based CI/CD pipelines for noraneko-runtime.
//
// This module refactors the existing GitHub Actions workflows into Dagger pipelines
// for improved reproducibility, local testing, and cross-platform builds.
package main

import (
	"context"
	"flag"
	"fmt"
	"os"
	"strings"

	"dagger.io/dagger"
)

// Platform represents the target build platform.
type Platform string

const (
	PlatformLinux   Platform = "linux"
	PlatformWindows Platform = "windows"
	PlatformMac     Platform = "mac"
)

// Arch represents the target architecture.
type Arch string

const (
	ArchX86_64  Arch = "x86_64"
	ArchAarch64 Arch = "aarch64"
)

// BuildConfig holds all build configuration options.
type BuildConfig struct {
	Platform          Platform
	Arch              Arch
	Debug             bool
	PGO               bool
	PGOMode           string // "generate" or "use"
	PGOArtifactName   string
	MOZBuildDate      string
	OmnijarCompress   string
	CodeCoverage      bool
	SCCachePath       string
}

// DefaultBuildConfig returns default build configuration.
func DefaultBuildConfig() BuildConfig {
	return BuildConfig{
		Platform:        PlatformLinux,
		Arch:            ArchX86_64,
		Debug:           true,
		PGO:             false,
		OmnijarCompress: "deflate",
		CodeCoverage:    false,
	}
}

// CI provides Dagger pipelines for noraneko-runtime CI/CD.
type CI struct{}

// baseContainer creates the base Ubuntu container with common dependencies.
func (ci *CI) baseContainer(client *dagger.Client) *dagger.Container {
	return client.Container().
		From("ubuntu:22.04").
		WithEnvVariable("DEBIAN_FRONTEND", "noninteractive").
		WithExec([]string{"apt-get", "update"}).
		WithExec([]string{"apt-get", "install", "-y",
			"curl", "wget", "git", "python3", "python3-pip", "python3-venv",
			"build-essential", "autoconf2.13", "yasm",
			"libgtk-3-dev", "libgconf-2-dev", "libxtst6", "libxrandr2",
			"libasound2-dev", "libpango1.0-dev", "libatk1.0-dev",
			"libcairo-gobject2", "libgdk-pixbuf2.0-dev", "libdbus-glib-1-dev",
			"xvfb", "mesa-utils", "msitools", "llvm-19", "clang-19",
			"gcc-aarch64-linux-gnu", "g++-aarch64-linux-gnu",
		})
}

// setupRust configures the Rust toolchain for the build.
func (ci *CI) setupRust(container *dagger.Container, cfg BuildConfig) *dagger.Container {
	rustVersion := "1.86.0"

	container = container.
		WithExec([]string{"sh", "-c", "curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y --default-toolchain " + rustVersion}).
		WithEnvVariable("PATH", "/root/.cargo/bin:$PATH").
		WithEnvVariable("CARGO_INCREMENTAL", "0")

	// Add appropriate target based on platform and architecture
	switch cfg.Platform {
	case PlatformWindows:
		container = container.WithExec([]string{"/root/.cargo/bin/rustup", "target", "add", "x86_64-pc-windows-msvc"})
	case PlatformLinux:
		if cfg.Arch == ArchAarch64 {
			container = container.WithExec([]string{"/root/.cargo/bin/rustup", "target", "add", "aarch64-unknown-linux-gnu"})
		} else {
			container = container.WithExec([]string{"/root/.cargo/bin/rustup", "target", "add", "x86_64-unknown-linux-gnu"})
		}
	}

	return container
}

// getMozconfigPath returns the path to the appropriate mozconfig file.
func getMozconfigPath(cfg BuildConfig) string {
	switch cfg.Platform {
	case PlatformWindows:
		return ".github/workflows/mozconfigs/windows-x86_64.mozconfig"
	case PlatformLinux:
		if cfg.Arch == ArchAarch64 {
			return ".github/workflows/mozconfigs/linux-aarch64.mozconfig"
		}
		return ".github/workflows/mozconfigs/linux-x86_64.mozconfig"
	default:
		return ".github/workflows/mozconfigs/linux-x86_64.mozconfig"
	}
}

// setupNoraneko configures the noraneko build environment.
func (ci *CI) setupNoraneko(container *dagger.Container, source *dagger.Directory, cfg BuildConfig) *dagger.Container {
	mozconfigPath := getMozconfigPath(cfg)

	// Build mozconfig content dynamically
	var mozconfigAdditions strings.Builder

	// Branding and chrome format
	mozconfigAdditions.WriteString("ac_add_options --with-branding=browser/branding/noraneko-unofficial\n")
	mozconfigAdditions.WriteString("ac_add_options --enable-chrome-format=flat\n")

	// Debug settings
	if cfg.Debug {
		mozconfigAdditions.WriteString("ac_add_options --enable-debug\n")
	}

	// PGO settings
	if cfg.PGO {
		switch cfg.PGOMode {
		case "generate":
			mozconfigAdditions.WriteString("ac_add_options --enable-profile-generate=cross\n")
		case "use":
			mozconfigAdditions.WriteString("export MOZ_LTO=cross\n")
			mozconfigAdditions.WriteString("ac_add_options --enable-profile-use=cross\n")
			mozconfigAdditions.WriteString("ac_add_options --with-pgo-profile-path=/artifacts/merged.profdata\n")
			mozconfigAdditions.WriteString("ac_add_options --with-pgo-jarlog=/artifacts/en-US.log\n")
		}
	}

	// Update channel
	mozconfigAdditions.WriteString("ac_add_options --enable-update-channel=alpha\n")

	container = container.
		WithDirectory("/workspace", source).
		WithWorkdir("/workspace").
		// Copy base mozconfig
		WithExec([]string{"cp", mozconfigPath, "mozconfig"}).
		// Append additional configuration
		WithExec([]string{"sh", "-c", fmt.Sprintf("echo '%s' >> mozconfig", mozconfigAdditions.String())}).
		// Copy branding assets
		WithExec([]string{"cp", "-r", ".github/assets/branding/", "browser/branding/"})

	// Set MOZ_BUILD_DATE if provided
	if cfg.MOZBuildDate != "" {
		container = container.WithEnvVariable("MOZ_BUILD_DATE", cfg.MOZBuildDate)
	}

	return container
}

// applyPatches applies upstream patches to the source.
func (ci *CI) applyPatches(container *dagger.Container) *dagger.Container {
	return container.WithExec([]string{"sh", "-c", `
		PATCH_DIR=".github/patches/upstream"
		if [ -d "$PATCH_DIR" ]; then
			for patch in "$PATCH_DIR"/*.patch; do
				[ -e "$patch" ] || continue
				echo "Applying patch: $(basename "$patch")"
				git apply --verbose "$patch" || true
			done
		else
			echo "No patches to apply"
		fi
	`})
}

// bootstrap runs the Mozilla bootstrap process.
func (ci *CI) bootstrap(container *dagger.Container) *dagger.Container {
	return container.WithExec([]string{"./mach", "--no-interactive", "bootstrap", "--application-choice", "browser"})
}

// build runs the actual build.
func (ci *CI) build(container *dagger.Container, cfg BuildConfig) *dagger.Container {
	jobs := "$(( $(nproc) * 3 / 4 ))"

	if cfg.Platform == PlatformLinux {
		container = container.
			WithEnvVariable("LIBGL_ALWAYS_SOFTWARE", "1").
			WithExec([]string{"sh", "-c", fmt.Sprintf("xvfb-run -a -s '-screen 0 1024x768x24' ./mach configure")}).
			WithExec([]string{"sh", "-c", fmt.Sprintf("xvfb-run -a -s '-screen 0 1024x768x24' nice -n 10 ./mach build --jobs=%s", jobs)}).
			WithExec([]string{"sh", "-c", fmt.Sprintf("xvfb-run -a -s '-screen 0 1024x768x24' ./mach package --compress='%s'", cfg.OmnijarCompress)})
	} else {
		container = container.
			WithExec([]string{"./mach", "configure"}).
			WithExec([]string{"sh", "-c", fmt.Sprintf("nice -n 10 ./mach build --jobs=%s", jobs)}).
			WithExec([]string{"./mach", "package", fmt.Sprintf("--compress=%s", cfg.OmnijarCompress)})
	}

	return container
}

// getObjectDir returns the object directory path based on platform and architecture.
func getObjectDir(cfg BuildConfig) string {
	switch cfg.Platform {
	case PlatformWindows:
		return "obj-x86_64-pc-windows-msvc"
	case PlatformLinux:
		if cfg.Arch == ArchAarch64 {
			return "obj-aarch64-unknown-linux-gnu"
		}
		return "obj-x86_64-pc-linux-gnu"
	default:
		return "obj-x86_64-pc-linux-gnu"
	}
}

// getArtifactExtension returns the artifact file extension based on platform.
func getArtifactExtension(platform Platform) string {
	if platform == PlatformWindows {
		return "zip"
	}
	return "tar.xz"
}

// packageArtifact creates and exports the build artifact.
func (ci *CI) packageArtifact(container *dagger.Container, cfg BuildConfig) *dagger.Container {
	objDir := getObjectDir(cfg)
	ext := getArtifactExtension(cfg.Platform)
	artifactName := fmt.Sprintf("noraneko-%s-%s-moz-artifact.%s", cfg.Platform, cfg.Arch, ext)

	container = container.
		WithExec([]string{"mkdir", "-p", "/output"})

	if cfg.Platform == PlatformWindows {
		container = container.
			WithExec([]string{"sh", "-c", fmt.Sprintf("mv %s/dist/noraneko-*win64.zip /output/%s", objDir, artifactName)})
	} else {
		container = container.
			WithExec([]string{"sh", "-c", fmt.Sprintf("mv %s/dist/noraneko-*.tar.xz /output/%s", objDir, artifactName)})
	}

	// Copy application.ini for MAR updates
	container = container.
		WithExec([]string{"sh", "-c", fmt.Sprintf("cp %s/dist/bin/application.ini /output/application.ini || true", objDir)})

	return container
}

// Build runs the complete build pipeline.
func (ci *CI) Build(ctx context.Context, source *dagger.Directory, cfg BuildConfig) (*dagger.Directory, error) {
	client, err := dagger.Connect(ctx)
	if err != nil {
		return nil, fmt.Errorf("failed to connect to dagger: %w", err)
	}
	defer client.Close()

	// Build pipeline
	container := ci.baseContainer(client)
	container = ci.setupRust(container, cfg)
	container = ci.setupNoraneko(container, source, cfg)
	container = ci.applyPatches(container)
	container = ci.bootstrap(container)
	container = ci.build(container, cfg)
	container = ci.packageArtifact(container, cfg)

	return container.Directory("/output"), nil
}

// BuildLinuxX86_64 builds for Linux x86_64.
func (ci *CI) BuildLinuxX86_64(ctx context.Context, source *dagger.Directory, debug bool, pgo bool, omnijarCompress string) (*dagger.Directory, error) {
	cfg := DefaultBuildConfig()
	cfg.Platform = PlatformLinux
	cfg.Arch = ArchX86_64
	cfg.Debug = debug
	cfg.PGO = pgo
	if omnijarCompress != "" {
		cfg.OmnijarCompress = omnijarCompress
	}

	return ci.Build(ctx, source, cfg)
}

// BuildLinuxAarch64 builds for Linux aarch64.
func (ci *CI) BuildLinuxAarch64(ctx context.Context, source *dagger.Directory, debug bool, pgo bool, omnijarCompress string) (*dagger.Directory, error) {
	cfg := DefaultBuildConfig()
	cfg.Platform = PlatformLinux
	cfg.Arch = ArchAarch64
	cfg.Debug = debug
	cfg.PGO = pgo
	if omnijarCompress != "" {
		cfg.OmnijarCompress = omnijarCompress
	}

	return ci.Build(ctx, source, cfg)
}

// PGOConfig holds PGO-specific configuration.
type PGOConfig struct {
	BrowserArtifactName string
	ArtifactPath        string
	TargetArch          Arch
	UploadArtifactName  string
}

// pgoProfileContainer creates a container for PGO profile generation.
func (ci *CI) pgoProfileContainer(client *dagger.Client, cfg PGOConfig) *dagger.Container {
	return client.Container().
		From("debian:bookworm-slim").
		WithEnvVariable("DEBIAN_FRONTEND", "noninteractive").
		WithExec([]string{"apt-get", "update", "-qq"}).
		WithExec([]string{"apt-get", "install", "-y", "--no-install-recommends",
			"curl", "ca-certificates", "bash", "file",
			"libgtk-3-0", "libdbus-glib-1-2", "libxt6", "libx11-xcb1",
			"libasound2", "libpulse0", "libgl1", "libglib2.0-0",
			"fonts-liberation", "xdg-utils",
			"libdrm2", "libgbm1", "libxcomposite1", "libxdamage1",
			"libxrandr2", "libxshmfence1", "libxtst6",
			"xvfb", "ruby", "python3", "python3-pip", "llvm-19",
		})
}

// GeneratePGOProfile generates PGO profile data from a built browser.
func (ci *CI) GeneratePGOProfile(ctx context.Context, source *dagger.Directory, browserArtifact *dagger.Directory, cfg PGOConfig) (*dagger.Directory, error) {
	client, err := dagger.Connect(ctx)
	if err != nil {
		return nil, fmt.Errorf("failed to connect to dagger: %w", err)
	}
	defer client.Close()

	container := ci.pgoProfileContainer(client, cfg)

	// Setup directories
	container = container.
		WithDirectory("/workspace", source).
		WithDirectory("/browser", browserArtifact).
		WithWorkdir("/workspace").
		WithExec([]string{"mkdir", "-p", "/tmp/output", "/tmp/clang/bin", "obj-firefox/dist/firefox"})

	// Setup LLVM profdata
	profdataName := "llvm-profdata-x86_64"
	if cfg.TargetArch == ArchAarch64 {
		profdataName = "llvm-profdata-arm64"
	}

	container = container.
		WithExec([]string{"cp", "/usr/bin/llvm-profdata-19", fmt.Sprintf("/tmp/clang/%s", profdataName)}).
		WithExec([]string{"chmod", "+x", fmt.Sprintf("/tmp/clang/%s", profdataName)}).
		WithExec([]string{"sh", "-c", `
			cat > /tmp/clang/bin/llvm-profdata << 'EOF'
#!/bin/sh
SCRIPT_DIR="$(dirname "$(readlink -f "$0")")"
PROFDATA_NAME="llvm-profdata-x86_64"
if [ "$(uname -m)" = "aarch64" ]; then
	PROFDATA_NAME="llvm-profdata-arm64"
fi
exec "$SCRIPT_DIR/../$PROFDATA_NAME" "$@"
EOF
			chmod +x /tmp/clang/bin/llvm-profdata
		`})

	// Extract browser artifact and run profile generation
	container = container.
		WithExec([]string{"sh", "-c", `
			cd /browser
			if ls *.tar.* >/dev/null 2>&1; then
				tar -xf *.tar.*
			elif ls *.zip >/dev/null 2>&1; then
				unzip -q *.zip
			fi
		`}).
		WithEnvVariable("MOZ_FETCHES_DIR", "/tmp").
		WithEnvVariable("JARLOG_FILE", "en-US.log").
		WithEnvVariable("LLVM_PROFDATA", "/tmp/clang/bin/llvm-profdata").
		WithEnvVariable("DISPLAY", ":99").
		WithEnvVariable("MOZ_PGO_TIMEOUT_MULTIPLIER", "5").
		WithEnvVariable("MOZ_DISABLE_CONTENT_SANDBOX", "1").
		WithEnvVariable("MOZ_DISABLE_GMP_SANDBOX", "1").
		WithExec([]string{"sh", "-c", "Xvfb :99 -screen 0 1024x768x24 &"}).
		WithExec([]string{"pip3", "install", "requests"}).
		WithExec([]string{"python3", "build/pgo/profileserver.py", "--binary", "/browser/noraneko/noraneko"})

	// Collect profile output
	container = container.
		WithExec([]string{"cp", "merged.profdata", "/tmp/output/"}).
		WithExec([]string{"cp", "en-US.log", "/tmp/output/"})

	return container.Directory("/tmp/output"), nil
}

// CacheCleanup handles cache cleanup operations.
type CacheCleanup struct {
	SizeThresholdMB int
	DryRun          bool
}

// CleanupCaches creates a function that can be run to clean up caches.
// Note: This would typically require GitHub API access which should be
// handled through environment variables or secrets in the workflow.
func (ci *CI) CleanupCaches(ctx context.Context, cfg CacheCleanup) error {
	client, err := dagger.Connect(ctx)
	if err != nil {
		return fmt.Errorf("failed to connect to dagger: %w", err)
	}
	defer client.Close()

	container := client.Container().
		From("node:20-alpine").
		WithExec([]string{"npm", "install", "-g", "@octokit/rest"})

	// The actual cleanup would require GitHub token and repository info
	// which should be passed via environment variables
	container = container.
		WithEnvVariable("SIZE_THRESHOLD_MB", fmt.Sprintf("%d", cfg.SizeThresholdMB)).
		WithEnvVariable("DRY_RUN", fmt.Sprintf("%t", cfg.DryRun))

	_, err = container.Stdout(ctx)
	return err
}

// DailyBuild orchestrates the daily build workflow.
func (ci *CI) DailyBuild(ctx context.Context, source *dagger.Directory, debug, pgo bool, omnijarCompress string) (map[string]*dagger.Directory, error) {
	results := make(map[string]*dagger.Directory)

	// Build Linux x86_64
	linuxX64Output, err := ci.BuildLinuxX86_64(ctx, source, debug, pgo, omnijarCompress)
	if err != nil {
		return nil, fmt.Errorf("linux x86_64 build failed: %w", err)
	}
	results["linux-x86_64"] = linuxX64Output

	// Build Linux aarch64
	linuxArm64Output, err := ci.BuildLinuxAarch64(ctx, source, debug, pgo, omnijarCompress)
	if err != nil {
		return nil, fmt.Errorf("linux aarch64 build failed: %w", err)
	}
	results["linux-aarch64"] = linuxArm64Output

	return results, nil
}

func main() {
	if len(os.Args) < 2 {
		printUsage()
		os.Exit(1)
	}

	command := os.Args[1]

	ctx := context.Background()

	var err error
	switch command {
	case "build":
		cfg := parseFlags()
		err = runBuild(ctx, cfg)
	case "help", "-h", "--help":
		printUsage()
	default:
		fmt.Printf("Unknown command: %s\n", command)
		printUsage()
		os.Exit(1)
	}

	if err != nil {
		fmt.Fprintf(os.Stderr, "Error: %v\n", err)
		os.Exit(1)
	}
}

// CLIConfig holds the CLI configuration.
type CLIConfig struct {
	Platform        string
	Arch            string
	Debug           bool
	PGO             bool
	PGOMode         string
	OmnijarCompress string
	OutputDir       string
}

func parseFlags() CLIConfig {
	cfg := CLIConfig{}

	// Skip the "build" command in args
	buildCmd := flag.NewFlagSet("build", flag.ExitOnError)
	buildCmd.StringVar(&cfg.Platform, "platform", "linux", "Target platform (linux, windows)")
	buildCmd.StringVar(&cfg.Arch, "arch", "x86_64", "Target architecture (x86_64, aarch64)")
	buildCmd.BoolVar(&cfg.Debug, "debug", true, "Enable debug build")
	buildCmd.BoolVar(&cfg.PGO, "pgo", false, "Enable Profile-Guided Optimization")
	buildCmd.StringVar(&cfg.PGOMode, "pgo-mode", "", "PGO mode: generate or use")
	buildCmd.StringVar(&cfg.OmnijarCompress, "omnijar-compress", "deflate", "Omni.ja compression algorithm")
	buildCmd.StringVar(&cfg.OutputDir, "output", "./output", "Output directory for artifacts")

	buildCmd.Parse(os.Args[2:])
	return cfg
}

func runBuild(ctx context.Context, cliCfg CLIConfig) error {
	client, err := dagger.Connect(ctx, dagger.WithLogOutput(os.Stderr))
	if err != nil {
		return fmt.Errorf("failed to connect to dagger: %w", err)
	}
	defer client.Close()

	// Get the source directory (current working directory, go up one level from ci/)
	sourceDir := client.Host().Directory("..", dagger.HostDirectoryOpts{
		Exclude: []string{
			".git",
			"ci/",
			"obj-*",
			"*.log",
		},
	})

	ci := &CI{}

	cfg := BuildConfig{
		Platform:        Platform(cliCfg.Platform),
		Arch:            Arch(cliCfg.Arch),
		Debug:           cliCfg.Debug,
		PGO:             cliCfg.PGO,
		PGOMode:         cliCfg.PGOMode,
		OmnijarCompress: cliCfg.OmnijarCompress,
	}

	fmt.Printf("Building noraneko for %s-%s\n", cfg.Platform, cfg.Arch)
	fmt.Printf("Debug: %v, PGO: %v\n", cfg.Debug, cfg.PGO)

	// Build pipeline
	container := ci.baseContainer(client)
	container = ci.setupRust(container, cfg)
	container = ci.setupNoraneko(container, sourceDir, cfg)
	container = ci.applyPatches(container)
	container = ci.bootstrap(container)
	container = ci.build(container, cfg)
	container = ci.packageArtifact(container, cfg)

	// Export the output
	outputDir := container.Directory("/output")

	// Create output directory
	if err := os.MkdirAll(cliCfg.OutputDir, 0755); err != nil {
		return fmt.Errorf("failed to create output directory: %w", err)
	}

	// Export artifacts
	_, err = outputDir.Export(ctx, cliCfg.OutputDir)
	if err != nil {
		return fmt.Errorf("failed to export artifacts: %w", err)
	}

	fmt.Printf("Build artifacts exported to %s\n", cliCfg.OutputDir)
	return nil
}

func printUsage() {
	fmt.Print(`Noraneko Runtime CI/CD Dagger Module

Usage:
  go run . <command> [options]

Commands:
  build     Build the browser for a specific platform/architecture
  help      Show this help message

Build Options:
  -platform string      Target platform: linux, windows (default "linux")
  -arch string          Target architecture: x86_64, aarch64 (default "x86_64")
  -debug                Enable debug build (default true)
  -pgo                  Enable Profile-Guided Optimization
  -pgo-mode string      PGO mode: generate or use
  -omnijar-compress     Omni.ja compression algorithm (default "deflate")
  -output string        Output directory for artifacts (default "./output")

Examples:
  # Build for Linux x86_64 with debug
  go run . build -platform=linux -arch=x86_64 -debug

  # Build for Linux aarch64 without debug
  go run . build -platform=linux -arch=aarch64 -debug=false

  # Build with PGO profile generation
  go run . build -platform=linux -arch=x86_64 -pgo -pgo-mode=generate
`)
}
