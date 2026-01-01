#!/usr/bin/env bash
# SPDX-License-Identifier: MPL-2.0
# Build Noraneko browser
set -eu

source $BSYS6/exports/target.sh
source $BSYS6/exports/version.sh

source "$BSYS6/source.sh"

# Apply patches if any exist
PATCH_DIR="$BSYS6/../patches"
if [ -d "$PATCH_DIR" ]; then
  for patch in "$PATCH_DIR"/*.patch; do
    if [ -e "$patch" ]; then
      echo "-> Applying patch: $(basename $patch)" >&2
      (cd $SOURCE && git apply "$patch") || echo "Warning: Patch $(basename $patch) may have already been applied" >&2
    fi
  done
fi

# Copy branding assets if they exist
BRANDING_ASSETS="$SOURCEDIR/.github/assets/branding"
if [ -d "$BRANDING_ASSETS" ]; then
  echo "-> Copying branding assets" >&2
  cp -r "$BRANDING_ASSETS"/* "$SOURCE/browser/branding/" 2>/dev/null || true
fi

echo "-> Running 'mach build'" >&2

# Calculate job count (3/4 of available CPUs)
if [ -z "${BUILD_JOBS:-}" ]; then
  BUILD_JOBS="$(( $(nproc) * 3 / 4 ))"
fi

# Run build
if [ "${VERBOSE:-}" == "true" ]; then
  (cd $SOURCE && ./mach build -v --jobs=$BUILD_JOBS)
else
  (cd $SOURCE && ./mach build --jobs=$BUILD_JOBS)
fi

echo "-> Build completed successfully" >&2
