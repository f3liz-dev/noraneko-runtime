#!/usr/bin/env bash
# SPDX-License-Identifier: MPL-2.0
# Allocate swap space for GitHub Actions runners
set -eu

swap_size="${1:-30G}"

echo "-> Allocating $swap_size swap space"

sudo swapoff /mnt/swapfile 2>/dev/null || true
sudo rm -f /mnt/swapfile
sudo fallocate -l "$swap_size" /mnt/swapfile
sudo chmod 600 /mnt/swapfile
sudo mkswap /mnt/swapfile
sudo swapon /mnt/swapfile

echo "-> Swap allocated successfully"
free -h
