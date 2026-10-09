# Macintosh Backup Utility 1.0

A Mac app that keeps dated, verified backups of a Macintosh Plus's
BlueSCSI SD card on your Mac, rather as Time Machine does for a Mac, and
restores them: a file, a disk image, or the whole card, to a folder or
onto a new card.

## Installing

Unzip `Macintosh-Backup-Utility-1.0.zip` and drag **Macintosh Backup
Utility** to Applications. It needs an Apple silicon Mac with macOS 26;
nothing else.

It's signed ad hoc, for its owner's own use; not notarised. If macOS
won't open it the first time, open System Settings, click Privacy &
Security, and click Open Anyway beside its name. The first time it
reads a card, macOS asks you to allow access to removable volumes.

## Backing up

1. Shut the Macintosh Plus down with Shut Down in the Special menu, and
   switch it off when it says you may. (Losing power while the Plus is
   using the card can damage its disks.)
2. Take the card out and insert it into your Mac. The app recognises a
   BlueSCSI card by its `bluescsi.ini`, its log or its disk images, and
   asks to register it the first time ("Mac Plus BlueSCSI").
3. Click **Back Up Now**, check the summary, and click **Back Up**.
   Nothing is ever written to the card. Every file is read, copied and
   checked (SHA-256); only a fully checked backup becomes a snapshot.
4. Click **Eject**, and put the card back before you switch the Plus on.

Snapshots are kept in `~/Mac Plus Backups` (another folder can be chosen
in Settings), each a complete, independent copy with its own manifest.
Older ones are thinned after each backup: a card's newest snapshot of
each day for a week, of each week for a month, of each month for a year,
always at least two, never one marked **Keep** (Settings can turn this
off). Removed snapshots go to the Trash.

A disk image that wasn't shut down cleanly (after a power cut, say) is
flagged before the backup and in the history: an earlier snapshot may be
the better one to restore.

## Restoring

- **To a folder:** select a snapshot, **Restore…**: the whole snapshot,
  or chosen files and disk images; anything already there is asked about
  (Skip, Keep Both, Replace). Each file is checked against the backup.
- **To a new card:** **Restore to a New Card…** in a snapshot's menu.
  Format a card as exFAT first (Disk Utility: Erase, ExFAT, Master Boot
  Record); the app writes only to an empty card, never formats one, and
  checks every file afterwards. It can then take over the old card's name
  and history.

## Checked

On the owner's Mac and Macintosh Plus (System 6.0.7, a BlueSCSI with a
15.5 GB FAT32 card holding six disk images): recognising and registering
the card, backing it up (2.26 GB, every file verified), ejecting and
recognising it again, and restoring to folders. Restore to a New Card is
verified on exFAT and FAT32 disk images only, so far. 63 automated tests.

## Known limits

- It backs up the card's files, not the card itself: not its partition
  table, free space or deleted files.
- Each snapshot is a full copy; only never-used (zero) space inside a
  disk image is left out, so a card of 2 GB of images takes about 2 GB
  per snapshot.
- macOS itself adds hidden files to any card it mounts; BlueSCSI ignores
  them, and they're backed up, labelled, but never restored to a new card.
