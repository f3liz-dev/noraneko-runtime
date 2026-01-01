#!/usr/bin/env bash
# SPDX-License-Identifier: MPL-2.0
# Version management for Noraneko build system
set -eu
set -o pipefail

source "$BSYS6/exports/vars.sh"

if [ -z "${VERSION:-}" ]; then
  # For noraneko-runtime, we use the repository as source
  # Version is derived from the source code
  export VERSION="dev"
fi

if [ -z "${SOURCEDIR:-}" ]; then
  # Default to the repository root (three levels up from bsys6/src: src -> bsys6 -> .github -> repo root)
  export SOURCEDIR="$(readlink -f "$BSYS6/../../..")"
fi

if [ -z "${FULL_VERSION:-}" ]; then
  if [ -n "${RELEASE:-}" ] && [ "$RELEASE" != "1" ]; then
    export FULL_VERSION="$VERSION-$RELEASE"
  else
    export RELEASE="1"
    export FULL_VERSION="$VERSION"
  fi
fi
