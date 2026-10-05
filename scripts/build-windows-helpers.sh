#!/bin/bash
# Builds the Windows helpers in WindowsHelpers/ into Vendor/WindowsHelpers with llvm-mingw.
# The toolchain is downloaded once into build/toolchain and checked against its pin.
# Maintainers run this before scripts/package-runtime.sh; everyone else gets the
# helpers from the runtime release through scripts/fetch-runtime.sh.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
RELEASE="20260922"
NAME="llvm-mingw-$RELEASE-ucrt-macos-universal"
SHA256="52e5f5a7b131021d0c39a37a38fa380a1da7885cd04bd61afd0cd4ecfb8bc1f3"
TOOLS="$ROOT/build/toolchain"
OUT="$ROOT/Vendor/WindowsHelpers"

if [ ! -x "$TOOLS/$NAME/bin/x86_64-w64-mingw32-clang" ]; then
  mkdir -p "$TOOLS"
  curl -fL --retry 3 -o "$TOOLS/llvm-mingw.tar.xz" \
    "https://github.com/mstorsjo/llvm-mingw/releases/download/$RELEASE/$NAME.tar.xz"
  echo "$SHA256  $TOOLS/llvm-mingw.tar.xz" | shasum -a 256 -c -
  tar -xJf "$TOOLS/llvm-mingw.tar.xz" -C "$TOOLS"
  rm "$TOOLS/llvm-mingw.tar.xz"
fi
CC="$TOOLS/$NAME/bin/x86_64-w64-mingw32-clang"

mkdir -p "$OUT"
FLAGS=(-O2 -Wall -Wextra -Werror -municode -static -s)
build() { local name="$1"; shift; "$CC" "${FLAGS[@]}" "$ROOT/WindowsHelpers/$name.c" "$@" -o "$OUT/$name.exe"; echo "built $name.exe"; }
build show-window -luser32
build display-mode -luser32
build dismiss-dialog -luser32
build fit-window -luser32
build gpu-sync -luser32 -ladvapi32 -ldxgi -ldxguid

# prepare-pipelines builds on DXMT's Overwatch code (MIT), from the overwatch pack's
# Sources, and links against that pack's winemetal.dll.
PACK_SHA256="b987bf1540b66b09369ec95124a09df066050db21f5a7a6f0376978241e91c37"
DXMT="$ROOT/build/dxmt-overwatch"
if [ ! -f "$DXMT/source/src/d3d11/owt_recipe.hpp" ]; then
  mkdir -p "$DXMT"
  curl -fL --retry 3 -o "$DXMT/pack.tar.xz" \
    "https://github.com/tarikbc/macgames/releases/download/packs-1/macgames-pack-overwatch.tar.xz"
  echo "$PACK_SHA256  $DXMT/pack.tar.xz" | shasum -a 256 -c -
  tar -xJf "$DXMT/pack.tar.xz" -C "$DXMT"
  tar -xzf "$DXMT/overwatch/Sources/dxmt-overwatch-source.tar.gz" -C "$DXMT"
  rm "$DXMT/pack.tar.xz"
fi
BIN="$TOOLS/$NAME/bin"
WINEMETAL="$DXMT/overwatch/Overlays/overwatch/lib/wine/x86_64-windows/winemetal.dll"
{ echo "LIBRARY winemetal.dll"; echo "EXPORTS"
  "$BIN/llvm-objdump" -p "$WINEMETAL" | sed -n '/Ordinal      RVA  Name/,/^$/p' | awk 'NF == 3 { print $3 }'
} > "$DXMT/winemetal.def"
"$BIN/llvm-dlltool" -m i386:x86-64 -d "$DXMT/winemetal.def" -l "$DXMT/libwinemetal.a"
S="$DXMT/source"
"$BIN/x86_64-w64-mingw32-clang" -O2 -c "$S/src/util/sha1/sha1.c" -o "$DXMT/sha1.o"
"$BIN/x86_64-w64-mingw32-clang++" -O2 -std=c++20 -municode -static -s -DNOMINMAX -Wno-everything \
  -I"$S/include" -I"$S/src/winemetal" -I"$S/src/util" -I"$S/src/d3d11" -I"$S/src/dxmt" \
  "$ROOT/WindowsHelpers/prepare-pipelines.cpp" "$S/src/util/util_env.cpp" "$S/src/util/util_string.cpp" \
  "$S/src/util/log/log.cpp" "$S/src/util/sha1/sha1_util.cpp" "$DXMT/sha1.o" \
  -L"$DXMT" -lwinemetal -luser32 -lshell32 -lole32 -o "$OUT/prepare-pipelines.exe"
echo "built prepare-pipelines.exe"
cp "$S/LICENSE" "$OUT/DXMT-LICENSE.txt"
cp "$ROOT/LICENSE" "$OUT/LICENSE.txt"
