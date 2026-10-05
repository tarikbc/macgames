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

Each game gets its own data root in `~/Library/Application Support/macgames/<game>`:

| Path | Contents |
|---|---|
| `deps/Frameworks` | Sikarugir `Template-1.0.15` libraries and D3DMetal, downloaded and SHA-256 checked at setup |
| `engine` | Copy of the vendored Wine engine plus the game's overlays, with links into `deps/Frameworks` |
| `prefix` | The Wine prefix with its own Steam client |
| `logs` | One log per command, plus `steam-session.log` |

Setup runs `wineboot`, sets Windows 10, replaces the prefix's links to your Mac home with empty folders,
installs the graphics DLLs, enables SDL controllers in winebus, and installs Steam silently.

**AoE IV optimization.** With the optimization on, the patched Wine loader re-execs `RelicCardinal.exe`
through `MacGamesBridge`. The bridge checks the game's SHA-256 against the build the fixed-address
optimization was made for (24231237). On a match it runs the game under `x87sidecar --cooperative`;
on any other build it runs the plain Wine loader.

## Headless use

```sh
MacGames.app/Contents/MacOS/MacGames --command <check|setup|steam|install|play|stop|status|reset-display|settings> --game <aoe4|cs2>
```

`settings` takes `--optimized on|off` and `--hud on|off`.

## Licenses

Wine (LGPL 2.1, source in `Vendor/Sources/wine-source.tar.gz`), x87sidecar (MIT), DXMT (MIT), HDE/MinHook (BSD),
SDL2 (zlib). D3DMetal is downloaded at setup under Apple's Game Porting Toolkit license and is not bundled.
