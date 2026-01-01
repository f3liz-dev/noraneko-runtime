#!/usr/bin/env bash
# SPDX-License-Identifier: MPL-2.0
# Require a completed build before running this script
set -eu

source $BSYS6/exports/target.sh
source $BSYS6/exports/version.sh

OBJ_DIR="$SOURCEDIR/obj-$MOZ_TARGET"

if [ ! -d "$OBJ_DIR" ]; then
  echo "Error: Build not found at $OBJ_DIR" >&2
  echo "Please run './bsys6 build' first" >&2
  exit 1
fi
