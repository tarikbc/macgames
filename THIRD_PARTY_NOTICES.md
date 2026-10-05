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
| Wine ntdll fix and notch-safe winemac | Engine fixes for several games | LGPL 2.1 or later | Patches in `Vendor/Sources/ntdll-fix` and `Vendor/Sources/aom-notch` |
| cnc-ddraw | DirectDraw for Heroes III and Red Alert 2 | MIT | `Vendor/Sources/cnc-ddraw-ra2-source.tar.gz`, [`LICENSES/cnc-ddraw-MIT.txt`](LICENSES/cnc-ddraw-MIT.txt) |
| Catmull-Rom upscale shader | Red Alert 2 scaling | MIT | License in the file header |
| Sparkle | Signed app updates | MIT | [`LICENSES/Sparkle-MIT.txt`](LICENSES/Sparkle-MIT.txt) |
| MacGames Windows helpers (`WindowsHelpers/`) | Small Windows programs that run next to some games | PolyForm Noncommercial 1.0.0, like MacGames; `prepare-pipelines` also contains DXMT code (MIT, [`LICENSES/DXMT-MIT.txt`](LICENSES/DXMT-MIT.txt)) and the llvm-mingw runtime (Apache 2.0 with LLVM exception) | This repository |
| Witcher 3 FidelityFX proxy | Stops a shader crash in The Witcher 3 | MIT | `Vendor/Sources/witcher3-ffxproxy`, [`LICENSES/Witcher3-FFXProxy-MIT.txt`](LICENSES/Witcher3-FFXProxy-MIT.txt) |

## Website

The site in `docs/` uses the Barlow Condensed typeface, under the SIL Open Font License 1.1
([`docs/assets/fonts/OFL.txt`](docs/assets/fonts/OFL.txt)). Its game covers load from
Steam's public store servers when the page opens; they belong to each game's publisher and are not
part of this repository.

## Release packs, downloaded on first setup of an environment

| Pack | Contents | License |
|---|---|---|
| skyrim | DXMT 0.72 and the ntdll fix | MIT, LGPL 2.1+; source included |
| overwatch | DXMT for Overwatch and the ntdll fix | MIT, LGPL 2.1+; source included |
| battlenet | 32-bit DXMT 0.72 for the Battle.net client and the ntdll fix | MIT, LGPL 2.1+; source included |
| rockstar | Wine kernelbase with the Rockstar CEF patch, WineD3D `d3d11`, `dxgi`, `d3d10core` | LGPL 2.1+; patch included, built from the runtime's Wine source |
| gta5 | Wine 11.13 with patches | LGPL 2.1+; source and patches included |
| apple-d3dmetal-4.0b2 | Apple D3DMetal 4.0b2 Redistributables, unmodified | Apple Game Porting Toolkit license, with Apple's notices |

Apple's license allows the Game Porting Toolkit Redistributables to be distributed separately, only for
non-commercial purposes and for use on Apple-branded systems. MacGames is non-commercial, and these files
keep Apple's license and notices. The gta5 pack also holds copies of those Apple files.

If you distribute a build of MacGames.app, you must also make the corresponding source of the LGPL and
other components available, as their licenses require. The archives in `Vendor/Sources` are that source.

## Downloaded on your Mac during setup

MacGames does not include or distribute these. It downloads them from their official sources and checks
their SHA-256 hash where the file is stable.

| Component | Source | Terms |
|---|---|---|
| Sikarugir `Template-1.0.15` libraries, including Apple D3DMetal | github.com/Sikarugir-App/Wrapper | Each library's own license; D3DMetal under Apple's Game Porting Toolkit license |
| Steam client installer | cdn.akamai.steamstatic.com | Valve's Steam Subscriber Agreement |
| Battle.net installer | battle.net | Blizzard's terms |
| Rockstar Games Launcher | gamedownloads.rockstargames.com | Rockstar's terms |
| Microsoft Visual C++ runtime (Company of Heroes 3) | download.visualstudio.microsoft.com | Microsoft's license |
| .NET 8 runtimes (CnCNet client) | builds.dotnet.microsoft.com | MIT |
| CnCNet Yuri's Revenge client package | github.com/CnCNet | Its own license |
| GeneralsOnline client | cdn.playgenerals.online | Its own terms |
| Game artwork shown in the library | Steam's public store CDN | Owned by each game's publisher |

## Trademarks

Steam is a trademark of Valve Corporation. Age of Empires is a trademark of Microsoft Corporation.
Counter-Strike is a trademark of Valve Corporation. Apple, Mac, Metal and Rosetta are trademarks of
Apple Inc. CrossOver is a trademark of CodeWeavers. MacGames is not affiliated with or endorsed by any of
these companies, or by the makers of Sikarugir, DXMT or x87sidecar.
