# Security policy

## Reporting a problem

Please do not open a public issue for a security problem. Report it privately through the
**Security** tab of this repository ("Report a vulnerability"). You get an answer within a week.

## What counts

MacGames starts Windows programs, downloads files and runs helpers, so these matter most:

- A way to run code through `MacGamesBridge` or the x87sidecar launch path that a game would not run
  anyway
- A way around the SHA-256 checks on downloads
- A way for the Windows environment to reach files outside its own folder that it should not reach
- Anything that changes files outside `~/Library/Application Support/macgames` and the app itself

Problems in Wine, Steam, DXMT, x87sidecar or a game itself belong to those projects. If you are not
sure, report it here and we will help pass it on.
