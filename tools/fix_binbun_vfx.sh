#!/usr/bin/env bash
# Makes a fresh copy of the BinbunVFX_Vol2 pack usable from assetlibs/.
#
# The pack's scenes point at res://assets/BinbunVFX_Vol2/ (where it was
# authored) and reference files by UID. This rewrites the paths to
# res://assetlibs/BinbunVFX_Vol2/ and drops the UID hints so Godot resolves
# files by path. Run from the project root after copying the pack in, then
# rescan in the editor. Keep only one copy of the pack in the project:
# duplicate copies share UIDs and confuse Godot.
set -euo pipefail

PACK="assetlibs/BinbunVFX_Vol2"
if [ ! -d "$PACK" ]; then
	echo "No $PACK folder; copy the pack there first." >&2
	exit 1
fi

files=$(grep -rlE 'res://assets/BinbunVFX_Vol2/|^\[ext_resource [^]]*uid="uid://' \
	--include=*.tscn --include=*.tres --include=*.gd --include=*.gdshader --include=*.gdshaderinc "$PACK" || true)
if [ -z "$files" ]; then
	echo "Nothing to fix."
	exit 0
fi
echo "$files" | xargs sed -i -E \
	-e 's|res://assets/BinbunVFX_Vol2/|res://assetlibs/BinbunVFX_Vol2/|g' \
	-e '/^\[ext_resource /s/ uid="uid:\/\/[a-z0-9]+"//'
echo "Fixed $(echo "$files" | wc -l) files."

if [ ! -f "$PACK/shared/script/VFXControllerBB.gd" ]; then
	echo "Warning: $PACK/shared/script/VFXControllerBB.gd is missing; hit and cast effects need it." >&2
fi
