#!/usr/bin/env bash
# SPDX-License-Identifier: MPL-2.0
# Package Noraneko browser
set -eu

source $BSYS6/exports/target.sh
source $BSYS6/exports/require_build.sh

echo "-> Running 'mach package'" >&2

(cd $SOURCE && ./mach package)

if [ "$TARGET" == "windows" ]; then
  source $BSYS6/exports/move_artifact.sh "PACKAGE" "$SOURCE/obj-$MOZ_TARGET/dist" "$PROJECT_NAME-*.zip"
elif [ "$TARGET" == "macos" ]; then
  source $BSYS6/exports/move_artifact.sh "PACKAGE" "$SOURCE/obj-$MOZ_TARGET/dist" "$PROJECT_NAME-*.dmg"
else
  source $BSYS6/exports/move_artifact.sh "PACKAGE" "$SOURCE/obj-$MOZ_TARGET/dist" "$PROJECT_NAME-*.tar.xz"
fi
