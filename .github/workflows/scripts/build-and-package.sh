#!/usr/bin/env bash
set -e

# Arguments:
#   $1: platform (linux|mac|windows)
#   $2: arch (x86_64|aarch64)
#   $3: profile-generate-mode (true|false)
#   $4: MOZ_BUILD_DATE (optional)

PLATFORM="$1"
ARCH="$2"
PROFGEN="$3"
MOZ_BUILD_DATE="$4"

if [[ -n "$MOZ_BUILD_DATE" ]]; then
  export MOZ_BUILD_DATE="$MOZ_BUILD_DATE"
fi

if [[ "$PLATFORM" == "linux" ]]; then
  Xvfb :2 -screen 0 1024x768x24 &
  export DISPLAY=:2
fi

./mach configure

export MOZ_NUM_JOBS=$(( $(nproc) * 3 / 4 ))
nice -n 10 ./mach build --jobs=$MOZ_NUM_JOBS
./mach package
rm -rf ~/.cargo

# Artifact packaging
mkdir -p ~/output

ARTIFACT_NAME="noraneko-${PLATFORM}-${ARCH}-moz-artifact"
if [[ "$PLATFORM" == "windows" ]]; then
  mv obj-x86_64-pc-windows-msvc/dist/noraneko-*win64.zip ~/output/${ARTIFACT_NAME}.zip
  cp ./obj-x86_64-pc-windows-msvc/dist/bin/application.ini ./nora-application.ini || true
elif [[ "$PLATFORM" == "linux" ]]; then
  if [[ "$ARCH" == "aarch64" ]]; then
    mv obj-aarch64-unknown-linux-gnu/dist/noraneko-*.tar.xz ~/output/${ARTIFACT_NAME}.tar.xz
    cp ./obj-aarch64-unknown-linux-gnu/dist/bin/application.ini ./nora-application.ini || true
  else
    mv obj-x86_64-pc-linux-gnu/dist/noraneko-*.tar.xz ~/output/${ARTIFACT_NAME}.tar.xz
    cp ./obj-x86_64-pc-linux-gnu/dist/bin/application.ini ./nora-application.ini || true
  fi
fi
