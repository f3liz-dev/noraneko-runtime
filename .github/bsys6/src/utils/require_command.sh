#!/usr/bin/env bash
# SPDX-License-Identifier: MPL-2.0
# Check if a command is available
set -eu

cmd="$1"

if ! command -v "$cmd" &> /dev/null; then
  echo "Error: Required command '$cmd' not found" >&2
  exit 1
fi
