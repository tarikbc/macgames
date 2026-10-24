#!/bin/bash
# Build only the patched MIT x87sidecar; never alter the vendored Wine binaries.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ARCHIVE="$ROOT/Vendor/Sources/sidecar-source.tar.gz"
EXPECTED=50ad26b802a590b7c49a121da35ca632bc2676b2fcde40b663805e612d547ff0
[ -f "$ARCHIVE" ] || { echo "Run scripts/fetch-runtime.sh first." >&2; exit 1; }
printf '%s  %s\n' "$EXPECTED" "$ARCHIVE" | shasum -a 256 --check --status || {
  echo "Unexpected sidecar source archive; refusing to apply fixed-build patches." >&2; exit 1;
}
command -v cmake >/dev/null || { echo "Install CMake (brew install cmake)." >&2; exit 1; }
WORK="$ROOT/build/aoe-runtime"
mkdir -p "$WORK"
KEY="$( { shasum -a 256 "$ARCHIVE" "$ROOT"/patches/x87sidecar/*.patch "$0"; xcrun clang++ --version; } | shasum -a 256 | cut -d' ' -f1)"
if [ -f "$WORK/source-key" ] && [ "$(cat "$WORK/source-key")" = "$KEY" ] \
   && [ -s "$WORK/sidecar-source-patched.tar.gz" ] \
   && codesign --verify --strict "$WORK/x87sidecar" 2>/dev/null; then
  printf '%s\n' "$WORK/x87sidecar"
  exit 0
fi
STAGE="$(mktemp -d "$WORK/stage.XXXXXX")"
trap 'rm -rf "$STAGE"' EXIT
tar -xzf "$ARCHIVE" -C "$STAGE"
for patchfile in "$ROOT"/patches/x87sidecar/*.patch; do
  patch --batch --forward -d "$STAGE/x87sidecar" -p1 < "$patchfile" >&2
done
cmake -S "$STAGE/x87sidecar" -B "$STAGE/build" -DCMAKE_BUILD_TYPE=Release -DCMAKE_OSX_ARCHITECTURES=arm64 >&2
cmake --build "$STAGE/build" --target x87sidecar --parallel 6 >&2
codesign --verify --strict "$STAGE/build/bin/x87sidecar"
cp "$STAGE/build/bin/x87sidecar" "$WORK/x87sidecar.new"
mv "$WORK/x87sidecar.new" "$WORK/x87sidecar"
# Preserve corresponding patched sources next to the artifact for redistribution.
tar -czf "$WORK/sidecar-source-patched.tar.gz" -C "$STAGE" x87sidecar
printf '%s\n' "$KEY" > "$WORK/source-key"
printf '%s\n' "$WORK/x87sidecar"
