#!/usr/bin/env bash
# Builds native Linux and Windows 11 releases from Linux Mint.
# Needs Godot 4.7+ and its export templates (Editor > Manage Export Templates > Download).
# Usage:  ./export.sh            (uses `godot` on PATH)
#         GODOT=~/Apps/Godot_v4.7.2-stable_linux.x86_64 ./export.sh
set -euo pipefail
cd "$(dirname "$0")"
GODOT="${GODOT:-godot}"

mkdir -p build/linux build/windows
"$GODOT" --headless --path . --import
"$GODOT" --headless --path . --export-release "Linux" build/linux/BarrelsOfSilver.x86_64
"$GODOT" --headless --path . --export-release "Windows Desktop" build/windows/BarrelsOfSilver.exe
echo "Done: build/linux/BarrelsOfSilver.x86_64 and build/windows/BarrelsOfSilver.exe"
