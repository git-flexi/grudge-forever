#!/usr/bin/env bash
# Builds dist/GrudgeForever-<version>.zip (top-level folder GrudgeForever/) from the repo.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TOC="$ROOT/GrudgeForever.toc"

VERSION="$(sed -n 's/^## Version:[[:space:]]*//p' "$TOC" | head -n 1 | tr -d '\r')"
if [ -z "$VERSION" ]; then
  echo "package: no '## Version:' line in $TOC" >&2
  exit 1
fi

DIST="$ROOT/dist"
ZIP="$DIST/GrudgeForever-$VERSION.zip"
mkdir -p "$DIST"

TMP="$(mktemp -d "$DIST/build.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

mkdir "$TMP/GrudgeForever"
rsync -a \
  --exclude='/tests' \
  --exclude='/docs' \
  --exclude='/scripts' \
  --exclude='/Makefile' \
  --exclude='/.busted' \
  --exclude='/.luacheckrc' \
  --exclude='/.pkgmeta' \
  --exclude='/.superpowers' \
  --exclude='/dist' \
  --exclude='/.gitignore' \
  --exclude='.git' \
  --exclude='.DS_Store' \
  "$ROOT/" "$TMP/GrudgeForever/"

rm -f "$ZIP"
(cd "$TMP" && zip -qr "$ZIP" GrudgeForever)

echo "package: $ZIP"
