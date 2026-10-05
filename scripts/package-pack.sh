#!/bin/bash
# Maintainer tool: packs a prepared folder into a release pack that GameRuntime
# downloads on first setup of an environment.
# Usage: scripts/package-pack.sh <name> <folder containing the pack's files>
set -euo pipefail

NAME="${1:?usage: scripts/package-pack.sh <name> <folder>}"
SRC="${2:?usage: scripts/package-pack.sh <name> <folder>}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$ROOT/dist"
STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT

ditto "$SRC" "$STAGE/$NAME"
(cd "$STAGE/$NAME" && find . -type f ! -name SHA256SUMS -print0 | sort -z | xargs -0 shasum -a 256 > SHA256SUMS)
mkdir -p "$OUT"
tar -C "$STAGE" --options xz:compression-level=9,xz:threads=0 -cJf "$OUT/macgames-pack-$NAME.tar.xz" "$NAME"
shasum -a 256 "$OUT/macgames-pack-$NAME.tar.xz" | tee "$OUT/macgames-pack-$NAME.tar.xz.sha256"
