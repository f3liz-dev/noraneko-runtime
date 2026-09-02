#!/usr/bin/env bash
# SPDX-License-Identifier: MPL-2.0
# 焼けた物を GitHub Release(passed-<BuildID>)に上げる。
# 資産名は旧 release と同じ形: noraneko-<target>-<arch>-moz-artifact.*,
# <target>-<arch>-application-ini.zip(nora-application.ini), <target>-<arch>-dist-host.zip
# 要: gh(GH_TOKEN か gh auth)、zip。RELEASE_REPO で上げ先を変えられる。
set -eu

source $BSYS6/exports/version.sh

OUT="$ENTRY_PWD/release-out"
rm -rf "$OUT"; mkdir -p "$OUT"
BUILDID=""

emit() { # target arch objdir <application.ini の glob> <artifact の glob>
  local t=$1 a=$2 obj=$3 ini art
  [ -d "$SOURCEDIR/$obj" ] || return 0
  ini=$(ls $4 2>/dev/null | head -n1 || true)
  art=$(ls $ENTRY_PWD/$5 2>/dev/null | head -n1 || true)
  if [ -z "$ini" ] || [ -z "$art" ]; then echo "-> skip $t-$a (ini=${ini:-無} artifact=${art:-無})" >&2; return 0; fi
  local ext="${art##*.}"; [ "$ext" = "xz" ] && ext="tar.xz"
  cp "$art" "$OUT/$PROJECT_NAME-$t-$a-moz-artifact.$ext"
  cp "$ini" "$OUT/nora-application.ini"
  (cd "$OUT" && zip -q "$t-$a-application-ini.zip" nora-application.ini && rm -f nora-application.ini)
  if [ -d "$SOURCEDIR/$obj/dist/host/bin" ]; then
    (cd "$SOURCEDIR" && zip -qr "$OUT/$t-$a-dist-host.zip" "$obj/dist/host/bin")
  fi
  [ -n "$BUILDID" ] || BUILDID=$(grep -m1 '^BuildID=' "$ini" | cut -d= -f2 | tr -d '\r')
  echo "-> $t-$a: packaged (BuildID $BUILDID)" >&2
}

emit linux   aarch64 obj-aarch64-unknown-linux-gnu "$SOURCEDIR/obj-aarch64-unknown-linux-gnu/dist/bin/application.ini"            "$PROJECT_NAME-*.linux-aarch64.tar.xz"
emit linux   x86_64  obj-x86_64-pc-linux-gnu       "$SOURCEDIR/obj-x86_64-pc-linux-gnu/dist/bin/application.ini"                  "$PROJECT_NAME-*.linux-x86_64.tar.xz"
emit macos   aarch64 obj-aarch64-apple-darwin      "$SOURCEDIR/obj-aarch64-apple-darwin/dist/*.app/Contents/Resources/application.ini" "$PROJECT_NAME-macos-aarch64-moz-artifact.tar.xz"
emit windows x86_64  obj-x86_64-pc-windows-msvc    "$SOURCEDIR/obj-x86_64-pc-windows-msvc/dist/bin/application.ini"               "$PROJECT_NAME-*.win64.zip"

[ -n "$BUILDID" ] || { echo "Error: 上げる物が無い" >&2; exit 1; }
(cd "$OUT" && sha256sum * > SHA256SUMS)

TAG="passed-$BUILDID"
if [ "${RELEASE_DRY_RUN:-}" = "1" ]; then echo "-> dry-run: $TAG に上げる物:" >&2; (cd "$OUT" && ls -la) >&2; exit 0; fi
REPO="${RELEASE_REPO:-f3liz-casa/noraneko-runtime}"
if ! gh release view "$TAG" -R "$REPO" >/dev/null 2>&1; then
  gh release create "$TAG" -R "$REPO" --title "Runtime Release - $TAG" --notes "$(cat <<NOTES
This is a runtime release for Noraneko (built by noraneko-ci, $(uname -m) host).

**WARNING:** This release is not a Noraneko installer. Visit the [releases page](https://github.com/nyanrus/noraneko/releases/) to get Noraneko itself.

Commit: $(git -C "$SOURCEDIR" rev-parse HEAD 2>/dev/null || echo unknown)
Tests: not run in this pipeline.
NOTES
)"
fi
gh release upload "$TAG" -R "$REPO" --clobber "$OUT"/*
echo "-> released $TAG to $REPO: $(cd "$OUT" && ls | tr '\n' ' ')" >&2
