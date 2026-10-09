# Building the Macintosh Backup Utility

## What it needs

- An Apple silicon Mac with macOS 26 and Xcode 26 (Swift 6.3).
- Nothing else: no third-party code or tools. SHA-256 comes from
  CryptoKit; the volume details from DiskArbitration.

On this Mac, `xcrun` doesn't find the SDK by itself, so the scripts name
it: `SDKROOT=$(xcrun --sdk macosx --show-sdk-path)`.

## The scripts

    tools/test.sh           the tests (swift test)
    tools/build-app.sh      build/Macintosh Backup Utility.app, signed ad hoc
    tools/make-icon.sh      Resources/AppIcon.icns from Resources/Icon/AppIcon.svg
                            (needs headless Chrome; only when the icon changes)
    tools/make-release.sh   a release, from committed source (see TESTING.md)

`mbu` (`swift run mbu ...`) is the developer's command-line tool: backup,
verify, list, rebuild, show, restore.

## Releasing

1. Commit everything; set the version in
   `Sources/MacintoshBackupKit/Version.swift`.
2. `tools/make-release.sh`: tests, build, self-test on a copy outside the
   repository, then the release in `~/MacPlusProjects/releases/`.
3. After the owner's acceptance: `git tag v<version>`, then
   `tools/make-release.sh --bundle` to put the tag in the source bundle.
