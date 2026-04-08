#!/usr/bin/env bash
# SPDX-License-Identifier: MPL-2.0
# Fetch and unpack macOS SDK for cross-compilation
set -eu

source $BSYS6/source.sh

echo "-> Fetching macOS SDK"
$SOURCE/mach python --virtualenv build \
  $SOURCE/taskcluster/scripts/misc/unpack-sdk.py \
  "https://swcdn.apple.com/content/downloads/22/09/093-00219-A_WIA1LP39TY/evbam2mb02xqr05ju9ddb95y8qil8kz9tm/CLTools_macOSNMOS_SDK.pkg" \
  "f6a5f44b3652f5abdf7ad2602f54ad38774404f45264a4e70cfccc58b8b39aed2a89f74ef22c44bf932d0a55b062ebc3651f73fa06ff755ee5da53b9dcc62fba" \
  "Library/Developer/CommandLineTools/SDKs/MacOSX26.1.sdk" \
  "$MOZBUILD/MacOSX26.1.sdk"
