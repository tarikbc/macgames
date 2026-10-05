#!/bin/bash
# Downloads the prebuilt MacGames runtime (Wine, DXMT, x87sidecar, with their
# source code and licenses) from this repository's releases into Vendor/.
# Usage: scripts/fetch-runtime.sh [path to a local macgames-runtime-*.tar.xz]
set -euo pipefail

VERSION=3
SHA256=2795c8673a4c052e1a85ce1bd458beba7fad5cceb63f59d74aaf589fcf370816
URL="https://github.com/tarikbc/macgames/releases/download/runtime-$VERSION/macgames-runtime-$VERSION.tar.xz"

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VENDOR="$ROOT/Vendor"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

ARCHIVE="${1:-}"
if [ -z "$ARCHIVE" ]; then
  ARCHIVE="$WORK/runtime.tar.xz"
  echo "Downloading runtime $VERSION (about 130 MB)…"
  curl --fail --location --proto '=https' --proto-redir '=https' --progress-bar -o "$ARCHIVE" "$URL"
fi

echo "Checking the download…"
echo "$SHA256  $ARCHIVE" | shasum -a 256 --check --status || {
  echo "error: the runtime archive does not match the expected SHA-256." >&2; exit 1; }

tar -C "$WORK" -xJf "$ARCHIVE"
SRC="$WORK/macgames-runtime-$VERSION"
(cd "$SRC" && shasum -a 256 --check --quiet SHA256SUMS)
codesign --verify --strict "$SRC/Engine/bin/wine" "$SRC/Engine/bin/wineserver" "$SRC/Helpers/x87sidecar"

rm -rf "$VENDOR.old"
[ -d "$VENDOR" ] && mv "$VENDOR" "$VENDOR.old"
mv "$SRC" "$VENDOR"
rm -rf "$VENDOR.old"
echo "Runtime $VERSION is in $VENDOR."
