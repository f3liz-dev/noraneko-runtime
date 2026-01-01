#!/usr/bin/env bash
# SPDX-License-Identifier: MPL-2.0
# Free disk space on GitHub Actions runners
set -eu

echo "-> Freeing disk space"
echo "Before:"
df -h

# APT cleanup
sudo apt autoremove -y -qq 2>/dev/null || true
sudo apt clean 2>/dev/null || true

# Remove large pre-installed packages using parallel deletion
remove_dirs=(
    "./.git"
    "/home/linuxbrew"
    "/usr/share/dotnet"
    "/usr/local/lib/android"
    "/usr/local/graalvm"
    "/usr/local/share/powershell"
    "/usr/local/share/chromium"
    "/opt/ghc"
    "/usr/local/share/boost"
    "/etc/apache2"
    "/etc/nginx"
    "/usr/local/share/chrome_driver"
    "/usr/local/share/edge_driver"
    "/usr/local/share/gecko_driver"
    "/usr/share/java"
    "/usr/share/miniconda"
    "/usr/local/share/vcpkg"
)

printf '%s\n' "${remove_dirs[@]}" | xargs -P 4 -I {} sudo rm -rf {}

# Clean up hostedtoolcache except for Python
if [ -d "/opt/hostedtoolcache" ]; then
    for subdir in /opt/hostedtoolcache/*; do
        subdir_name="$(basename "$subdir" | tr '[:upper:]' '[:lower:]')"
        if [ -d "$subdir" ] && [ "$subdir_name" != "python" ]; then
            echo "Removing: $subdir"
            sudo rm -rf "$subdir"
        fi
    done
fi

# Clean up directories with version suffixes
for dir in $(find /usr/share -maxdepth 1 -type d \( -name 'gradle-*' -o -name 'julia-*' -o -name 'az_*' \) 2>/dev/null); do
    echo "Removing: $dir"
    sudo rm -rf "$dir"
done

echo
echo "After:"
df -h
