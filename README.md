# Macintosh Backup Utility

A macOS app for the MacMusic project: it backs up the BlueSCSI SD card
of a Macintosh Plus as dated, verified snapshots on your Mac, and
restores them, to a folder or to a new card.

**Status: Stage 6** (`Documentation/SPECIFICATION.md` §16, §20): the
1.0 candidate: backing up, verifying, restoring (to a folder or a new
card), recognising cards; checked on the owner's card (Restore to a New
Card on disk images only, so far).

    tools/build-app.sh && open "build/Macintosh Backup Utility.app"

| Document | |
|---|---|
| `Documentation/SPECIFICATION.md` | the brief; the investigation, decisions and findings (§20) |
| `Documentation/ARCHITECTURE.md` | the parts, the repository's layout and the manifest |
| `Documentation/BUILDING.md` | the environment, the scripts, releasing |
| `Documentation/TESTING.md` | the tests, the self-test, the hardware checks |
| `Documentation/RELEASE-NOTES.md` | for the owner: installing, using, limits |
| `Documentation/CHANGELOG.md` | changes by version |

Copyright © 2026 Jack McAteer. Not affiliated with Apple.
