# Releasing MacGames

A release is a Developer ID signed and notarized disk image, a Sparkle update zip, and an
updated feed. `scripts/release.sh` does all of it on a Mac that holds the credentials below.
Nothing secret lives in this repository.

## One-time setup

1. **Developer ID.** Install a "Developer ID Application" certificate in your login keychain.
   The script uses the first one it finds, or the one named in `DEVELOPER_ID`.
2. **Notarization.** Store App Store Connect credentials as a notarytool keychain profile:

   ```sh
   xcrun notarytool store-credentials <profile name> --team-id <your team ID>
   ```

   Pass the profile name as `NOTARY_PROFILE` when you release.
3. **Update signing.** Build the app once, so Swift Package Manager fetches Sparkle, then make
   the MacGames key in your keychain:

   ```sh
   build/DerivedData/SourcePackages/artifacts/sparkle/Sparkle/bin/generate_keys --account macgames
   ```

   It prints the public key, which goes in `project.yml` as `SUPublicEDKey`. Export a backup of
   the private key (`generate_keys --account macgames -x <file>`) and keep it outside the
   repository. Without it, existing installs cannot verify new updates.
4. **GitHub.** Sign in with `gh auth login`, with push rights to the repository.

## Each release

1. Set `MARKETING_VERSION` and raise `CURRENT_PROJECT_VERSION` in `project.yml`.
2. Add a `## <version> - <date>` section to `CHANGELOG.md`, and commit both.
3. Run:

   ```sh
   NOTARY_PROFILE=<profile name> scripts/release.sh <version>
   ```

The script builds the Release app, signs it inside out with the hardened runtime, notarizes and
staples the app and the disk image, signs the update zip for Sparkle, tags `v<version>`, publishes
the GitHub release, and uploads `appcast.xml` to the `appcast` release.

## Rules that keep updates working

- The feed lives in the `appcast` release, at a fixed URL. Never delete that release.
- The Wine runtime and the packs keep the signatures they ship with. The script never re-signs
  them: Wine's entitlements must stay as they are.
- `MacGamesBridge` needs `App/MacGamesBridge.entitlements`. Without it, the hardened runtime
  removes the `DYLD_` variables that Wine needs before the bridge hands them on to x87sidecar.
- Publish runtime and pack releases with `--latest=false`, so the app release stays the latest one.
