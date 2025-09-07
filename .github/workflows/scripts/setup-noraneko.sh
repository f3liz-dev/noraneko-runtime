#!/usr/bin/env bash
# SPDX-License-Identifier: MPL-2.0
set -e

# Arguments:
#   $1: platform (linux|mac|windows)
#   $2: arch (optional, for mac: x86_64|aarch64)
#   $3: debug (true|false)
#   $4: pgo (true|false or artifact name)
#   $5: MOZ_BUILD_DATE (optional)

PLATFORM="$1"
ARCH="$2"
DEBUG="$3"
PGO="$4"
MOZ_BUILD_DATE="$5"

if [[ -n "$MOZ_BUILD_DATE" ]]; then
  export MOZ_BUILD_DATE="$MOZ_BUILD_DATE"
fi

cd "$GITHUB_WORKSPACE"

# update noraneko to latest
# https://github.com/orgs/community/discussions/26818
git -C noraneko config remote.origin.fetch +refs/heads/*:refs/remotes/origin/*
git submodule update --remote noraneko

if [[ "$PLATFORM" == "windows" ]]; then
  cp ./.github/workflows/mozconfigs/windows-x86_64.mozconfig mozconfig
elif [[ "$PLATFORM" == "linux" ]]; then
  if [[ "$ARCH" == "aarch64" ]]; then
    cp ./.github/workflows/mozconfigs/linux-aarch64.mozconfig mozconfig
  else
    cp ./.github/workflows/mozconfigs/linux-x86_64.mozconfig mozconfig
  fi
fi

cp -r ./noraneko/static/gecko/branding/* ./browser/branding/

# Set Branding/Flat Chrome
echo "ac_add_options --with-branding=browser/branding/noraneko-unofficial" >> mozconfig
echo "ac_add_options --enable-chrome-format=flat" >> mozconfig

sudo apt install msitools -y
# # https://github.com/actions/runner-images/issues/6283#issuecomment-1260049630
# /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
# eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)"
# brew install sccache

# SCCACHE
{
  echo "mk_add_options 'export RUSTC_WRAPPER=/opt/hostedtoolcache/sccache/0.10.0/x64/sccache'"
  echo "mk_add_options 'export CCACHE_CPP2=yes'"
  echo "ac_add_options --with-ccache=/opt/hostedtoolcache/sccache/0.10.0/x64/sccache"
  echo "mk_add_options 'export SCCACHE_GHA_ENABLED=on'"
} >> mozconfig

# Debug
if [[ "$DEBUG" == "true" ]]; then
  echo "ac_add_options --enable-debug" >> mozconfig
fi

# PGO
if [[ "$PGO" == "true" ]]; then
  echo 'ac_add_options --enable-profile-generate=cross' >> mozconfig
elif [[ -n "$PGO" && "$PGO" != "false" ]]; then
  echo 'export MOZ_LTO=cross' >> mozconfig
  echo 'ac_add_options --enable-profile-use=cross' >> mozconfig
  echo 'ac_add_options --with-pgo-profile-path=$(echo ~)/artifacts/merged.profdata' >> mozconfig
  echo 'ac_add_options --with-pgo-jarlog=$(echo ~)/artifacts/en-US.log' >> mozconfig
fi

# Update Channel
echo "ac_add_options --with-version-file-path=noraneko/static/gecko/config" >> mozconfig
echo "ac_add_options --enable-update-channel=alpha" >> mozconfig

sed -i 's|https://@MOZ_APPUPDATE_HOST@/update/6/%PRODUCT%/%VERSION%/%BUILD_ID%/%BUILD_TARGET%/%LOCALE%/%CHANNEL%/%OS_VERSION%/%SYSTEM_CAPABILITIES%/%DISTRIBUTION%/%DISTRIBUTION_VERSION%/update.xml|https://github.com/nyanrus/noraneko/releases/download/%CHANNEL%/%BUILD_TARGET%.update.xml|g' ./build/application.ini.in

./mach --no-interactive bootstrap --application-choice browser
