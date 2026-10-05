#!/bin/bash
# Maintainer tool: packs Vendor/ into the runtime archive published as a GitHub release.
# Usage: scripts/package-runtime.sh <runtime version, e.g. 1>
set -euo pipefail

VERSION="${1:?usage: scripts/package-runtime.sh <version>}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VENDOR="$ROOT/Vendor"
OUT="$ROOT/dist"
NAME="macgames-runtime-$VERSION"

for part in Engine Overlays Helpers/x87sidecar dependency-links.json Licenses Sources; do
  [ -e "$VENDOR/$part" ] || { echo "error: Vendor/$part is missing" >&2; exit 1; }
done
codesign --verify --strict "$VENDOR/Engine/bin/wine" "$VENDOR/Engine/bin/wineserver" "$VENDOR/Helpers/x87sidecar"

STAGE="$(mktemp -d)/$NAME"
mkdir -p "$STAGE/Helpers"
ditto "$VENDOR/Engine" "$STAGE/Engine"
ditto "$VENDOR/Overlays" "$STAGE/Overlays"
ditto "$VENDOR/Helpers/x87sidecar" "$STAGE/Helpers/x87sidecar"
cp "$VENDOR/dependency-links.json" "$STAGE/"
ditto "$VENDOR/Licenses" "$STAGE/Licenses"
ditto "$VENDOR/Sources" "$STAGE/Sources"
cat > "$STAGE/README.txt" <<NOTE
MacGames runtime $VERSION

Engine/            Wine 11 (built from the CrossOver 26.3 open-source release, with patches), LGPL 2.1+
Overlays/cs2/      DXMT with CS2 early shader compile, MIT
Overlays/controllers/  winebus with SDL2 game controller support, LGPL 2.1+ and zlib
Helpers/x87sidecar Fast x87 math under Rosetta 2, MIT
Sources/           Corresponding source code for Wine, x87sidecar and DXMT
Licenses/          License texts

The Mach-O binaries are signed. Do not modify them, or Wine loses its entitlements.
https://github.com/tarikbc/macgames
NOTE
(cd "$STAGE" && find . -type f ! -name SHA256SUMS -print0 | sort -z | xargs -0 shasum -a 256 > SHA256SUMS)

mkdir -p "$OUT"
tar -C "$(dirname "$STAGE")" --options xz:compression-level=9 -cJf "$OUT/$NAME.tar.xz" "$NAME"
rm -rf "$(dirname "$STAGE")"
shasum -a 256 "$OUT/$NAME.tar.xz" | tee "$OUT/$NAME.tar.xz.sha256"
du -h "$OUT/$NAME.tar.xz"
