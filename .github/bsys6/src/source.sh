#!/usr/bin/env bash
# SPDX-License-Identifier: MPL-2.0
# Source preparation for Noraneko build
set -eu

source $BSYS6/exports/target.sh
source $BSYS6/exports/version.sh

if [ -z "${SOURCE:-}" ]; then
  if [ ! -d "$SOURCEDIR" ]; then
    echo "Error: Source directory not found at $SOURCEDIR" >&2
    exit 1
  fi

  # Look for existing mozconfig in the repository
  # Priority: .github/workflows/mozconfigs/{platform}-{arch}.mozconfig
  platform_mozconfig="$SOURCEDIR/.github/workflows/mozconfigs/$TARGET-$ARCH.mozconfig"
  
  # Create mozconfig backup if needed
  if [ ! -f "$SOURCEDIR/mozconfig.backup" ]; then
    if [ -f "$platform_mozconfig" ]; then
      echo "-> Using platform mozconfig from $platform_mozconfig" >&2
      cp "$platform_mozconfig" "$SOURCEDIR/mozconfig.backup"
    elif [ -f "$SOURCEDIR/mozconfig" ]; then
      echo "-> Creating mozconfig backup" >&2
      cp "$SOURCEDIR/mozconfig" "$SOURCEDIR/mozconfig.backup"
    else
      touch "$SOURCEDIR/mozconfig.backup"
    fi
  fi

  # Build mozconfig - start with the base
  mozconfig="$(cat "$SOURCEDIR/mozconfig.backup")"

  # Check if sccache was disabled during setup
  SCCACHE_DISABLED_FLAG="/tmp/.sccache_disabled"
  if [ -f "$SCCACHE_DISABLED_FLAG" ] || [ "${SCCACHE_DISABLED:-}" = "true" ]; then
    echo "-> sccache is disabled, will not add to mozconfig" >&2
    SKIP_SCCACHE=true
  else
    SKIP_SCCACHE=false
  fi

  # Add platform-specific config from bsys6 assets (additional options)
  if [ -f "$BSYS6/../assets/$TARGET.mozconfig" ]; then
    platform_config="$(cat "$BSYS6/../assets/$TARGET.mozconfig")"
    
    # Filter out sccache line if sccache is disabled
    if [ "$SKIP_SCCACHE" = "true" ]; then
      platform_config="$(echo "$platform_config" | grep -v "with-ccache=sccache" || true)"
    fi
    
    mozconfig="$(cat <<EOF
$mozconfig
$platform_config
EOF
    )"
  fi

  # Add branding (if not already in the base config)
  if ! echo "$mozconfig" | grep -q "with-branding"; then
    mozconfig="$(cat <<EOF
$mozconfig
ac_add_options --with-branding=$BRANDING_DIR
EOF
    )"
  fi

  # Add debug options if DEBUG is set
  if [ "${DEBUG:-}" == "true" ]; then
    if ! echo "$mozconfig" | grep -q "enable-debug"; then
      mozconfig="$(cat <<EOF
$mozconfig
ac_add_options --enable-debug
EOF
      )"
    fi
  fi

  # Add PGO options
  if [ "${PGO:-}" == "true" ]; then
    if [ "${PGO_MODE:-}" == "generate" ]; then
      mozconfig="$(cat <<EOF
$mozconfig
ac_add_options --enable-profile-generate=cross
EOF
      )"
    elif [ "${PGO_MODE:-}" == "use" ]; then
      mozconfig="$(cat <<EOF
$mozconfig
export MOZ_LTO=cross
ac_add_options --enable-profile-use=cross
ac_add_options --with-pgo-profile-path=${PGO_PROFILE_PATH:-/artifacts/merged.profdata}
ac_add_options --with-pgo-jarlog=${PGO_JARLOG_PATH:-/artifacts/en-US.log}
EOF
      )"
    fi
  fi

  # Check if mozconfig changed
  mozconfig_new_hash=$(echo "$mozconfig" | sha256sum | cut -d' ' -f1)
  mozconfig_old_hash=$(cat "$SOURCEDIR/mozconfig.hash" 2>/dev/null || echo "")

  if [ "$mozconfig_new_hash" != "$mozconfig_old_hash" ]; then
    echo "-> Updating mozconfig, target is $MOZ_TARGET" >&2
    echo "$mozconfig" > "$SOURCEDIR/mozconfig"
    echo "$mozconfig_new_hash" > "$SOURCEDIR/mozconfig.hash"
    export MOZCONFIG_CHANGED="true"
  fi

  export SOURCE="$SOURCEDIR"
fi
