# Changelog

All notable changes to MacGames are listed here.

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
