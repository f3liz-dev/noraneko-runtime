#!/usr/bin/env bash
# SPDX-License-Identifier: MPL-2.0
# Install dependencies using apt-get (Debian/Ubuntu) or pacman (Arch)
set -eu

apt_packages="${1:-}"
pacman_packages="${2:-}"

if command -v apt-get &> /dev/null; then
  if [ -n "$apt_packages" ]; then
    echo "-> Installing apt packages: $apt_packages"
    sudo apt-get update -qq
    sudo apt-get install -y --no-install-recommends $apt_packages
  fi
elif command -v pacman &> /dev/null; then
  if [ -n "$pacman_packages" ]; then
    echo "-> Installing pacman packages: $pacman_packages"
    sudo pacman -Sy --noconfirm $pacman_packages
  fi
else
  echo "Warning: No supported package manager found (apt-get or pacman)" >&2
fi
