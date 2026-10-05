#!/bin/bash
# Maintainer tool: builds the overwatch-recall pack from Recall's signed release, byte for byte,
# and gathers the source archives that go next to it in the packs-2 release.
# Usage: scripts/prepare-overwatch-pack.sh [--sources]
#   Writes dist/macgames-pack-overwatch-recall.tar.xz (through scripts/package-pack.sh);
#   with --sources, also dist/overwatch-recall-sources/ with every source archive and SOURCES.md.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WORK="$ROOT/build/recall"
DMG_URL="https://github.com/AsherJN/recall/releases/download/v1.1.0/Recall-1.1.0.dmg"
DMG_SHA="26da5978c1c7a3d665434b46d6abeed7dfb72a8b1efc1bf631b4850f2d2e01b0"
RUNTIME_SHA="a7e85b29d959d8432af32d4763a40eee869edf92f6e15323ecc5450edbdee8ac"

mkdir -p "$WORK"
DMG="$WORK/Recall-1.1.0.dmg"
[ -f "$DMG" ] || curl -fL --retry 3 -o "$DMG" "$DMG_URL"
echo "$DMG_SHA  $DMG" | shasum -a 256 -c -

MOUNT="$WORK/mnt"
mkdir -p "$MOUNT"
hdiutil attach -nobrowse -readonly -mountpoint "$MOUNT" "$DMG" > /dev/null
trap 'hdiutil detach "$MOUNT" > /dev/null 2>&1 || true' EXIT
APP="$MOUNT/Recall.app"
echo "$RUNTIME_SHA  $APP/Contents/Resources/runtime.tar.gz" | shasum -a 256 -c -

PACK="$WORK/overwatch-recall"
rm -rf "$PACK"
mkdir -p "$PACK/Engine" "$PACK/Helpers" "$PACK/Licenses"
tar -xzf "$APP/Contents/Resources/runtime.tar.gz" -C "$PACK/Engine"

# Every file must match Recall's own manifest of the runtime.
python3 - "$PACK/Engine" <<'EOF'
import hashlib, json, os, sys
root = sys.argv[1]
files = json.load(open(os.path.join(root, "runtime.json")))["files"]
for path, entry in files.items():
    data = open(os.path.join(root, path), "rb").read()
    if hashlib.sha256(data).hexdigest() != entry["sha256"] or len(data) != entry["bytes"]:
        sys.exit(f"runtime file differs from runtime.json: {path}")
print(f"runtime.json: {len(files)} files match")
EOF

# The graphics tool and its helpers; they find each other next to themselves.
for helper in ow2-pipeline pipeline-prepare pipeline-warm libpipeline_prepare.dylib; do
  ditto "$APP/Contents/Helpers/$helper" "$PACK/Helpers/$helper"
done
for binary in Engine/bin/wine Engine/bin/wineserver Helpers/ow2-pipeline Helpers/pipeline-prepare Helpers/pipeline-warm; do
  codesign --verify --strict "$PACK/$binary"
done
codesign --verify --strict --deep "$PACK/Engine/lib/wine/game-mode/Overwatch.app"

ditto "$APP/Contents/Resources/Licenses" "$PACK/Licenses/Recall"
cp "$APP/Contents/Resources/PROJECT-LICENSE.txt" "$PACK/Licenses/Recall-LICENSE.txt"
cp "$APP/Contents/Resources/NOTICE.txt" "$PACK/Licenses/Recall-NOTICE.txt"
cat > "$PACK/README.md" <<'EOF'
# overwatch-recall

The engine MacGames uses for Overwatch: the Wine and DXMT runtime of Recall 1.1.0
(https://github.com/AsherJN/recall), byte for byte as Recall ships it, and Recall's graphics
pipeline tool. Recall's own code is under the Apache License 2.0 (Licenses/Recall-LICENSE.txt,
Licenses/Recall-NOTICE.txt). Wine and DXMT are under the LGPL 2.1 or later; every component's
license is in Licenses/Recall and in Engine/licenses.

- Engine/   Recall's runtime.tar.gz, unpacked. Signed by Recall's author; MacGames never changes it.
- Helpers/  ow2-pipeline, pipeline-prepare, pipeline-warm and libpipeline_prepare.dylib from Recall.app.

The corresponding source code of every LGPL and GPL component, with Recall's patches and build
scripts, is published next to this pack in the packs-2 release of
https://github.com/tarikbc/macgames, with a list in SOURCES.md.
EOF

"$ROOT/scripts/package-pack.sh" overwatch-recall "$PACK"

[ "${1:-}" = "--sources" ] || exit 0
SOURCES="$ROOT/dist/overwatch-recall-sources"
mkdir -p "$SOURCES"
fetch() { [ -f "$SOURCES/$1" ] || curl -fL --retry 3 -o "$SOURCES/$1" "$2"; }
fetch crossover-sources-26.3.0.tar.gz https://media.codeweavers.com/pub/crossover/source/crossover-sources-26.3.0.tar.gz
fetch recall-1.1.0-source.tar.gz https://github.com/AsherJN/recall/archive/refs/tags/v1.1.0.tar.gz
fetch dxmt-c5dc3a0d.tar.gz https://github.com/NerRobDog/dxmt/archive/c5dc3a0dfe9108e667da43de871324bd298c9c02.tar.gz
fetch mingw-directx-headers-9df86f23.tar.gz https://github.com/misyltoad/mingw-directx-headers/archive/9df86f2341616ef1888ae59919feaa6d4fad693d.tar.gz
fetch gnutls-3.8.13.tar.xz https://www.gnupg.org/ftp/gcrypt/gnutls/v3.8/gnutls-3.8.13.tar.xz
fetch nettle-3.10.2.tar.gz https://ftp.gnu.org/gnu/nettle/nettle-3.10.2.tar.gz
fetch gmp-6.3.0.tar.xz https://ftp.gnu.org/gnu/gmp/gmp-6.3.0.tar.xz
fetch freetype-2.13.3.tar.gz https://download.savannah.gnu.org/releases/freetype/freetype-2.13.3.tar.gz
fetch wine-mono-10.4.1-src.tar.xz https://github.com/wine-mono/wine-mono/releases/download/wine-mono-10.4.1/wine-mono-10.4.1-src.tar.xz

{
  echo "# Sources of the overwatch-recall pack"
  echo
  echo "The pack holds Recall 1.1.0's runtime unchanged. These archives are the corresponding"
  echo "source of its components, as Recall's docs/SOURCES.json and patches/README.md list them."
  echo
  echo "| File | What it is | SHA-256 |"
  echo "|---|---|---|"
  row() { echo "| $1 | $2 | \`$(shasum -a 256 "$SOURCES/$1" | cut -d' ' -f1)\` |"; }
  row crossover-sources-26.3.0.tar.gz "CodeWeavers' Wine 26.3.0 source (LGPL 2.1+); Recall's Wine patches are in recall-1.1.0-source, patches/"
  row recall-1.1.0-source.tar.gz "Recall 1.1.0 (Apache 2.0): the Wine and DXMT patches, build scripts and the graphics tool's source"
  row dxmt-c5dc3a0d.tar.gz "DXMT, NerRobDog's fork at c5dc3a0d (LGPL 2.1+), before Recall's patches"
  row mingw-directx-headers-9df86f23.tar.gz "DirectX headers DXMT builds with, at 9df86f23"
  row gnutls-3.8.13.tar.xz "GnuTLS 3.8.13 (LGPL 2.1+)"
  row nettle-3.10.2.tar.gz "Nettle 3.10 (LGPL 3+ or GPL 2+); the library reports 3.10, and 3.10.2 is the newest 3.10 release"
  row gmp-6.3.0.tar.xz "GMP 6.3.0 (LGPL 3+ or GPL 2+)"
  row freetype-2.13.3.tar.gz "FreeType 2.13.3 (FreeType License or GPL 2)"
  row wine-mono-10.4.1-src.tar.xz "Wine Mono 10.4.1"
  echo
  echo "libinotify (MIT) and MoltenVK (Apache 2.0) need no source here; their licenses are in the pack."
  echo "Apple's libd3dshared.dylib is under Apple's license, in Engine/licenses/apple."
} > "$SOURCES/SOURCES.md"
ls -la "$SOURCES"
