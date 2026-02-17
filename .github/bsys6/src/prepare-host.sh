#!/usr/bin/env bash
# SPDX-License-Identifier: MPL-2.0
# Prepare GitHub Actions host for building
set -eu

echo "-> Installing LLVM-20 and dependencies" >&2
sudo apt-get update
sudo apt-get install -y clang-20 lld-20 libclang-rt-20-dev

echo "-> Preparing GitHub Actions host" >&2
echo "Before:"
free -h
df -h

# Allocate swap
$BSYS6/utils/allocate_swap.sh 30G

# Free disk space
$BSYS6/utils/free_disk_space.sh

# Setup sccache for build caching
$BSYS6/utils/setup_sccache.sh

echo
echo "-> Host preparation completed" >&2
