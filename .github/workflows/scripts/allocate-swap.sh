#!/usr/bin/env bash
# SPDX-License-Identifier: MPL-2.0
# Allocate swap space and free up disk space for Firefox builds on GitHub Actions

set -e

echo "Before:"
free -h
df -h

echo
echo

# Allocate 30GB swap
sudo swapoff /mnt/swapfile 2>/dev/null || true
sudo rm -f /mnt/swapfile
sudo fallocate -l 30G /mnt/swapfile
sudo chmod 600 /mnt/swapfile
sudo mkswap /mnt/swapfile
sudo swapon /mnt/swapfile

# APT operations with quiet flags
sudo apt autoremove -y -qq
sudo apt clean

# Optimized directory removal using rsync method
mkdir -p /tmp/empty

remove_dir() {
    local dir="$1"
    if [ -d "$dir" ]; then
        echo "Removing: $dir"
        sudo rsync -a --delete /tmp/empty/ "$dir/" 2>/dev/null || true
        sudo rmdir "$dir" 2>/dev/null || true
    fi
}

# Remove directories to free up disk space
remove_dir "./git"
remove_dir "/home/linuxbrew"
remove_dir "/usr/share/dotnet"
remove_dir "/usr/local/lib/android"
remove_dir "/usr/local/graalvm"
remove_dir "/usr/local/share/powershell"
remove_dir "/usr/local/share/chromium"
remove_dir "/opt/ghc"
remove_dir "/usr/local/share/boost"
remove_dir "/etc/apache2"
remove_dir "/etc/nginx"
remove_dir "/usr/local/share/chrome_driver"
remove_dir "/usr/local/share/edge_driver"
remove_dir "/usr/local/share/gecko_driver"
remove_dir "/usr/share/java"
remove_dir "/usr/share/miniconda"
remove_dir "/usr/local/share/vcpkg"

rmdir /tmp/empty 2>/dev/null || true

echo
echo

echo "After:"
free -h
df -h
