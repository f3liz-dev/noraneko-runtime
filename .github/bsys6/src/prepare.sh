#!/usr/bin/env bash
# SPDX-License-Identifier: MPL-2.0
# Prepare build environment for Noraneko
set -eu

source $BSYS6/exports/target.sh

case $TARGET in

linux)
  echo "-> Preparing build environment for Linux (target: $TARGET, arch: $ARCH)"

  # Install base dependencies
  $BSYS6/utils/dependencies.sh "python3-pip curl gnupg2 jq build-essential autoconf2.13 yasm libgtk-3-dev libxtst6 libxrandr2 libasound2-dev libpango1.0-dev libatk1.0-dev libcairo-gobject2 libgdk-pixbuf2.0-dev libdbus-glib-1-dev xvfb mesa-utils msitools" "python-pip curl gnupg jq base-devel autoconf yasm gtk3 libxtst libxrandr alsa-lib pango atk cairo gdk-pixbuf2 dbus-glib xorg-server-xvfb mesa msitools"

  # Install LLVM/Clang 19 on Debian/Ubuntu
  if command -v apt-get &> /dev/null; then
    echo "-> Installing LLVM/Clang 19"
    wget -qO- https://apt.llvm.org/llvm-snapshot.gpg.key | sudo gpg --dearmor -o /etc/apt/trusted.gpg.d/llvm.gpg || true
    echo 'deb http://apt.llvm.org/bookworm/ llvm-toolchain-bookworm-19 main' | sudo tee -a /etc/apt/sources.list || true
    sudo apt-get update -qq
    sudo apt-get install -y --no-install-recommends llvm-19 clang-19 || true
  fi

  # Cross-compilation dependencies
  if [ "$ARCH" == "aarch64" ]; then
    $BSYS6/utils/dependencies.sh "gcc-aarch64-linux-gnu g++-aarch64-linux-gnu binutils-aarch64-linux-gnu" "aarch64-linux-gnu-gcc aarch64-linux-gnu-binutils"
  fi

  # Bootstrap mach
  source $BSYS6/exports/version.sh
  $BSYS6/bootstrap.sh

  # Add Rust targets
  $BSYS6/utils/rustup_target.sh "x86_64-unknown-linux-gnu" "aarch64-unknown-linux-gnu"
  ;;

windows)
  echo "-> Preparing build environment for Windows cross-compilation (target: $TARGET)"

  $BSYS6/utils/dependencies.sh "python3-pip curl msitools zstd libc6-i386 p7zip-full jq zip unzip wget mono-complete gettext-base pkg-config wine64" "python-pip curl msitools zstd lib32-glibc p7zip jq zip unzip wget mono gettext pkgconf wine"

  # Install LLVM/Clang 19 on Debian/Ubuntu
  if command -v apt-get &> /dev/null; then
    echo "-> Installing LLVM/Clang 19"
    wget -qO- https://apt.llvm.org/llvm-snapshot.gpg.key | sudo gpg --dearmor -o /etc/apt/trusted.gpg.d/llvm.gpg || true
    echo 'deb http://apt.llvm.org/bookworm/ llvm-toolchain-bookworm-19 main' | sudo tee -a /etc/apt/sources.list || true
    sudo apt-get update -qq
    sudo apt-get install -y --no-install-recommends llvm-19 clang-19 || true
  fi

  source $BSYS6/exports/version.sh
  $BSYS6/bootstrap.sh

  # Add Windows Rust targets
  $BSYS6/utils/rustup_target.sh "x86_64-pc-windows-msvc" "aarch64-pc-windows-msvc" "i686-pc-windows-msvc"
  ;;

*)
  echo "Cannot prepare build environment for target '$TARGET'"
  exit 1
  ;;
esac

echo "-> Build environment prepared successfully" >&2
