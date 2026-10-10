# Testing the Macintosh Backup Utility

## Automated (tools/test.sh)

63 tests (Swift Testing), on generated cards and disk images only, never
a real card. By suite:

| Suite | What |
|---|---|
| BackupTests | everything backed up byte for byte; sparse copies; a changed, unreadable or vanished file; cancelling; too little room |
| VerifierTests | a changed byte, a missing or unexpected file, a damaged manifest, a later schema |
| CatalogTests | the catalogue rebuilt when lost, damaged or out of date, without touching a snapshot |
| RestoreTests | whole and partial restores, conflicts, a damaged backup, incomplete snapshots |
| HousekeepingTests | deleting only the confirmed, matching, own snapshot |
| CleanShutdownTests | the "unmounted cleanly" mark, on hand-made images and an `hformat` disk |
| RetentionTests | thinning over 420 days, the minimum of two, pins, the newest, clean preferred |
| CardTests | evidence, the register, the watcher, thinning per card, exFAT and FAT32 mounts |
| NewCardTests | the checks, restoring onto exFAT and FAT32 images, refusals, the replacement |
| ReliabilityTests | a 3 GB image and memory, a full destination, interruptions, a vanished card |
| PreferencesTests, SelfTestTests | settings remembered; the self-test passes and leaves nothing |

On this Mac, `hdiutil create` works from the test runner but not from
the shell, so test disk images are made only inside the tests.

## The self-test

`Macintosh Backup Utility.app/Contents/MacOS/MacintoshBackup --self-test`:
no window; a small card in a temporary folder backed up, verified,
restored and compared, then removed. The release script runs it on a
copy outside the repository.

## With the owner's hardware

- **The real card** (Stage 4, 2026-10-09): recognised, registered,
  backed up, verified, ejected, recognised again, restored to folders;
  every image marked as cleanly put away (SPECIFICATION.md §20.7).
- **Restore to a New Card on a spare card:** to do (the steps:
  SPECIFICATION.md §20.8).

## Jobs for later

- **Waiting for a spare SD card** (logged 2026-10-10: the owner hasn't
  one to hand): test Restore to a New Card on it (SPECIFICATION.md
  §20.8). Then: record the result in the release notes' "Checked", tag
  `v1.0`, run `tools/make-release.sh --bundle`, and add the utility to
  MacMusic's environment archive. Until then, the 1.0 candidate
  (`~/MacPlusProjects/releases/Macintosh-Backup-Utility-1.0`, from
  c18515c) stands, with Restore to a New Card verified on disk images.
