#!/usr/bin/env bash
# SPDX-License-Identifier: MPL-2.0
# Check if a list contains a value
set -eu

list="$1"
item="$2"

for i in $list; do
  if [ "$i" == "$item" ]; then
    exit 0
  fi
done

exit 1
