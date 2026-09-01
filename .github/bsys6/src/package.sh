#!/usr/bin/env bash
# SPDX-License-Identifier: MPL-2.0
# Package Noraneko browser
set -eu

source $BSYS6/exports/target.sh
source $BSYS6/exports/require_build.sh

echo "-> Running 'mach package'" >&2

if [ "$TARGET" == "macos" ] && [ "$(uname -m)" == "aarch64" ]; then
  echo "-> Skipping mach package (no dmg tools on aarch64 host; packaging as tar)" >&2
else
  (cd $SOURCE && ./mach package)
fi

if [ "$TARGET" == "windows" ]; then
  source $BSYS6/exports/move_artifact.sh "PACKAGE" "$SOURCE/obj-$MOZ_TARGET/dist" "$PROJECT_NAME-*.zip"
elif [ "$TARGET" == "macos" ]; then
  if [ "$(uname -m)" == "aarch64" ]; then
    # aarch64 単体チャネル: dist の .app をそのまま tar.xz に
    app_dir="$SOURCE/obj-$MOZ_TARGET/dist"
    app_name="$(cd "$app_dir" && ls -d *.app | head -n1)"
    [ -n "$app_name" ] || { echo "Error: no .app in $app_dir" >&2; exit 1; }
    tar -cJf "$app_dir/$PROJECT_NAME-macos-$ARCH-moz-artifact.tar.xz" -C "$app_dir" "$app_name"
    source $BSYS6/exports/move_artifact.sh "PACKAGE" "$app_dir" "$PROJECT_NAME-macos-*.tar.xz"
  else
    source $BSYS6/exports/move_artifact.sh "PACKAGE" "$SOURCE/obj-$MOZ_TARGET/dist" "$PROJECT_NAME-*.dmg"
  fi
else
  source $BSYS6/exports/move_artifact.sh "PACKAGE" "$SOURCE/obj-$MOZ_TARGET/dist" "$PROJECT_NAME-*.tar.xz"
fi
