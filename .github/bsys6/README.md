# Noraneko Build System (bsys6)

This is a shell-based build system for Noraneko, adapted from [LibreWolf's bsys6](https://gitlab.com/librewolf-community/browser/bsys6.git).

## Setup

The build system is located at `.github/bsys6/` and can be run directly from there.

## Usage

```bash
cd .github/bsys6

# View available commands
./bsys6 help

# Prepare the build environment and build
TARGET=linux ARCH=x86_64 ./bsys6 prepare build package
```

## Commands

| Command | Description |
|---------|-------------|
| `help` | Show help message |
| `prepare` | Install build dependencies |
| `prepare-host` | Prepare GitHub Actions host (swap, disk cleanup) |
| `bootstrap` | Bootstrap Mozilla build system |
| `source` | Prepare source code and mozconfig |
| `build` | Build the browser |
| `package` | Create distributable package |
| `clean` | Clean build artifacts |

## Workflow

```
prepare -> bootstrap -> source -> build -> package
```

## Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `TARGET` | linux | Target platform: linux, windows |
| `ARCH` | x86_64 | Architecture: x86_64, aarch64 |
| `DEBUG` | false | Enable debug build |
| `PGO` | false | Enable Profile-Guided Optimization |
| `PGO_MODE` | - | PGO mode: generate, use |
| `OMNIJAR_COMPRESS` | deflate | Compression: deflate, zstd, lz4, none |
| `BUILD_JOBS` | 3/4 of CPUs | Number of parallel build jobs |
| `VERBOSE` | false | Enable verbose output |

## Directory Structure

```
.github/bsys6/
├── bsys6              # Main entry point
├── assets/            # Platform-specific configs
│   ├── linux.mozconfig
│   └── windows.mozconfig
├── patches/           # Patches to apply (if any)
└── src/
    ├── exports/       # Environment variable scripts
    │   ├── vars.sh
    │   ├── target.sh
    │   ├── version.sh
    │   ├── require_build.sh
    │   ├── require_target.sh
    │   └── move_artifact.sh
    ├── utils/         # Utility scripts
    │   ├── allocate_swap.sh
    │   ├── dependencies.sh
    │   ├── free_disk_space.sh
    │   ├── list_contains.sh
    │   ├── require_command.sh
    │   └── rustup_target.sh
    ├── bootstrap.sh   # Bootstrap Mozilla build
    ├── build.sh       # Build command
    ├── clean.sh       # Clean artifacts
    ├── help.sh        # Help command
    ├── package.sh     # Package command
    ├── prepare.sh     # Prepare environment
    ├── prepare-host.sh # Prepare GitHub Actions host
    └── source.sh      # Source preparation
```

## Examples

```bash
# Linux x86_64 debug build
TARGET=linux ARCH=x86_64 DEBUG=true ./bsys6 prepare build package

# Linux aarch64 release build
TARGET=linux ARCH=aarch64 ./bsys6 prepare build package

# Windows cross-compilation
TARGET=windows ./bsys6 prepare build package

# PGO profile generation
TARGET=linux PGO=true PGO_MODE=generate ./bsys6 build package

# Just rebuild (skip prepare)
./bsys6 build package

# Clean and rebuild
./bsys6 clean build package
```

## GitHub Actions Integration

For GitHub Actions, use the `prepare-host` command first:

```yaml
- name: Prepare host
  run: |
    cd .github/bsys6
    ./bsys6 prepare-host

- name: Build
  run: |
    cd .github/bsys6
    TARGET=linux ARCH=x86_64 ./bsys6 prepare build package
```

## Credits

Based on [LibreWolf's bsys6](https://gitlab.com/librewolf-community/browser/bsys6.git).

## License

Mozilla Public License 2.0 (MPL-2.0)
