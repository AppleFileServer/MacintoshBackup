# Macintosh Backup Utility: architecture

The design (SPECIFICATION.md §20; decisions B1-B14). What's built, stage
by stage, is marked in the CHANGELOG.

## Parts

- **MacintoshBackupKit**, the library, holding everything that can be
  tested without a window or a card:
  - `Inventory`: the source tree as entries (path, kind, size, dates,
    file identifier, category), read without writing;
  - `Category`: what a file is (disk image, BlueSCSI configuration, log,
    firmware package, macOS metadata, other), from its name;
  - `Repository`: the backup folder's layout and its safety checks;
  - `SnapshotWriter`: copy, hash, sparse write, read-back, the source
    re-checked, the manifest, the commit;
  - `Verifier`: a snapshot against its own manifest, read-only;
  - `Manifest`: the versioned JSON (below);
  - `FileCopy`: one file copied, hashed, sparse, read back (backing up and
    restoring alike);
  - `Catalog`: the index, rebuilt from the manifests (Stage 2);
  - `Restorer`: to a folder, checked against the manifest (Stage 2);
  - `Housekeeping`: deleting a snapshot, only confirmed, to the Trash (Stage 2);
  - later stages: recognition, identity, restoring to a new card.
- **mbu**, the developer's command-line tool (Stages 1-2).
- **The app** (Stage 3 on), SwiftUI, a thin layer over the library.

## The repository

    Mac Plus Backups/
      Catalog/catalog.json              the index (Stage 2); rebuilt from the manifests
      Snapshots/
        2026-10-09_17-30-00_7f3a/       a complete, verified snapshot
          SnapshotManifest.json
          Files/...                     the card's root, exactly
        .incomplete-<UUID>/             a job in progress, failed or abandoned
          SnapshotManifest.json         its status and why, if it got that far
          Files/...
      Logs/

A snapshot's folder name is its local start time and the first four hex
digits of its identifier (a UUID); the identifier is the snapshot's true
name. A finished job is moved from `.incomplete-<UUID>` to its name only
when every check has passed and the manifest has been written, read
back and checked; if that name exists already (it can't, short of a
clash of both time and identifier), the move is refused and the job
fails. Only verified snapshots are ever given a name; anything else
stays hidden as `.incomplete-...`, with its manifest saying why.

## The manifest (schema version 1)

    {
      "schemaVersion": 1,
      "snapshotID": "UUID",
      "name": "2026-10-09_17-30-00_7f3a",
      "status": "verified" | "inconsistent" | "failed" | "cancelled",
      "started": "ISO 8601", "finished": "ISO 8601",
      "app": { "name": "Macintosh Backup Utility", "version": "0.1.0" },
      "source": { "path": "/Volumes/BLUESCSI", "volumeName": "...",
                  "volumeUUID": "...", "filesystem": "...", "capacity": 0 },
      "totals": { "files": 0, "folders": 0, "bytes": 0 },
      "entries": [
        { "path": "HD00_512 System.hda", "kind": "file" | "folder" | "link" | "other",
          "size": 0, "sha256": "hex", "modified": "ISO 8601", "created": "ISO 8601",
          "category": "diskImage" | "configuration" | "log" | "firmware" | "macOSMetadata" | "other",
          "result": "verified" | "skipped" | "failed" | "changed", "note": "..." }
      ],
      "warnings": [ "..." ]
    }

Paths are relative to the card's root, with "/" between folders, in
the form the filesystem gives them. Decoding ignores fields it doesn't
know, so a later version's manifests stay readable; a complete
snapshot's manifest is never rewritten.

## Copying a file (B7, B14)

1. Open the source for reading only; open the copy new (it can't
   already exist: the workspace is new).
2. Read 1 MiB at a time: hash every chunk; a chunk of all zeros is
   skipped by seeking (a hole, on APFS); any other is written.
3. Set the copy's length to the source's (so trailing zeros are a hole
   too), flush it to the disk, and give it the source's dates.
4. Read the copy back and hash it: it must match.
5. After every file is copied, re-read each source file's size,
   modification date and file identifier: any change, or a file gone,
   makes the snapshot inconsistent.

What's preserved: every byte, the folder structure, names, and the
modification and creation dates (to FAT's coarser precision). What
isn't: FAT attributes (hidden, system, archive), permissions (FAT has
none), anything else of the card's filesystem.

## The catalogue (Stage 2)

`Catalog/catalog.json` lists every folder in Snapshots that is a
snapshot (a snapshot's name, or `.incomplete-<UUID>`; any other folder
is ignored): its ID, status, dates, files, bytes, the space it takes,
the card's name and UUID, its warnings, and any problem (a manifest
that can't be read, or a folder and manifest that disagree). Only a
named, verified snapshot is a restore point. It's rewritten after every
job, and rebuilt from the manifests (reading them only) whenever it's
missing, can't be read, or doesn't list exactly the folders there.

## Restoring (Stage 2)

Only from a restore point. Each file is copied (as above) to a hidden
`.mbu-restore-<UUID>` beside its place, its SHA-256 compared with the
manifest's, and only then moved into place; a mismatch (the backup
damaged) leaves nothing behind. A file already there is never replaced
without an answer: Skip, Keep Both ("Name 2.ext") or Replace. A whole
snapshot goes into a new folder, "Restored <snapshot name>" (numbered if
taken). macOS's own files and firmware packages can be left out (for
restoring to a card, B13).

## Deleting (Stage 2)

Only when confirmed, only a folder that is one of this repository's
snapshot folders (by name, directly inside Snapshots), and only if its
manifest names the snapshot asked for; it goes to the Trash, so a
mistake can be undone. The window warns when it's a card's last restore
point. Nothing is ever deleted by the app on its own.
