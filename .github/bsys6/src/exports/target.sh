#!/usr/bin/env bash
# SPDX-License-Identifier: MPL-2.0
# Target platform configuration for Noraneko build system
set -eu

# Extension of vars.sh, but kept in a separate file because
# sometimes we want TARGET to be undefined, to be able to set
# it to the right value when needed in require_target.sh.

if [ -z "${TARGET:-}" ]; then
  export TARGET="linux"
fi

case $TARGET in
linux)
  export MOZ_TARGET="$ARCH-pc-linux-gnu"
  if [ "${ARCH:-}" == "aarch64" ]; then
    export MOZ_TARGET="aarch64-unknown-linux-gnu"
  fi
  ;;
windows)
  export MOZ_TARGET="$ARCH-pc-mingw32"
  if [ "${ARCH:-}" == "aarch64" ]; then
    export MOZ_TARGET="aarch64-pc-windows-msvc"
  else
    export MOZ_TARGET="x86_64-pc-windows-msvc"
  fi
  ;;
macos)
  if [ "${ARCH:-}" == "aarch64" ] || [ "${ARCH:-}" == "arm64" ]; then
    export MOZ_TARGET="aarch64-apple-darwin"
  else
    export MOZ_TARGET="x86_64-apple-darwin"
  fi
  ;;
*)
  echo "Unsupported target $TARGET"
  exit 1
  ;;
esac
