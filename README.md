# Macintosh Backup Utility

A macOS app for the MacMusic project: it backs up the BlueSCSI SD card
of a Macintosh Plus as dated, verified snapshots on your Mac, and
restores them, to a folder or to a new card.

**Status: Stage 3** (`Documentation/SPECIFICATION.md` §16, §20): the
backup engine, the catalogue, restoring to a folder, and the window,
tested on generated folders only. No real card has been read.

    tools/build-app.sh && open "build/Macintosh Backup Utility.app"

| Document | |
|---|---|
| `Documentation/SPECIFICATION.md` | the brief; the investigation, decisions and findings (§20) |
| `Documentation/ARCHITECTURE.md` | the parts, the repository's layout and the manifest |
| `Documentation/CHANGELOG.md` | changes by version |

Copyright © 2026 Jack McAteer. Not affiliated with Apple.
