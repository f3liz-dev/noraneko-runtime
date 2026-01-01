#!/usr/bin/env bash
# SPDX-License-Identifier: MPL-2.0
# Clean build artifacts
set -eu

source $BSYS6/exports/target.sh
source $BSYS6/exports/version.sh

echo "-> Cleaning build artifacts" >&2

if [ -d "$SOURCEDIR/obj-$MOZ_TARGET" ]; then
  echo "Removing $SOURCEDIR/obj-$MOZ_TARGET"
  rm -rf "$SOURCEDIR/obj-$MOZ_TARGET"
fi

# Remove mozconfig hash to force regeneration
rm -f "$SOURCEDIR/mozconfig.hash"

echo "-> Clean completed" >&2
