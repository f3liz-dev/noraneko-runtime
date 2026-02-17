#!/usr/bin/env bash
# SPDX-License-Identifier: MPL-2.0
# Fetch and install Gecko toolchain artifacts
set -eu

source $BSYS6/source.sh

cd "$MOZBUILD"

while [[ $# -gt 0 ]]; do
  echo "-> Fetching toolchain artifact $1"
  case $1 in
    linux64-binutils)
      $SOURCE/mach artifact toolchain --from-task Z03jCC7wSK6Y3R_59fying:public/build/binutils.tar.zst
      ;;
    *)
      $SOURCE/mach artifact toolchain --from-build "$1"
      ;;
  esac
  shift
done
