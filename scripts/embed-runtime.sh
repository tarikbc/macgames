#!/bin/bash
# Xcode build phase: copies the vendored runtime and the helpers into MacGames.app.
set -euo pipefail

VENDOR="$SRCROOT/Vendor"
if [ ! -f "$VENDOR/SHA256SUMS" ]; then
  echo "error: Vendor/ is missing. Run scripts/fetch-runtime.sh first." >&2
  exit 1
fi
APP="$TARGET_BUILD_DIR/$WRAPPER_NAME"
RT="$APP/Contents/Resources/Runtime"
HELPERS="$APP/Contents/Helpers"
mkdir -p "$RT" "$HELPERS"

# Byte-for-byte copies: the engine's signatures and entitlements must stay valid.
rsync -a --delete "$VENDOR/Engine/" "$RT/Engine/"
rsync -a --delete "$VENDOR/Overlays/" "$RT/Overlays/"
rsync -a --delete "$VENDOR/Licenses/" "$RT/Licenses/"
cp "$VENDOR/dependency-links.json" "$RT/dependency-links.json"
shasum -a 256 "$VENDOR/SHA256SUMS" | cut -c1-16 > "$RT/VERSION"

ditto "$VENDOR/Helpers/x87sidecar" "$HELPERS/x87sidecar"
ditto "$BUILT_PRODUCTS_DIR/MacGamesBridge" "$HELPERS/MacGamesBridge"
ditto "$BUILT_PRODUCTS_DIR/RosettaProbe" "$HELPERS/RosettaProbe"
