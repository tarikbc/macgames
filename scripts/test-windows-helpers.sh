#!/bin/bash
# Runs each Windows helper under MacGames' Wine against small fixture programs.
# Usage: scripts/test-windows-helpers.sh [environment root]
# The environment root (default: the shared steam environment) provides the engine and
# the D3DMetal libraries; the tests run in a fresh, temporary Wine prefix.
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ENV_ROOT="${1:-$HOME/Library/Application Support/macgames/steam}"
OUT="$ROOT/Vendor/WindowsHelpers"
TOOLS="$ROOT/build/toolchain/llvm-mingw-20260922-ucrt-macos-universal/bin"
[ -x "$OUT/show-window.exe" ] || { echo "Run scripts/build-windows-helpers.sh first." >&2; exit 1; }
[ -x "$ENV_ROOT/engine/bin/wine" ] || { echo "No engine in $ENV_ROOT. Set up a game first." >&2; exit 1; }

WORK="$(mktemp -d)"
trap 'WINEPREFIX="$WORK/prefix" "$ENV_ROOT/engine/bin/wineserver" -k 2>/dev/null; rm -rf "$WORK"' EXIT
F="$ENV_ROOT/deps/Frameworks"
export WINEPREFIX="$WORK/prefix" WINEDEBUG=-all WINEMSYNC=1
export DYLD_FALLBACK_LIBRARY_PATH="$F:$F/GStreamer.framework/Versions/1.0/lib:/usr/lib"
export WINEDLLOVERRIDES="winemenubuilder.exe=;mscoree,mshtml="
WINE="$ENV_ROOT/engine/bin/wine"
C="$WINEPREFIX/drive_c/t"

for fixture in fixture-dialog fixture-window; do
  "$TOOLS/x86_64-w64-mingw32-clang" -O2 -municode -static -s "$ROOT/WindowsHelpers/fixtures/$fixture.c" -luser32 -lgdi32 -o "$WORK/$fixture.exe"
done
"$WINE" wineboot --init >/dev/null 2>&1
mkdir -p "$C" && cp "$OUT"/*.exe "$WORK"/fixture-*.exe "$C/"

failures=0
check() { if [ "$2" = "$3" ]; then echo "ok    $1"; else echo "FAIL  $1: expected '$3', got '$2'"; failures=$((failures + 1)); fi; }

mode="$("$WINE" 'C:\t\display-mode.exe' 2>/dev/null | tr -d '\r')"
[[ "$mode" =~ ^[0-9]+\ [0-9]+$ ]] && check "display-mode prints a size ($mode)" ok ok || check "display-mode prints a size" "$mode" "<w> <h>"

"$WINE" 'C:\t\show-window.exe' nothing.exe >/dev/null 2>&1; check "show-window without a window" $? 2

TITLE="Minimum Recommended Hardware Check Failure"
TEXT="Please update your graphics driver."
"$WINE" 'C:\t\fixture-dialog.exe' "$TITLE" "$TEXT" >/dev/null 2>&1 & dialog=$!
sleep 4
"$WINE" 'C:\t\dismiss-dialog.exe' --program fixture-dialog.exe --title "$TITLE" --text "Another message." --wait-seconds 3 >/dev/null 2>&1
kill -0 $dialog 2>/dev/null; check "dismiss-dialog leaves another message alone" $? 0
"$WINE" 'C:\t\dismiss-dialog.exe' --program fixture-dialog.exe --title "$TITLE" --text "  Please update   your graphics driver. " --wait-seconds 20 >/dev/null 2>&1
wait $dialog; check "dismiss-dialog presses OK on the exact dialog" $? 1

"$WINE" 'C:\t\fixture-dialog.exe' "$TITLE" "$TEXT" >/dev/null 2>&1 & dialog=$!
sleep 4
"$WINE" 'C:\t\dismiss-dialog.exe' --program fixture-dialog.exe --title "$TITLE" --text "Another message." --wait-seconds 60 >/dev/null 2>&1 & watcher=$!
sleep 3
kill $dialog 2>/dev/null; wait $dialog 2>/dev/null
for _ in $(seq 20); do kill -0 $watcher 2>/dev/null || break; sleep 0.5; done
kill -0 $watcher 2>/dev/null; check "dismiss-dialog exits when its program exits" $? 1
kill $watcher 2>/dev/null

"$WINE" 'C:\t\show-window.exe' fixture-window.exe >/dev/null 2>&1; check "show-window without the program" $? 2
read -r mw mh <<<"$mode"
"$WINE" 'C:\t\fixture-window.exe' 8 > "$WORK/window.txt" 2>/dev/null & window=$!
sleep 3
"$WINE" 'C:\t\show-window.exe' fixture-window.exe >/dev/null 2>&1; check "show-window raises the program's window" $? 0
"$WINE" 'C:\t\fit-window.exe' --program fixture-window.exe --width "$mw" --height "$mh" --inset 32 --wait-seconds 20 >/dev/null 2>&1
wait $window
check "fit-window moves a fullscreen window below the inset" "$(tr -d '\r' < "$WORK/window.txt")" "0 32 $mw $((mh - 32))"

"$WINE" 'C:\t\gpu-sync.exe' >/dev/null 2>&1; check "gpu-sync finds the DirectX key of the adapter" $? 0
"$WINE" 'C:\t\gpu-sync.exe' --watch nothing.exe --wait-seconds 2 >/dev/null 2>&1; check "gpu-sync --watch gives up on a program that never starts" $? 4

# prepare-pipelines needs the Overwatch build of DXMT that scripts/build-windows-helpers.sh unpacked.
OW="$ROOT/build/dxmt-overwatch/overwatch/Overlays/overwatch/lib/wine"
if [ -d "$OW" ]; then
  mkdir -p "$WORK/ow/recipes" "$WORK/ow/archives" "$WORK/ow/shaders"
  run() { WINEDLLPATH="$OW:$ENV_ROOT/engine/lib/wine" DXMT_OWT_PIPELINE_CACHE="$WORK/ow/archives" \
          "$WINE" 'C:\t\prepare-pipelines.exe' "$WORK/ow/recipes" "$WORK/ow/shaders" 2>/dev/null | tr -d '\r'; }
  run > "$WORK/ow/out.txt"; grep -q '"stage":"complete","done":0,"failed":0' "$WORK/ow/out.txt"; check "prepare-pipelines finds Metal and an empty recipe folder" $? 0
  head -c 3000 /dev/urandom > "$WORK/ow/recipes/0000.recipe"
  run > "$WORK/ow/out.txt"; grep -q '"reason":"invalid-recipe"' "$WORK/ow/out.txt"; check "prepare-pipelines rejects a damaged recipe" $? 0
fi

echo "$failures failure(s)"
exit $((failures > 0))
