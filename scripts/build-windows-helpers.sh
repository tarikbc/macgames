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

cp "$ROOT/LICENSE" "$OUT/LICENSE.txt"
