#!/usr/bin/env bash
# SPDX-License-Identifier: MPL-2.0
# Require a specific target platform
set -eu

expected_target="${1:-}"

if [ -z "$expected_target" ]; then
  echo "Error: require_target.sh needs a target argument" >&2
  exit 1
fi

source $BSYS6/exports/target.sh

if [ "$TARGET" != "$expected_target" ]; then
  echo "Error: This command requires TARGET=$expected_target, but TARGET=$TARGET" >&2
  exit 1
fi
