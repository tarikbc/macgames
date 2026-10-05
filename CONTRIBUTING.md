# Contributing to MacGames

Thank you for helping. MacGames gets better with every Mac it is tested on and every game someone adds.
You do not need to write code to help: a good bug report or a test on a different Mac is just as useful.

## Ways to help

- **Test a game on your Mac** and report what works, with your Mac model and macOS version.
- **Report a bug** with the [bug report form](../../issues/new?template=bug_report.yml).
- **Request a game** with the [game request form](../../issues/new?template=game_request.yml).
- **Add a game profile** or fix something, with a pull request.

## Get set up

You need an Apple Silicon Mac with macOS 26 or later, Xcode 27 and XcodeGen.

```sh
git clone https://github.com/tarikbc/macgames.git
cd macgames
scripts/fetch-runtime.sh   # once: downloads the runtime into Vendor/
xcodegen generate
open MacGames.xcodeproj
```

The core logic has its own test suite, which needs neither Xcode's UI nor the runtime:

```sh
cd Packages/MacGamesCore
swift test
```

Please run it before you open a pull request. Every change to `MacGamesCore` comes with a test.

## How the code is organized

| Path | What lives there |
|---|---|
| `Packages/MacGamesCore/Sources/MacGamesCore` | Everything that touches Wine, Steam and the disk: profiles, paths, environment, setup, launch, status |
| `Packages/MacGamesCore/Sources/BridgeKit`, `MacGamesBridge` | The helper that Wine starts for Age of Empires IV, which decides between x87sidecar and the plain loader |
| `Packages/MacGamesCore/Tests` | Swift Testing suites; they use temporary folders and real processes |
| `App` | The SwiftUI app and the headless `--command` mode |
| `scripts` | Runtime download and packaging, the build phase that embeds it, and the icon renderer |
| `Vendor` (not in git) | The runtime binaries and their source archives, from the release |

A few rules keep the runtime working:

- **Never change a vendored Mach-O file.** `bin/wine` is signed with entitlements, and macOS ignores
  `DYLD_FALLBACK_LIBRARY_PATH` if the signature breaks.
- **`engine/` and `deps/` stay side by side** in the data root. Wine finds its libraries through
  `@loader_path/../../deps/Frameworks`.
- **Steam passes its environment to games.** Anything a game needs must be in the environment Steam
  starts with. See `WineEnvironment.swift` and `SteamLaunch.needsRestart`.

## Adding a game

1. Open a [game request](../../issues/new?template=game_request.yml), so others know you are on it.
2. Add a profile in `GameProfile.swift`:

   ```swift
   public static let mygame = GameProfile(
       id: "mygame", title: "My Game", steamAppID: "123456",
       installFolder: "My Game", executableRelativePath: "bin/MyGame.exe",
       engineOverlays: ["controllers"], graphics: .d3dmetal,
       optimizedExecutableSHA256: nil,
       presentation: Presentation(accentHex: "3A7BD5", heroFocus: .init(x: 0.6, y: 0.4)))
   ```

   Then add it to `GameProfile.all`.
3. Choose the renderer. `.d3dmetal` suits most DirectX 11 and 12 games. `.dxmt` suits DirectX 11
   games that DXMT handles well. If the game needs its own environment values, add them in
   `WineEnvironment.make` behind the profile's ID, with a test in `WineEnvironmentTests`.
4. Set `heroFocus` to the part of the Steam hero art that must stay visible. The app crops around it.
5. Test the full flow on your Mac: setup, install in Steam, play, quit, play again. Say in the pull
   request what you tested and on which Mac.

## Pull requests

- Keep each pull request to one change, and describe what you tested.
- Match the style of the code around your change.
- Do not add dependencies without asking in an issue first.
- Write commit subjects in the imperative mood, for example "Add a profile for My Game".

## License of contributions

MacGames uses the [PolyForm Noncommercial License 1.0.0](LICENSE). By submitting a contribution, you
agree that:

- your contribution is licensed under the same license, and
- you have the right to submit it, and
- the maintainer, Tarik Caramanico, may also license your contribution under other terms, for example to
  give a company a commercial license to MacGames.

Third-party code keeps its own license. Do not add code you cannot license this way.

## Code of conduct

Everyone who takes part follows the [code of conduct](CODE_OF_CONDUCT.md).
