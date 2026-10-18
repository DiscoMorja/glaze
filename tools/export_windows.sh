#!/usr/bin/env bash
# Builds a Windows release of glaze into build/windows/ and zips it for
# sending to a co-op partner. Needs Godot 4.7.2's export templates
# (Editor > Manage Export Templates). Run from the repo root:
#   bash tools/export_windows.sh
set -euo pipefail
GODOT="${GODOT:-/c/Godot/Godot_v4.7.2-stable_win64_console.exe}"
mkdir -p build/windows
"$GODOT" --headless --path . --export-release "Windows Desktop" build/windows/glaze.exe
cp docs/PLAYTEST.md build/windows/HOW_TO_PLAY_TOGETHER.md
( cd build && rm -f glaze-windows.zip && powershell -NoProfile -Command "Compress-Archive -Path windows/* -DestinationPath glaze-windows.zip" )
echo "Built build/windows/glaze.exe and build/glaze-windows.zip"
