# Third-party notices

The PolyForm Noncommercial license in [`LICENSE`](LICENSE) covers the MacGames source code in this
repository. It does not change the license of any third-party component. Each component below keeps its
own license, and you may use it under those terms.

## Bundled into MacGames.app at build time

These files are not in the git repository. `scripts/fetch-runtime.sh` downloads them from this
repository's releases into `Vendor/`, and the Xcode build copies them into the app. The release archive
contains the corresponding source code in `Sources/`.

| Component | What it does | License | Source |
|---|---|---|---|
| Wine 11 (from the CrossOver 26.3 open-source release, with patches) | Runs the Windows programs | LGPL 2.1 or later | `Vendor/Sources/wine-source.tar.gz`, license in [`LICENSES/Wine-LGPL.txt`](LICENSES/Wine-LGPL.txt) |
| HDE64 / MinHook parts inside Wine | x86-64 instruction decoding for the patched loader | BSD 2-Clause | [`LICENSES/HDE-LICENSE.txt`](LICENSES/HDE-LICENSE.txt) |
| x87sidecar | Fast x87 math under Rosetta 2 for Age of Empires IV | MIT | `Vendor/Sources/sidecar-source.tar.gz`, [`LICENSES/Sidecar-MIT.txt`](LICENSES/Sidecar-MIT.txt) |
| DXMT (custom build with CS2 early compile) | Direct3D 11 on Metal for Counter-Strike 2 | MIT | `Vendor/Sources/dxmt-cs2-source.tar.gz`, [`LICENSES/DXMT-MIT.txt`](LICENSES/DXMT-MIT.txt) |
| SDL2 (controller support in winebus) | Game controllers | zlib | [`LICENSES/SDL2.txt`](LICENSES/SDL2.txt) |

If you distribute a build of MacGames.app, you must also make the corresponding source of the LGPL and
other components available, as their licenses require. The archives in `Vendor/Sources` are that source.

## Downloaded on your Mac during setup

MacGames does not include or distribute these. It downloads them from their official sources and checks
their SHA-256 hash where the file is stable.

| Component | Source | Terms |
|---|---|---|
| Sikarugir `Template-1.0.15` libraries, including Apple D3DMetal | github.com/Sikarugir-App/Wrapper | Each library's own license; D3DMetal under Apple's Game Porting Toolkit license |
| Steam client installer | cdn.akamai.steamstatic.com | Valve's Steam Subscriber Agreement |
| Game artwork shown in the library | Steam's public store CDN | Owned by each game's publisher |

## Trademarks

Steam is a trademark of Valve Corporation. Age of Empires is a trademark of Microsoft Corporation.
Counter-Strike is a trademark of Valve Corporation. Apple, Mac, Metal and Rosetta are trademarks of
Apple Inc. CrossOver is a trademark of CodeWeavers. MacGames is not affiliated with or endorsed by any of
these companies, or by the makers of Sikarugir, DXMT or x87sidecar.
