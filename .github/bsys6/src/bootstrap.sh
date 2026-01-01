#!/usr/bin/env bash
# SPDX-License-Identifier: MPL-2.0
# Bootstrap the Mozilla build system
set -eu

source $BSYS6/source.sh

echo "-> Bootstrapping the build system with mach" >&2
(cd $SOURCE && ./mach --no-interactive bootstrap --application-choice=browser)
