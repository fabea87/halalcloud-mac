#!/usr/bin/env bash
#
# Builds dist/HalalCloud.app from the SwiftPM package.
#
# Environment:
#   VERSION       marketing version (default: latest git tag or 0.1.0)
#   BUILD_NUMBER  bundle build number (default: git commit count)
#   BUNDLE_ID     bundle identifier (default: cn.halalcloud.mac)
#   ARCHS         space separated architectures, e.g. "arm64 x86_64"
#   SIGN_IDENTITY codesign identity (default: "-", i.e. ad-hoc)
#
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

APP_NAME="HalalCloud"
BUNDLE_ID="${BUNDLE_ID:-cn.halalcloud.mac}"
CONFIGURATION="${CONFIGURATION:-release}"
ARCHS="${ARCHS:-}"
SIGN_IDENTITY="${SIGN_IDENTITY:--}"

if [[ -z "${VERSION:-}" ]]; then
    VERSION="$(git describe --tags --abbrev=0 2>/dev/null | sed 's/^v//' || true)"
fi
VERSION="${VERSION:-0.1.0}"
if [[ -z "${BUILD_NUMBER:-}" ]]; then
    BUILD_NUMBER="$(git rev-list --count HEAD 2>/dev/null || echo 1)"
fi

BUILD_ARGS=(-c "$CONFIGURATION")
for arch in $ARCHS; do
    BUILD_ARGS+=(--arch "$arch")
done

printf '==> Building %s %s (build %s) [%s%s]\n' \
    "$APP_NAME" "$VERSION" "$BUILD_NUMBER" "$CONFIGURATION" "${ARCHS:+ $ARCHS}"

swift build "${BUILD_ARGS[@]}"

BIN_DIR="$(swift build "${BUILD_ARGS[@]}" --show-bin-path)"
BINARY="$BIN_DIR/$APP_NAME"
if [[ ! -x "$BINARY" ]]; then
    printf 'error: executable not found at %s\n' "$BINARY" >&2
    exit 1
fi

APP="$ROOT/dist/$APP_NAME.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

cp "$BINARY" "$APP/Contents/MacOS/$APP_NAME"

sed \
    -e "s|@VERSION@|$VERSION|g" \
    -e "s|@BUILD@|$BUILD_NUMBER|g" \
    -e "s|@BUNDLE_ID@|$BUNDLE_ID|g" \
    "$ROOT/packaging/Info.plist" > "$APP/Contents/Info.plist"

printf 'APPL????' > "$APP/Contents/PkgInfo"

"$ROOT/scripts/make-icns.sh" "$ROOT/packaging/AppIcon.png" "$APP/Contents/Resources/AppIcon.icns"

# Ad-hoc signing is enough for local use and for the Homebrew cask; set
# SIGN_IDENTITY to a Developer ID to produce a notarizable build.
codesign --force --sign "$SIGN_IDENTITY" "$APP" >/dev/null 2>&1 \
    || codesign --force --sign - "$APP"

printf '==> Built %s\n' "$APP"
