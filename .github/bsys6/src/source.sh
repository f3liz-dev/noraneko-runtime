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

  # Add platform-specific config from bsys6 assets (additional options)
  if [ -f "$BSYS6/../assets/$TARGET.mozconfig" ]; then
    mozconfig="$(cat <<EOF
$mozconfig
$(cat "$BSYS6/../assets/$TARGET.mozconfig")
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

  # Add sccache configuration if enabled
  BSYS6_STATE_DIR="${BSYS6_STATE_DIR:-/tmp/bsys6-state}"
  USE_SCCACHE_FILE="$BSYS6_STATE_DIR/USE_SCCACHE"
  
  if [ -f "$USE_SCCACHE_FILE" ]; then
    USE_SCCACHE=$(cat "$USE_SCCACHE_FILE")
  else
    USE_SCCACHE="${USE_SCCACHE:-false}"
  fi
  
  if [ "$USE_SCCACHE" = "true" ]; then
    echo "-> Configuring sccache in mozconfig" >&2
    
    # Configure sccache with R2 bucket
    # Both SCCACHE_BUCKET and SCCACHE_ENDPOINT are required (validated in setup_sccache.sh)
    if [ -n "${SCCACHE_BUCKET:-}" ] && [ -n "${SCCACHE_ENDPOINT:-}" ]; then
      mozconfig="$(cat <<EOF
$mozconfig

# sccache configuration
ac_add_options --with-ccache=sccache
mk_add_options "export SCCACHE_BUCKET=$SCCACHE_BUCKET"
EOF
      )"
      
      # Add endpoint if using R2/S3
      if [ -n "${SCCACHE_ENDPOINT:-}" ]; then
        mozconfig="$(cat <<EOF
$mozconfig
mk_add_options "export SCCACHE_ENDPOINT=$SCCACHE_ENDPOINT"
EOF
        )"
      fi
      
      # Add region if specified
      if [ -n "${SCCACHE_REGION:-}" ]; then
        mozconfig="$(cat <<EOF
$mozconfig
mk_add_options "export SCCACHE_REGION=$SCCACHE_REGION"
EOF
        )"
      fi
      
      # Configure verbose stats and max frame length
      mozconfig="$(cat <<EOF
$mozconfig
export CCACHE="sccache"
export SCCACHE_VERBOSE_STATS=1
# Workaround for https://github.com/mozilla/sccache/issues/459#issuecomment-618756635
mk_add_options "export SCCACHE_MAX_FRAME_LENGTH=50000000"
EOF
      )"
      
      # Add daemon management if sccache binary is available
      if command -v sccache >/dev/null 2>&1; then
        SCCACHE_PATH="$(command -v sccache)"
        mozconfig="$(cat <<EOF
$mozconfig
mk_add_options MOZBUILD_MANAGE_SCCACHE_DAEMON=$SCCACHE_PATH
EOF
        )"
      fi
    fi
  else
    echo "-> sccache is disabled (credentials not available or not configured)" >&2
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
