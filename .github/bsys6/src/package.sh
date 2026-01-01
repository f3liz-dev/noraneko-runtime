#!/usr/bin/env bash
# SPDX-License-Identifier: MPL-2.0
# Package Noraneko browser
set -eu

source $BSYS6/exports/target.sh
source $BSYS6/exports/require_build.sh

echo "-> Running 'mach package'" >&2

# Get compression option
OMNIJAR_COMPRESS="${OMNIJAR_COMPRESS:-deflate}"

(cd $SOURCE && ./mach package --compress="$OMNIJAR_COMPRESS")

if [ "$TARGET" == "windows" ]; then
  source $BSYS6/exports/move_artifact.sh "PACKAGE" "$SOURCE/obj-$MOZ_TARGET/dist" "$PROJECT_NAME-*.zip"
else
  source $BSYS6/exports/move_artifact.sh "PACKAGE" "$SOURCE/obj-$MOZ_TARGET/dist" "$PROJECT_NAME-*.tar.xz"
fi
