#!/usr/bin/env bash
# SPDX-License-Identifier: MPL-2.0
# Fetch and unpack macOS SDK for cross-compilation
set -eu

source $BSYS6/source.sh

# 冪等ガード: 展開済みなら触らない(unpack-sdk.py は symlink 衝突で死ぬ)。
# 途中死の食い残しは消してやり直す。
if [ -f "$MOZBUILD/MacOSX26.5.sdk/SDKSettings.plist" ]; then
  echo "-> macOS SDK already present, skipping"
  return 0 2>/dev/null || exit 0
fi
rm -rf "$MOZBUILD/MacOSX26.5.sdk"

echo "-> Fetching macOS SDK"
$SOURCE/mach python --virtualenv build \
  $SOURCE/taskcluster/scripts/misc/unpack-sdk.py \
  "https://swcdn.apple.com/content/downloads/09/08/047-91568-A_Y1CFZWQCD4/4xekpyz43i26dbp4enxfro8eb1q7wiujh5/CLTools_macOSNMOS_SDK.pkg" \
  "5db8b5a06a489a7d3ec587ebb7e01be55163128029923fc24edcad47faecd67830193c0d91e2643ee0e92f2ccca37adf20e4c42cf8de5784666f8663638b5cc5" \
  "Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk" \
  "$MOZBUILD/MacOSX26.5.sdk"
