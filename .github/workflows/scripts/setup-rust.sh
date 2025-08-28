#!/usr/bin/env bash
set -e

# Arguments:
#   $1: platform (linux|mac|windows)
#   $2: arch (optional, for mac: x86_64|aarch64)
#   $3: pgo_artifact_name (optional)

PLATFORM="$1"
ARCH="$2"
PGO_ARTIFACT_NAME="$3"

if [[ "$PLATFORM" == "windows" ]]; then
  if [[ -n "$PGO_ARTIFACT_NAME" ]]; then
    rustup toolchain install 1.81.0
    rustup default 1.81.0
  fi
  rustup target add x86_64-pc-windows-msvc
elif [[ "$PLATFORM" == "linux" ]]; then
  if [[ "$ARCH" == "aarch64" ]]; then
    rustup default stable
    rustup target add aarch64-unknown-linux-gnu
  else
    rustup default stable
    rustup target add x86_64-unknown-linux-gnu
  fi
fi

rustc --version --verbose
export CARGO_INCREMENTAL=0
