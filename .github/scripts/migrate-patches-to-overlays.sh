#!/usr/bin/env bash
# SPDX-License-Identifier: MPL-2.0
# One-time migration: convert .github/patches/upstream/*.patch to .github/overlays/
set -eu

REPO_ROOT="$(git rev-parse --show-toplevel)"
PATCH_DIR="$REPO_ROOT/.github/patches/upstream"
OVERLAY_DIR="$REPO_ROOT/.github/overlays"

if [ ! -d "$PATCH_DIR" ]; then
  echo "No patch directory found at $PATCH_DIR"
  exit 1
fi

mkdir -p "$OVERLAY_DIR"

FAILED=""
COUNT=0

for patch in "$PATCH_DIR"/*.patch; do
  [ -e "$patch" ] || continue
  patch_name=$(basename "$patch")

  # Extract the target file path from the patch header
  file=$(grep '^diff --git a/' "$patch" | head -1 | sed 's|diff --git a/\(.*\) b/.*|\1|')
  if [ -z "$file" ]; then
    echo "SKIP: $patch_name (could not parse file path)"
    FAILED="$FAILED\n  $patch_name"
    continue
  fi

  # Apply patch
  if (cd "$REPO_ROOT" && git apply --ignore-space-change --ignore-whitespace "$patch"); then
    mkdir -p "$OVERLAY_DIR/$(dirname "$file")"
    cp "$REPO_ROOT/$file" "$OVERLAY_DIR/$file"
    # Revert the source file
    (cd "$REPO_ROOT" && git checkout -- "$file")
    echo "OK: $patch_name -> overlays/$file"
    COUNT=$((COUNT + 1))
  else
    echo "FAIL: $patch_name could not be applied"
    FAILED="$FAILED\n  $patch_name"
  fi
done

# Record the upstream base (current HEAD)
git rev-parse HEAD > "$OVERLAY_DIR/UPSTREAM_BASE"

echo ""
echo "Migration complete: $COUNT overlays created"
if [ -n "$FAILED" ]; then
  echo -e "Failed patches:$FAILED"
  echo "These need manual resolution."
fi
