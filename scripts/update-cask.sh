#!/usr/bin/env bash
#
# Renders the cask for the tap repository from the template.
#
# usage: update-cask.sh <version> <sha256> <tap-dir> <owner/repo>
#
set -euo pipefail

VERSION="${1:?version}"
SHA256="${2:?sha256}"
TAP_DIR="${3:?tap directory}"
REPO="${4:?owner/repo}"

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

mkdir -p "$TAP_DIR/Casks"
sed \
    -e "s|@@VERSION@@|$VERSION|g" \
    -e "s|@@SHA256@@|$SHA256|g" \
    -e "s|@@REPO@@|$REPO|g" \
    "$ROOT/packaging/homebrew/halalcloud.rb" > "$TAP_DIR/Casks/halalcloud.rb"

printf '==> Wrote %s/Casks/halalcloud.rb\n' "$TAP_DIR"
