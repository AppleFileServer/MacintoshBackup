# Changelog

## 0.1.0 (in development)

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
