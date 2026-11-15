#!/usr/bin/env bash
#
# Renders an .icns from a square PNG using the macOS toolchain.
# Written for bash 3.2 (the version that ships with macOS).
#
set -euo pipefail

SOURCE="${1:-}"
TARGET="${2:-}"

if [[ -z "$SOURCE" || -z "$TARGET" ]]; then
    printf 'usage: %s <source.png> <target.icns>\n' "$0" >&2
    exit 1
fi

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

ICONSET="$WORK/AppIcon.iconset"
mkdir -p "$ICONSET"

for spec in \
    "icon_16x16.png 16" \
    "icon_16x16@2x.png 32" \
    "icon_32x32.png 32" \
    "icon_32x32@2x.png 64" \
    "icon_128x128.png 128" \
    "icon_128x128@2x.png 256" \
    "icon_256x256.png 256" \
    "icon_256x256@2x.png 512" \
    "icon_512x512.png 512" \
    "icon_512x512@2x.png 1024"
do
    set -- $spec
    sips -z "$2" "$2" "$SOURCE" --out "$ICONSET/$1" >/dev/null
done

iconutil --convert icns --output "$TARGET" "$ICONSET"
