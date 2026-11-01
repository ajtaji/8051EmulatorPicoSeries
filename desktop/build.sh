#!/bin/sh
# Builds the desktop 8051 emulator on Linux: mcs51_desktop, the window and the
# console modes (--test, --bench, --frames) in one program - Linux has no
# separate console format. The same source as build.ps1 on Windows.
#   PUREBASIC_HOME   the PureBasic for Linux install (its compilers/pbcompilerc)
#   NEON_ENGINE_DIR  the Neon Arcade Display Engine checkout; by default the one
#                    beside this repository (../../Neon-Arcade-Dispay-Engine/)
set -e
here=$(cd "$(dirname "$0")" && pwd)
: "${PUREBASIC_HOME:?set PUREBASIC_HOME to the PureBasic for Linux install}"
export PUREBASIC_HOME
engine=${NEON_ENGINE_DIR:-$here/../../Neon-Arcade-Dispay-Engine/}
case "$engine" in */) ;; *) engine="$engine/" ;; esac
"$PUREBASIC_HOME/compilers/pbcompilerc" "$here/mcs51_desktop.pb" -t -z -o "$here/mcs51_desktop" -co "GL_ENGINE_DIR\$=$engine"
sha256sum "$here/mcs51_desktop"
