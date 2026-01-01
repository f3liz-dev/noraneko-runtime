#!/usr/bin/env bash
# SPDX-License-Identifier: MPL-2.0
# Move artifact to output directory
set -eu

artifact_name="${1:-}"
source_dir="${2:-}"
pattern="${3:-}"

if [ -z "$artifact_name" ] || [ -z "$source_dir" ] || [ -z "$pattern" ]; then
  echo "Error: move_artifact.sh requires 3 arguments: artifact_name source_dir pattern" >&2
  exit 1
fi

# Find the artifact using -name (glob pattern) instead of -regex
# The pattern should be a shell glob like "noraneko-*.tar.xz"
artifact_path=$(find "$source_dir" -maxdepth 1 -type f -name "$pattern" | head -n1)

if [ -z "$artifact_path" ]; then
  echo "Error: No artifact matching pattern '$pattern' found in '$source_dir'" >&2
  exit 1
fi

# Move to entry directory
artifact_filename=$(basename "$artifact_path")
mv "$artifact_path" "$ENTRY_PWD/$artifact_filename"

# Export the artifact path
export "$artifact_name"="$ENTRY_PWD/$artifact_filename"
echo "-> $artifact_name: $ENTRY_PWD/$artifact_filename"
