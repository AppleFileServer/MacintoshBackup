# Changelog

## 1.0 (candidate)

- Stage 6, packaging: `--self-test`; `tools/make-release.sh`; the release
  notes, BUILDING.md and TESTING.md. Version 1.0. 63 tests.

## 0.1.0 (in development)

- Stage 5, reliability (F1-F6): a 3 GB image backed up, verified and
  restored; the destination filling up mid-copy; a backup interrupted
  with no record ("Interrupted", cleared on request); an interrupted
  restore's temporary file cleared next time (only its own); the card
  vanishing mid-backup; after each, the earlier snapshot verifies byte
  for byte. Fixed: each chunk's memory now released as it goes (a 3 GB
  image had taken 2 GB of memory); free space read correctly on disks
  that aren't APFS (it had read 0). 61 tests.
- Stage 4b, Restore to a New Card (B13): a snapshot onto a new, empty
  card (only macOS's own files on it; never formatted by the app): exFAT
  preferred, FAT32 refused for a 4 GB image, room checked; macOS's files
  and BlueSCSI firmware packages left out (firmware includable); every
  byte written in order under a hidden name, renamed once its read-back
  matches, and the whole card checked afterwards; on a failure only the
  app's own files removed; no `._` files. The new card takes over the old
  one's entry in the register (its name and history; the old UUID kept,
  so the old card turning up is asked about). The sheet: how to format,
  the inserted cards and whether each will do, a confirmation, the
  result, the replacement, Eject. 56 tests, on exFAT and FAT32 disk images.

- Stage 4, recognising the card (C1-C8): disks appearing and going
  (macOS's notifications, and those already there at launch), only
  external removable or ejectable ones; a BlueSCSI card told by its
  `bluescsi.ini`, its log's own text, or its image names, read only;
  the card register (`Catalog/cards.json`): register a card under a
  name, know it again by its volume UUID, ask when only its name, size
  and format match (a reformatted card); one offer per insertion, never
  a backup by itself; a notification when the app is in the background;
  the card removed mid-backup; Eject; a plain message if macOS hasn't
  allowed access. Each snapshot records its card, and thinning keeps
  cards apart. 50 tests, on folders and exFAT and FAT32 disk images.

- Stage 3, the window (W1-W14): the status (with the shut-down reminder
  while waiting for a card), the card and its contents, the history and
  the selected snapshot's manifest; Back Up Now (with its sheet: the
  room needed and free, the warnings), progress and Cancel, the result
  in plain words; Browse Backups, Verify Backup, Restore… (the whole
  snapshot or chosen files, conflicts asked), Open Backup Folder,
  Settings (the backup folder; thinning); Keep (pin) and Delete… (to
  the Trash, warning of a card's last backup); incomplete jobs, Clear….
  W13: disk images not shut down cleanly found and warned of. W14:
  older snapshots thinned after each verified backup (on by default).
  The icon. `tools/build-app.sh`. 45 tests.

- Stage 2, the catalogue and recovery: the catalogue (updated after
  each job; rebuilt from the manifests when lost, damaged or out of
  date, without touching a snapshot; incomplete jobs listed apart from
  restore points); restoring a file, a folder or a whole snapshot (into
  "Restored <name>"), each file checked against the manifest before
  it's put in place, conflicts answered Skip, Keep Both or Replace;
  deleting a snapshot or abandoned work, only confirmed, only the
  repository's own, to the Trash. `mbu list`, `rebuild`, `show`,
  `restore`. 33 tests.

- Stage 1, the backup engine: a source folder inventoried (everything,
  hidden files too, each labelled: disk image, configuration, log,
  firmware, macOS metadata, other); each file copied in 1 MiB chunks,
  hashed (SHA-256) as it's read, runs of zeros left as holes (B14),
  flushed, dated and read back; the source re-checked afterwards (size,
  date, file identifier); a versioned manifest written, read back and
  checked; only then the snapshot named. Anything less stays hidden as
  `.incomplete-<UUID>`, its manifest saying why (inconsistent, failed,
  cancelled). A snapshot verified later against its own manifest,
  reading only. `mbu backup` and `mbu verify`. 18 tests, on generated
  cards only.
- Stage 0: the investigation (SPECIFICATION.md §20.1) and decisions
  B1-B14 (§20.2).
