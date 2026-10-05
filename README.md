# MacGames

A small macOS launcher that runs **Age of Empires IV** and **Counter-Strike 2** from Steam on Apple Silicon.

It uses a patched Wine 11 (x86_64, under Rosetta 2), Apple's D3DMetal for AoE IV, DXMT for CS2, and the
x87sidecar Rosetta x87 JIT for AoE IV. The runtime binaries come from a prebuilt runtime bundle;
only their open-licensed parts are used (see `LICENSES/`). All launcher code here is new.

## Requirements

- Apple Silicon Mac, macOS 26 or later, Rosetta 2
- Xcode 27 and XcodeGen (`brew install xcodegen`)
- Your own Steam account that owns the game

## Build

```sh
scripts/fetch-runtime.sh   # once: fills Vendor/ (git-ignored, ~540 MB)
xcodegen generate
xcodebuild -project MacGames.xcodeproj -scheme MacGames -configuration Debug -derivedDataPath build/DerivedData build
open build/DerivedData/Build/Products/Debug/MacGames.app
```

Core tests: `cd Packages/MacGamesCore && swift test`.

## How it works

All games share one Steam client in one data root, `~/Library/Application Support/macgames/steam`:

| Path | Contents |
|---|---|
| `deps/Frameworks` | Sikarugir `Template-1.0.15` libraries and D3DMetal, downloaded and SHA-256 checked at setup |
| `engine` | Copy of the vendored Wine engine plus every game's overlays (DXMT, controllers), with links into `deps/Frameworks` |
| `prefix` | The Wine prefix with the shared Steam client and its library |
| `games/<id>` | Per-game settings and caches (CS2 shader and pipeline caches) |
| `logs` | One log per command, plus `steam-session.log` |

Setup runs `wineboot`, sets Windows 10, replaces the prefix's links to your Mac home with empty folders,
installs every game's graphics DLLs (D3DMetal natives in `system32` for AoE IV, `winemetal.dll` for CS2),
enables SDL controllers in winebus, and installs Steam silently.

**Per-game graphics.** Steam passes its environment to the games it starts, and the games need different
renderers: AoE IV loads D3DMetal (`dxgi,d3d11,d3d12,atidxx64=n,b`), CS2 forces the DXMT builtins
(`dxgi,d3d11,d3d10core,d3d12,atidxx64,winemetal=b`). When you press Play and Steam runs with another game's
settings, MacGames restarts Steam first (never while a game runs). Opening Steam never restarts it.

**AoE IV optimization.** With the optimization on, the patched Wine loader re-execs `RelicCardinal.exe`
through `MacGamesBridge`. The bridge checks the game's SHA-256 against the build the fixed-address
optimization was made for (24231237). On a match it runs the game under `x87sidecar --cooperative`;
on any other build it runs the plain Wine loader.

**Adding a game.** Add a `GameProfile` (Steam app ID, install folder, executable, renderer, overlays,
accent color and art focal point). The library, art and setup steps follow from it.

## Headless use

```sh
MacGames.app/Contents/MacOS/MacGames --command <check|setup|steam|install|play|stop|status|reset-display|settings> --game <aoe4|cs2>
```

`settings` takes `--optimized on|off` and `--hud on|off`.

## Licenses

Wine (LGPL 2.1, source in `Vendor/Sources/wine-source.tar.gz`), x87sidecar (MIT), DXMT (MIT), HDE/MinHook (BSD),
SDL2 (zlib). D3DMetal is downloaded at setup under Apple's Game Porting Toolkit license and is not bundled.
