#!/usr/bin/env bash
# SPDX-License-Identifier: MPL-2.0
# Add Rust targets via rustup
set -eu

for target in "$@"; do
  echo "-> Adding Rust target: $target"
  rustup target add "$target" || true
done
