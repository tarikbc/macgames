# Changelog

All notable changes to MacGames are listed here.

## 0.1.4 - 2026-10-31

- Age of Empires IV gets the Rosetta optimization again on its current Steam build (17.0.12182).
  The game update had turned it off, so the game ran on the standard runtime. A game that has not
  updated yet runs without the optimization until Steam updates it. Thanks to @GamBurGer-bit for
  the report
- The optimization's code range now comes with the game's build in MacGames, so the next game
  update needs no new Wine runtime

## 0.1.3 - 2026-10-25

- Age of Empires IV stutters much less. Its x87 math and its software exception handling now run
  together in the Rosetta optimization, where before the exception handling switched the x87 part off.
  Loading a save no longer crashes. Thanks to @DrA1ex
- A HiDPI (Retina) setting on each game's page. It applies to every game in the same Windows
  environment, and Steam or Battle.net restarts to apply it at the next launch. Overwatch keeps it on,
  because its fullscreen canvas needs it
- Age of Wonders 4 is supported, on D3DMetal. MacGames starts the game itself and skips the Paradox
  Launcher, whose window never opens under Wine. The first play installs the game's Windows runtimes,
  and Wine's Retina mode is on for the game alone, so it draws at the display's full size. Thanks to
  @jppittman

## 0.1.2 - 2026-10-22

- Age of Empires IV starts again. The Steam library's engine carried DXMT's `dxgi` and `d3d11` in place
  of D3DMetal's, so the game crashed while it looked for graphics adapters. A Steam library setup
  rebuilds its engine on the next launch, with nothing to do on your side. Thanks to @bgarciaoliveira
- After Play, a Steam game shows as starting until the game itself runs, instead of going back to Play
  while Steam brings it up. MacGames says so when Steam closes first, or when the game has not started
  after 2 minutes

## 0.1.1 - 2026-10-05

- Overwatch runs on the Wine and DXMT of [Recall](https://github.com/AsherJN/recall) 1.1.0 (Apache 2.0),
  with Recall's settings: a fullscreen canvas at the game's resolution, raw mouse input, macOS Game Mode,
  shaders prepared when the game creates them, and learned pipelines built before each session
- Overwatch installs and starts through Battle.net. Play asks Battle.net to start the game. A setup of
  Overwatch from 0.1.0 does not carry over: choose Remove setup for Overwatch, then set it up again
- MacGames keeps the resolution you choose in Overwatch, and lowers it for one launch when it does not fit
  the display
- New installer window art in the app's glass style
- The game page stays centered in a wide window, and paths show your home folder as ~
- A website for MacGames

## 0.1.0 - 2026-10-05

First version.

- Library window with a sidebar for any number of games, Steam artwork, and a header that collapses
  while you scroll
- One-click setup of a shared Windows environment and the official Steam client
- One Steam client for every game, restarted with the right graphics settings before a launch
- Age of Empires IV with Apple D3DMetal and the x87sidecar optimization for build 24231237
- Counter-Strike 2 with DXMT and early shader compilation
- Steam card with your account, live download progress, and open and stop actions
- Headless `--command` mode for scripts and bug reports
- 18 more games: Age of Empires III, Age of Mythology: Retold, Company of Heroes 3, Zero Hour, Red Alert 2,
  Heroes III, Diablo IV, Path of Exile 2, Hogwarts Legacy, The Witcher 3, Elden Ring, Skyrim, Overwatch,
  Diablo IV and Diablo II: Resurrected on Battle.net, Red Dead Redemption 2, San Andreas and GTA V
- Windows environments: a shared Steam library, plus separate environments for games that need them,
  grouped in the sidebar by launcher or publisher
- Release packs for the extra engines and renderers, downloaded on first setup
- Play Online for Zero Hour (GeneralsOnline) and Red Alert 2 (CnCNet)
- Windows helpers of our own: GPU keys and notch-safe fullscreen for Age of Mythology: Retold, the
  driver advisory for GTA V, pipeline preparation for Overwatch, a hidden Battle.net window, and the
  display size for Red Alert 2
- Uninstall for each game, and Remove setup for a group with no installed games
- Signed and notarized disk image, with automatic updates through Sparkle
