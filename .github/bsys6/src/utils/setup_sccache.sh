#!/usr/bin/env bash
# SPDX-License-Identifier: MPL-2.0
# Setup sccache for build caching
set -eu

SCCACHE_VERSION="${SCCACHE_VERSION:-0.8.2}"

echo "-> Installing sccache v${SCCACHE_VERSION}"

# Detect architecture
ARCH="$(uname -m)"
case "$ARCH" in
  x86_64)
    SCCACHE_ARCH="x86_64"
    ;;
  aarch64|arm64)
    SCCACHE_ARCH="aarch64"
    ;;
  *)
    echo "Unsupported architecture: $ARCH"
    exit 1
    ;;
esac

# Detect OS
OS="$(uname -s)"
case "$OS" in
  Linux)
    SCCACHE_OS="unknown-linux-musl"
    SCCACHE_EXT="tar.gz"
    ;;
  Darwin)
    SCCACHE_OS="apple-darwin"
    SCCACHE_EXT="tar.gz"
    ;;
  *)
    echo "Unsupported OS: $OS"
    exit 1
    ;;
esac

# Download and install sccache
SCCACHE_FILE="sccache-v${SCCACHE_VERSION}-${SCCACHE_ARCH}-${SCCACHE_OS}.${SCCACHE_EXT}"
SCCACHE_URL="https://github.com/mozilla/sccache/releases/download/v${SCCACHE_VERSION}/${SCCACHE_FILE}"

echo "   Downloading from: $SCCACHE_URL"
if ! wget -q "$SCCACHE_URL" -O "/tmp/${SCCACHE_FILE}"; then
  echo "   ERROR: Failed to download sccache from $SCCACHE_URL"
  exit 1
fi

echo "   Extracting sccache"
if ! tar -xzf "/tmp/${SCCACHE_FILE}" -C /tmp; then
  echo "   ERROR: Failed to extract sccache archive"
  rm -f "/tmp/${SCCACHE_FILE}"
  exit 1
fi

echo "   Installing to /usr/local/bin"
if ! sudo install -m 755 "/tmp/sccache-v${SCCACHE_VERSION}-${SCCACHE_ARCH}-${SCCACHE_OS}/sccache" /usr/local/bin/sccache; then
  echo "   ERROR: Failed to install sccache to /usr/local/bin"
  rm -rf "/tmp/${SCCACHE_FILE}" "/tmp/sccache-v${SCCACHE_VERSION}-${SCCACHE_ARCH}-${SCCACHE_OS}"
  exit 1
fi

# Clean up
rm -rf "/tmp/${SCCACHE_FILE}" "/tmp/sccache-v${SCCACHE_VERSION}-${SCCACHE_ARCH}-${SCCACHE_OS}"

# Verify installation
if command -v sccache &> /dev/null; then
  echo "   sccache installed successfully: $(sccache --version)"
else
  echo "   ERROR: sccache installation failed"
  exit 1
fi

# Configure sccache with Cloudflare R2 if credentials are provided
if [ -n "${SCCACHE_BUCKET:-}" ] && [ -n "${SCCACHE_ENDPOINT:-}" ]; then
  echo "-> Configuring sccache with Cloudflare R2"
  
  # Validate R2 configuration
  if [ -z "${AWS_ACCESS_KEY_ID:-}" ] || [ -z "${AWS_SECRET_ACCESS_KEY:-}" ]; then
    echo "   WARNING: AWS_ACCESS_KEY_ID or AWS_SECRET_ACCESS_KEY not set"
    echo "   sccache will not be able to use R2 storage"
  else
    echo "   R2 configuration:"
    echo "   - Bucket: ${SCCACHE_BUCKET}"
    echo "   - Endpoint: ${SCCACHE_ENDPOINT}"
    echo "   - Region: ${SCCACHE_REGION:-auto}"
  fi
  
  # Start sccache server
  echo "-> Starting sccache server"
  if sccache --show-stats &>/dev/null; then
    echo "   sccache server is already running"
  else
    if sccache --start-server; then
      echo "   sccache server started successfully"
    else
      echo "   WARNING: Failed to start sccache server"
      echo "   sccache will start automatically on first use"
    fi
  fi
  
  # Show sccache stats
  echo "-> sccache statistics:"
  sccache --show-stats || true
else
  echo "-> sccache will use local disk cache (no R2 credentials provided)"
fi

echo "-> sccache setup completed"
