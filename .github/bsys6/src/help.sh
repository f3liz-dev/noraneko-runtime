#!/usr/bin/env bash
# SPDX-License-Identifier: MPL-2.0
# Display help for Noraneko build system
set -eu

cat <<EOF
Noraneko Build System (based on bsys6 from LibreWolf)
======================================================

Usage: ./bsys6 <command> [command2] [command3] ...

Commands can be chained together to run in sequence.

Core Commands:
  help        Show this help message
  prepare     Install dependencies for building
  bootstrap   Bootstrap the Mozilla build system
  source      Prepare source code and mozconfig
  build       Build the browser
  package     Create distributable package

Workflow:
  prepare -> bootstrap -> source -> build -> package

Environment Variables:
  TARGET              Target platform: linux (default), windows
  ARCH                Architecture: x86_64 (default), aarch64
  DEBUG               Enable debug build: true, false
  PGO                 Enable PGO: true, false
  PGO_MODE            PGO mode: generate, use
  OMNIJAR_COMPRESS    Compression: deflate (default), zstd, lz4, none
  BUILD_JOBS          Number of parallel build jobs (default: 3/4 of CPUs)
  VERBOSE             Verbose output: true, false

Examples:
  # Prepare and build for Linux x86_64
  TARGET=linux ARCH=x86_64 ./bsys6 prepare build package

  # Build with debug enabled
  DEBUG=true ./bsys6 build package

  # Cross-compile for Windows
  TARGET=windows ./bsys6 prepare build package

  # Just run the build step
  ./bsys6 build

  # View help
  ./bsys6 help

For more information, see:
  https://github.com/nyanrus/noraneko/
EOF
