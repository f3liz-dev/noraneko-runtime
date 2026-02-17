#!/usr/bin/env bash
# SPDX-License-Identifier: MPL-2.0
# Core variables and configuration for Noraneko build system
set -e

if [ -f "$BSYS6/../env.sh" ]; then
  source $BSYS6/../env.sh
fi

if [ -z "$BSYS6" ]; then
  export BSYS6="$(dirname "$(readlink -f "$0/..")")"
fi

if [ -z "${ARCH:-}" ]; then
  export ARCH="x86_64"
fi

if [ -z "${MOZBUILD:-}" ]; then
  export MOZBUILD="$HOME/.mozbuild"
fi

if [ -z "${WORKDIR:-}" ]; then
  export WORKDIR="$HOME/.local/share/noraneko-bsys6/work"
fi
mkdir -p "$WORKDIR"

export AVAILABLE_TARGETS="linux windows macos"
export AVAILABLE_ARCHS="x86_64 aarch64"
export AVAILABLE_ARTIFACTS="SOURCE PACKAGE"

if ! $BSYS6/utils/list_contains.sh "$AVAILABLE_ARCHS" "$ARCH"; then
  echo "Unsupported architecture $ARCH"
  exit 1
fi

# Project configuration
export PROJECT_NAME="noraneko"
export PROJECT_DISPLAY_NAME="Noraneko"
export BRANDING_DIR="browser/branding/noraneko-unofficial"
