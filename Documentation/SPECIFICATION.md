# Macintosh Backup Utility: specification

§1–§19 are the owner's brief, as given on 2026-10-09, unedited (it
calls the app "Mac Plus Backup"; B1 named it the Macintosh Backup
Utility). §20 records the investigation, the decisions and what each
stage found.

---

# Mac Plus Backup — Software Development Specification

**Project:** Mac Plus Backup
**Platform:** Native macOS on Apple Silicon
**Primary computer:** MacBook Neo
**Source:** BlueSCSI SD card used by a physical Macintosh Plus
**Target vintage system:** Macintosh Plus running System 6.0.8
**Initial release:** Full, verified, dated backups with removable-card detection

## 1. Project purpose

Develop a native macOS application called **Mac Plus Backup** that protects the contents of the BlueSCSI SD card used by my Macintosh Plus.

The app should provide a simple, dependable backup history inspired by Apple Time Machine, but designed specifically around BlueSCSI disk-image files and configuration.

The first version must:

1. Detect when a potential BlueSCSI SD card is mounted on macOS.
2. Identify the card and present a clear option to back it up.
3. Copy all filesystem-visible files and directories from the card to a dedicated backup folder on the MacBook Neo.
4. Create a new, dated, independent snapshot for each successful backup.
5. Verify the backup against the source using file sizes and checksums.
6. Maintain an inventory and history of completed snapshots.
7. Allow the user to inspect previous snapshots and restore individual files or a complete snapshot.
8. Protect existing backups and source data from accidental deletion or overwriting.

The first version should prioritise correctness, data safety and understandable behaviour over advanced features.

Do not implement block-level deduplication, automatic backup deletion, remote storage or raw SD-card imaging in the initial release.

---

## 2. BlueSCSI-specific requirements

Before implementation, inspect the current official BlueSCSI documentation:

* Usage: https://bluescsi.com/docs/Usage
* Main documentation: https://bluescsi.com/docs/
* SD card guidance: https://bluescsi.com/docs/SD-Cards
* Configuration: https://bluescsi.com/docs/bluescsi.ini

The current documented conventions include:

* Disk images normally reside in the root directory of an exFAT or FAT32 SD card.
* BlueSCSI image filenames encode device type and may encode SCSI ID, logical unit number and sector size.
* The image filename limit is 64 characters.
* A card can contain multiple image files, and configuration and log files are stored alongside them.

Treat these as implementation requirements to verify against the current documentation, not as reasons to assume every removable SD card is a BlueSCSI card.

### Backup scope

Back up all files and directories accessible through the mounted SD-card filesystem, including:

* All `.hda` hard disk images.
* Other supported disk-image formats.
* `bluescsi.ini`, if present.
* `log.txt`, if present.
* Other configuration files.
* Any other files and directories present on the card, including hidden files that are accessible through the filesystem.

Do not filter by file extension or back up only recognised disk images.

Do not modify the source card during backup.

### Important distinction

The initial product backs up the filesystem-visible contents of the SD card. It is not a sector-by-sector clone of the entire physical SD card.

This means it does not necessarily preserve filesystem metadata, unused sectors, deleted files or the SD card's partition table. Document this limitation clearly.

If full physical-card imaging is considered in a later version, design it as a separate, explicitly selected feature with separate safety requirements.

---

## 3. Application identity and user experience

Build a native SwiftUI application for Apple Silicon macOS, using AppKit integration where needed for removable-volume detection.

The interface should be calm, practical and easy to understand. It should resemble a small, reliable backup utility rather than a complex system-administration tool.

### Main window

Provide these principal areas:

**A. Backup status**

Display:

* Current status: waiting for a card, card detected, awaiting confirmation, backing up, verifying, complete or failed.
* Name of the detected volume.
* Available source capacity and used space where available.
* Last successful backup date.
* Most recent backup result.

**B. Source card**

Display:

* Volume name.
* Mount location.
* Filesystem type, when available.
* Total file count and total source size after scanning.
* Recognised BlueSCSI image files.
* Relevant configuration files.
* Warnings about unexpected or unreadable files.

Do not infer that a card is definitely a BlueSCSI card from its volume name alone.

**C. Backup history**

Display previous snapshots with:

* Date and time.
* Snapshot name.
* Source card identity.
* File count.
* Total stored size.
* Verification status.
* Any warnings or errors.

Allow the user to select a snapshot and inspect its manifest.

**D. Main actions**

Include:

* Back Up Now.
* Browse Backups.
* Verify Backup.
* Restore.
* Open Backup Folder.
* Settings.

The app must remain responsive during scanning, copying, hashing and verification.

---

## 4. Removable-card detection

Use native macOS volume-mount notifications, such as `NSWorkspace.didMountNotification`, with appropriate handling for already-mounted volumes when the application launches.

Investigate the correct implementation for the deployment target and modern macOS versions.

### Detection workflow

When a new volume is mounted:

1. Obtain its mounted URL and available volume metadata.
2. Determine whether it is a removable volume or otherwise a plausible SD-card source.
3. Inspect its accessible root directory without modifying it.
4. Check for evidence consistent with BlueSCSI use, such as disk-image filenames, BlueSCSI configuration or logs.
5. Match the volume against previously recognised cards where possible.
6. Present a notification or in-app prompt offering to back it up.

Do not automatically begin copying when a volume is mounted.

Do not interrupt the user with repeated prompts for unrelated USB drives, camera cards or other removable media.

### Card identification

Design a source-card identity model that uses the most reliable available metadata, potentially including:

* Volume UUID or filesystem identifier.
* Volume name.
* Device characteristics.
* A user-assigned label.
* Other stable metadata supported by macOS.

No single property should be assumed universally available or immutable.

Where reliable identification is impossible, ask the user to confirm the source rather than silently treating it as a known card.

Allow the user to register a card as a recognised BlueSCSI backup source and give it a friendly name, such as `Mac Plus BlueSCSI`.

Support multiple recognised cards in the data model, even if the initial interface is optimised for one card.

### Permissions and privacy

Use normal macOS file-access permissions. If the app needs persistent access to the backup destination or source folder, implement appropriate security-scoped bookmarks or other supported mechanisms.

Do not request administrator privileges unless a separately approved feature genuinely requires them.

Do not scan unrelated personal directories or external drives unnecessarily.

---

## 5. Backup destination and directory layout

The default destination should be a dedicated folder inside the user's home directory on the MacBook Neo.

Use a clear default such as:

`~/Mac Plus Backups/`

Allow the user to select another folder through a native directory picker.

Store backup data in a predictable layout similar to:

* `Mac Plus Backups/`

  * `Catalog/`
  * `Snapshots/`

    * `2026-10-09_12-30-00/`

      * `SnapshotManifest.json`
      * `Files/`

        * all files and directories copied from the SD-card root
    * `2026-10-10_09-15-00/`

      * `SnapshotManifest.json`
      * `Files/`

        * all files and directories copied from the SD-card root
  * `Logs/`

This is an illustrative layout. Refine it during architecture design, but keep the result documented and stable.

The actual snapshot name must be unique. Use a stable internal snapshot identifier in addition to a human-readable date and time.

Do not rely on timestamps alone to guarantee uniqueness.

### Snapshot immutability

Once a snapshot is verified and marked complete, treat it as immutable.

Never modify an earlier snapshot to make room for a new one.

A new backup always creates a new snapshot. It must not overwrite a previous backup merely because the same SD card is being backed up again.

Incomplete snapshots must be clearly marked as incomplete or failed and must never be presented as verified restore points.

---

## 6. Full-copy snapshot model

Version 1 uses full independent copies.

Each snapshot contains a complete copy of every accessible file and directory found on the source card during that backup.

Do not implement deduplication, hard-link sharing or dependency on previous snapshots in version 1.

A snapshot must be independently recoverable even if other snapshots are missing or damaged.

### Backup process

Implement a staged workflow:

1. Identify and validate the source volume.
2. Check that the destination is available and writable.
3. Enumerate the entire source tree.
4. Build a source inventory.
5. Estimate the required backup storage.
6. Check for unreadable files, symlinks, unsupported filesystem objects and other hazards.
7. Ask for confirmation if significant warnings exist.
8. Create a new temporary snapshot workspace.
9. Copy the complete directory tree.
10. Record file sizes and checksums.
11. Verify the copied files against the source inventory.
12. Confirm that no expected files are missing and no unexplained changes occurred during the operation.
13. Write and validate the final manifest.
14. Mark the snapshot complete and verified.
15. Update the backup catalogue and report the result.

Use a safe commit strategy: a snapshot should only become a normal, completed restore point after all required checks pass.

If a backup fails, preserve useful diagnostic information and mark the snapshot incomplete. Offer safe cleanup of abandoned temporary data without touching prior snapshots.

### Storage estimates

Estimate the required space using the total size of the files being copied, plus filesystem and metadata overhead.

The estimate must be a practical guide, not a guarantee. Check available destination space before starting and handle a destination that runs out of space during copying.

If the source is larger than available destination space, explain the problem before beginning.

---

## 7. Integrity verification

Verification is a core feature, not an optional extra.

Use a well-supported cryptographic checksum such as SHA-256 for each file.

The manifest should record enough information to identify and verify every backed-up file.

For each file, record as applicable:

* Relative path.
* File size in bytes.
* SHA-256 checksum.
* File type or category, if useful.
* Relevant timestamps.
* Whether the file was copied and verified successfully.

Use relative paths within the snapshot rather than absolute source paths as the authoritative file identity.

### Verification rules

After copying each file, verify its destination size and checksum against the source.

Do not mark a snapshot as verified if:

* A file is missing.
* A checksum differs.
* A file could not be read.
* A copy was incomplete.
* The source changed during the backup.
* The manifest is invalid or incomplete.

For very large disk images, calculate checksums incrementally in chunks rather than loading entire files into memory.

The app should also support verifying an existing snapshot at a later date against its manifest.

A later verification must not alter the snapshot.

If a file has changed or become unreadable, report the exact path and the type of failure.

### Metadata limitations

macOS and exFAT/FAT32 do not necessarily preserve all metadata in the same way. Document which file attributes are preserved and which are not.

The primary integrity guarantee is that the bytes of each file are copied correctly, not that every source filesystem attribute can be reproduced.

---

## 8. Consistency and source safety

The Macintosh Plus and BlueSCSI use the disk images as working storage. The images may change while the vintage Mac is running.

A file-by-file copy of a disk image that is actively being modified is not guaranteed to represent a consistent point in time.

### Initial safety policy

For version 1, use a manual, safe workflow:

1. The user shuts down the Macintosh Plus cleanly.
2. The user removes the SD card and inserts it into the MacBook Neo.
3. Mac Plus Backup detects the mounted card.
4. The user confirms that the card is ready to back up.
5. The app scans, copies and verifies the files.
6. The user ejects the card safely through macOS before returning it to the BlueSCSI.

The application must not claim it can independently determine whether the vintage computer is actively using the card merely because the card has been mounted on the MacBook.

The confirmation prompt should explain that the Macintosh Plus must no longer be using the card.

### Change detection

Record the source inventory before copying.

Where possible, compare source file sizes, modification metadata and other available information after copying to identify changes during the operation.

Do not treat timestamps alone as proof that a file has remained unchanged.

If a source file changes or disappears during backup, mark the operation as failed or inconsistent and do not claim that the snapshot is a verified restore point.

Avoid holding the entire source inventory in memory if the card contains many large files.

### Read-only behaviour

The backup process must not write to the source card, change BlueSCSI configuration, rename images or alter source files.

Do not automatically eject the card while copying is in progress.

After a successful backup, show instructions for safely ejecting the card.

---

## 9. Manifest and catalogue design

Use a versioned, machine-readable manifest, such as JSON.

The manifest should contain:

* Manifest schema version.
* Snapshot identifier.
* Snapshot creation time.
* Completion and verification status.
* Source-card identity and recorded volume metadata.
* Backup application version.
* File count.
* Total size.
* Relative path of each file.
* File size and checksum.
* Any relevant warnings or omissions.

Design the schema so that future versions can add fields without invalidating older snapshots.

Use a separate catalogue to index available snapshots for quick browsing.

The catalogue must not be the only record of what a snapshot contains. Each snapshot must contain its own manifest so that it can be inspected and recovered even if the central catalogue is lost.

If the catalogue is damaged, provide a recovery or rebuild operation that discovers snapshot manifests and reconstructs the index without modifying snapshot contents.

Do not execute code or open files automatically based on manifest contents. Treat metadata read from a backup as data, not as trusted instructions.

---

## 10. Backup history and retention

The initial release should retain snapshots until the user explicitly deletes them.

Do not implement automatic pruning or retention policies in version 1.

Display:

* Number of snapshots.
* Total space used.
* Space used by each snapshot.
* Last successful backup.
* Last verification result.
* Any failed or incomplete jobs.

Allow the user to delete a snapshot only after explicit confirmation.

Before deletion, confirm that the selected item is a managed snapshot within the configured backup repository. Do not allow arbitrary folder paths to be deleted through the snapshot-deletion mechanism.

Never delete the only remaining verified backup of a source card automatically.

A later version may introduce user-configurable retention policies, but they must be opt-in and thoroughly tested.

---

## 11. Restore and recovery

The initial release must support restoring individual files and complete snapshots to a user-selected destination.

### Restore individual files

Allow the user to browse a snapshot and restore selected files or directories.

Preserve relative paths where appropriate. Detect conflicts at the destination and ask whether to skip, rename or replace files.

Do not overwrite files silently.

### Restore a complete snapshot

Allow a snapshot to be restored into a new folder, preserving the original directory structure and file bytes.

Verify the restored files against the manifest.

This creates a recovered copy of the card's contents; it does not automatically create a sector-by-sector SD-card clone.

### Restore to the SD card

Treat direct restoration to a mounted SD card as a guarded operation.

The initial release may provide a guided manual workflow rather than directly replacing the card's files.

If direct restore is implemented, it must:

* Require explicit source and destination confirmation.
* Warn that replacing files on the SD card can affect the Macintosh Plus.
* Check that the destination is the intended removable volume.
* Never format the card.
* Never delete unrelated files without a clear, separately confirmed action.
* Preserve an opportunity to back up the card's current contents before replacing them.
* Verify the restored files before reporting success.

The application must not describe a restored collection of files as a complete physical-card clone.

---

## 12. User interface states and error handling

Represent backup operations as explicit states, for example:

* Waiting for a card.
* Card detected.
* Scanning.
* Awaiting confirmation.
* Preparing snapshot.
* Copying.
* Verifying.
* Completed and verified.
* Completed with warnings.
* Failed.
* Cancelled.
* Source changed during backup.

Use a clear state model rather than scattered Boolean flags.

Show progress using measurable information such as bytes copied, files completed and the current operation.

Do not display a fabricated percentage if total work cannot be estimated accurately.

Support cancellation. Cancellation must leave previous snapshots untouched and must not make a partial snapshot appear complete.

Handle common errors explicitly:

* Unreadable source file.
* Unsupported filesystem entry.
* Destination unavailable.
* Insufficient space.
* Permissions denied.
* Source volume unmounted.
* Source file changed.
* Disk full during copy.
* Checksum mismatch.
* Snapshot manifest invalid.
* Backup repository unavailable.
* Interrupted application or system shutdown.

Provide concise messages for users and detailed diagnostic logs for troubleshooting.

Do not include sensitive personal data in logs unnecessarily.

---

## 13. Application architecture

Use Swift and SwiftUI for the main application, with native AppKit and Foundation APIs where appropriate.

Keep the architecture small and testable.

Suggested components:

### App and UI

* `MacPlusBackupApp`
* `MainWindow`
* `BackupStatusView`
* `SourceVolumeView`
* `SnapshotHistoryView`
* `SnapshotDetailView`
* `RestoreView`
* `SettingsView`

### Domain models

* `SourceVolume`
* `SourceCardIdentity`
* `BackupJob`
* `BackupSnapshot`
* `SnapshotManifest`
* `ManifestFileEntry`
* `BackupResult`
* `VerificationResult`
* `RestoreJob`

### Core services

* `VolumeMonitor` — observes mount and unmount events.
* `BlueSCSIRecognitionService` — evaluates whether a mounted volume resembles a BlueSCSI card.
* `SourceScanner` — inventories the filesystem-visible contents.
* `BackupCoordinator` — coordinates the job state machine.
* `SnapshotWriter` — copies files into a new snapshot.
* `ChecksumService` — calculates file checksums incrementally.
* `VerificationService` — verifies files and manifests.
* `SnapshotCatalog` — indexes snapshots and rebuilds the index.
* `RestoreService` — restores files or snapshots.
* `RepositoryManager` — manages the chosen backup destination.
* `LoggingService` — records useful diagnostics.

These are suggested boundaries, not a requirement to create a separate class for every operation. Prefer a simple, maintainable design.

### Concurrency

Long-running operations must not block the main UI thread.

Use Swift concurrency or another well-supported native mechanism for scanning, copying, hashing and verification.

Use bounded concurrency so that several very large disk images do not consume excessive memory or I/O bandwidth.

Keep filesystem operations cancellable where practical.

### Dependencies

Prefer native macOS APIs and Swift implementations for filesystem copying, checksums and volume monitoring.

Do not require Homebrew, Docker, Retro68 or the existing MacMusic development toolchain for the released application.

Document any third-party dependencies and their licences.

---

## 14. Data protection and repository safety

The backup repository itself is important data.

Implement the following safeguards:

* Never overwrite a completed snapshot.
* Never silently reuse an existing snapshot identifier.
* Never delete snapshots automatically.
* Never treat an incomplete snapshot as verified.
* Write manifests safely and validate them before committing a snapshot.
* Use temporary workspaces and safe finalisation.
* Detect destination conflicts before writing.
* Handle interrupted jobs and abandoned temporary snapshots.
* Allow the catalogue to be reconstructed from snapshot manifests.
* Verify snapshots independently of the original source card.
* Do not depend on the source SD card remaining connected after backup.

If the destination is unavailable, stop safely and explain the issue.

If the application launches after a crash, identify incomplete jobs without assuming they can be resumed safely. The first version may discard incomplete temporary work after user confirmation, provided completed snapshots remain untouched.

---

## 15. Testing strategy

Create a comprehensive automated test suite.

### Unit tests

Test:

* Snapshot identifier generation.
* Manifest encoding, decoding and version handling.
* Source-card identity matching.
* Volume-recognition rules.
* Filename and relative-path handling.
* Checksum calculation.
* Inventory comparison.
* Snapshot state transitions.
* Catalogue rebuilding.
* Restore conflict handling.
* Error classification.

### Integration tests

Use temporary directories and generated fixtures to simulate SD-card contents.

Include:

* Multiple `.hda` images.
* Configuration files.
* Logs.
* Nested directories.
* Hidden files.
* Empty files.
* Large test files.
* Files with spaces, Unicode and unusual names.
* Duplicate or case-conflicting paths where the test filesystem permits them.
* Unreadable files where reliably reproducible.
* Source files modified during copying.
* Destination disk-full or permission failures where safely testable.
* Interrupted backup jobs.
* Corrupted snapshot files.
* Corrupted manifests.
* Missing files during verification.

Verify that a successful backup contains every expected file with the correct checksum.

Verify that a failed backup never appears as a completed restore point.

### Volume detection tests

Separate the volume-detection logic from real hardware notifications so that it can be tested with simulated mount events and fixture directories.

Test that ordinary removable volumes do not automatically trigger a backup job.

### Manual acceptance tests

On the actual MacBook Neo:

1. Launch the application.
2. Insert the BlueSCSI SD card.
3. Confirm that the app detects the mounted volume and offers a backup.
4. Confirm that no copy starts before the user accepts.
5. Create a snapshot.
6. Verify the snapshot.
7. Disconnect and reconnect the card and confirm that the application handles it correctly.
8. Browse the previous snapshot.
9. Restore a selected file to a separate folder.
10. Verify that the restored file matches the original.
11. Restore a complete snapshot to a new folder.
12. Confirm that existing snapshots remain unchanged.

Do not claim physical-device testing has passed unless it has actually been performed.

---

## 16. Staged development roadmap

### Stage 0 — Inspect and design

* Inspect the existing MacBook Neo development environment and repository.
* Confirm the minimum supported macOS version.
* Research the current BlueSCSI documentation.
* Establish the volume-monitoring approach.
* Define the snapshot manifest and catalogue schemas.
* Produce an architecture note and test plan.
* Identify security and data-loss risks.

Deliverable: documented design, with unresolved assumptions clearly listed.

### Stage 1 — Core backup proof of concept

Build a command-driven or minimal-interface prototype that can:

* Read a selected source directory.
* Inventory every supported file.
* Copy the directory tree to a new snapshot.
* Calculate checksums.
* Verify the copied files.
* Write a manifest.
* Mark the snapshot complete only after verification.

Use a temporary test directory first. Do not begin by risking the actual SD card.

Deliverable: a tested, independent snapshot that can be verified and recovered without the source.

### Stage 2 — Snapshot catalogue and recovery

Implement:

* Snapshot listing.
* Snapshot detail inspection.
* Catalogue reconstruction from manifests.
* Independent snapshot verification.
* File restoration to a chosen destination.
* Complete snapshot restoration to a separate folder.

Deliverable: reliable backup history and recovery before adding hardware automation.

### Stage 3 — Native application interface

Build the SwiftUI interface and connect it to the tested core.

Add:

* Backup status.
* Source-volume details.
* Snapshot history.
* Progress and cancellation.
* Error messages.
* Settings and destination selection.
* Restore workflow.

Deliverable: a usable manual-backup application.

### Stage 4 — Removable-volume detection

Implement native volume mount and unmount monitoring.

Add BlueSCSI recognition, first-time card registration, remembered card identities and a prompt offering to back up.

Handle duplicate notifications, already-mounted volumes, card removal and permission failures.

Deliverable: the application offers a backup when a recognised or plausible BlueSCSI card is connected, without starting a job automatically.

### Stage 5 — Reliability and failure testing

Test large image files, interruptions, changing source files, missing files, checksum mismatches, destination failures and recovery from a damaged catalogue.

Confirm that completed snapshots remain intact when later jobs fail.

Deliverable: a reliable first release candidate.

### Stage 6 — Packaging and documentation

Prepare a native Apple Silicon build, document permissions and installation, and test the application outside the development environment.

Complete the README, specification, architecture, build and testing documentation.

Deliverable: a maintainable release that does not require the development environment to be installed.

---

## 17. Future features — explicitly out of scope for version 1

Keep the architecture extensible, but do not implement these features until the basic backup process is proven:

* Automatic scheduled backups.
* Automatic snapshot deletion and retention policies.
* Deduplicated or incremental snapshots.
* Full raw-sector SD-card images.
* Cloud or network destinations.
* Encryption and password-protected repositories.
* Backup comparison beyond the core manifest inventory.
* Automatic detection of changes made to a card between snapshots.
* Integration with MacMusic Transfer or the audio converter.
* Direct remote backup over BlueSCSI Wi-Fi or FTP.

Future integration with the other MacMusic utilities should be possible through documented file formats and clear interfaces, not through tight coupling between applications.

---

## 18. Definition of done

The first release is complete when:

* The app builds and runs natively on Apple Silicon macOS.
* It detects mounted volumes and offers a backup for a recognised or plausible BlueSCSI card.
* The user explicitly confirms a backup before copying begins.
* Every accessible file and directory is included.
* Each successful backup is a complete, independent snapshot.
* Every backed-up file is verified using its recorded checksum.
* Snapshot manifests and the catalogue are robust and versioned.
* The app supports snapshot browsing and file or folder recovery.
* It handles failures without damaging previous backups or the source card.
* No automatic retention policy deletes backups.
* Automated tests pass.
* The actual SD-card workflow has been tested and documented.
* All remaining limitations are clearly documented.

## 19. Instructions to Claude Code

Start at Stage 0.

Inspect the actual development environment and repository before choosing implementation details. Do not assume any particular project structure or that previous utilities are already integrated.

Provide a concise investigation report covering:

1. Recommended architecture.
2. Volume-detection strategy.
3. Snapshot layout and manifest schema.
4. Backup and verification strategy.
5. Risks and limitations.
6. Proposed staged implementation and tests.

Then implement the stages incrementally.

After each stage, run the relevant tests, update the documentation and summarise what was actually verified. Do not claim success for features that have not been tested.

Never delete or overwrite a completed backup to make an implementation easier. Never alter the source SD card during backup. Prefer a simple, dependable first release over speculative features.

---

## 20. Investigation, decisions and findings

### 20.1 Stage 0: the investigation (2026-10-09)

**The environment.** This Mac (Mac17,5), macOS 26.4.1, Xcode 26.6,
Swift 6.3.3; the SDK must be named (`SDKROOT=$(xcrun --sdk macosx
--show-sdk-path)`), as for the other utilities. The minimum macOS is
26.0, as theirs. The owner's Macintosh Plus runs **System 6.0.7** (not
6.0.8, as the brief says); nothing here depends on it.

**BlueSCSI, from its documentation** (Usage, SD Cards, bluescsi.ini):
images in the root of an exFAT (preferred) or FAT32 card, named
`TYPE[ID][_SECTORSIZE].ext` (types HD, CD, FD, MO, RE, TP, ZP; ID 0-7,
default 1; LUN 0 only; sector sizes 256-8192, default 512), at most 64
characters; `bluescsi.ini` can put images in folders (`Dir`, `ImgDir`,
`ImgN`); removable media may use folders such as `CD3`; the log is
`log.txt` in the root.

**BlueSCSI, from its firmware** (`BlueSCSI-v2/src/BlueSCSI.cpp`,
`findHDDImages`): a file is an image only if its name starts with a
device code (hd, cd, fd, mo, re, tp, zp, and others), case ignored, so
macOS's `._` files are never taken for images; the firmware writes
`log.txt` and keeps the last session's as `lastlog.txt`; it unpacks and
installs firmware from `BlueSCSI_update.zip` (and similarly named
packages), deleting the extracted `.bin` afterwards; special names
(`CLEAR_ROM`, `CREATEFILE...`) act as commands.

**macOS and FAT cards.** macOS writes to any FAT or exFAT card it mounts
(`.fseventsd`, `.Spotlight-V100`, `.Trashes`, `._*` files) before any
app sees it. The app can't prevent this, and BlueSCSI ignores them.

**Volume details.** `NSWorkspace` mount and unmount notifications, and
the volumes already mounted at launch; each volume's removable,
ejectable and internal flags, capacity and format from `URL`
resource values; its UUID, the device's model and protocol from
DiskArbitration. On FAT and exFAT, the volume UUID is derived from the
filesystem's serial number, which reformatting changes.

### 20.2 Decisions (approved by the owner, 2026-10-09)

- **B1, the name:** the **Macintosh Backup Utility** (as the manual, its
  cover and the stand-in icon); repository `~/MacPlusProjects/MacintoshBackup`;
  default backups `~/Mac Plus Backups/` (the brief's).
- **B2, the architecture:** a tested library, `MacintoshBackupKit` (the
  scanner, the copy-and-hash writer, the verifier, the manifest and
  catalogue, the restorer, recognition and identity); a thin SwiftUI
  app; a command-line tool, `mbu`, for Stages 1-2. No third-party code:
  CryptoKit for SHA-256, DiskArbitration for the volume's details.
- **B3, detection:** mount and unmount notifications, plus the volumes
  mounted at launch. A removable volume's root is read without writing;
  it is a *plausible BlueSCSI card* if it has a file named to the
  device-code pattern, `bluescsi.ini`, or `log.txt`/`lastlog.txt` in
  BlueSCSI's own log form. Others are ignored silently. The prompt is
  in the window, with one notification if the app is in the background;
  a backup never starts by itself.
- **B4, identity:** the volume UUID, name, capacity, filesystem and the
  reader's model; registering gives a card a friendly name; a partial
  match asks. The model holds many cards; the window is designed for one.
- **B5, the layout:** `Catalog/catalog.json` (an index, rebuildable);
  `Snapshots/<yyyy-MM-dd_HH-mm-ss>_<4 hex>/` with `SnapshotManifest.json`
  and `Files/`; work in progress in `Snapshots/.incomplete-<UUID>/`,
  moved into place only after every check passes; `Logs/`.
- **B6, the manifest:** versioned JSON (ARCHITECTURE.md). A snapshot's
  manifest is never rewritten once it is complete, so a later version's
  fields are never lost.
- **B7, copy and verify:** each file read once, in 1 MiB chunks, hashed
  and written; the copy flushed and read back to check its SHA-256; then
  each source file's size, modification date and file identifier
  compared with the inventory taken before. Any difference: the snapshot
  is *inconsistent*, never verified. The card isn't re-read to re-hash
  it (a "thorough" option may follow). One file at a time.
- **B8, scope:** everything visible, hidden files included; macOS's own
  files labelled "macOS metadata". Symbolic links and anything not a
  plain file or folder: recorded, skipped, with a warning.
- **B9, restore:** to a folder (a file, a folder or a whole snapshot,
  checked against the manifest; conflicts ask Skip, Keep Both or
  Replace); onto the existing card, a guided manual step.
- **B10, permissions:** unsandboxed, ad-hoc signed; macOS asks once for
  access to removable volumes.
- **B11, stages:** the brief's 0-6. **Before the app first reads the
  owner's real card, the owner is told exactly what will happen, and
  says go.**
- **B12, tests:** Swift Testing, against generated test cards; detection
  with simulated mount events.
- **B13, Restore to a New Card:** onto an empty card only (nothing but
  macOS's own files on it), never formatted by the app; exFAT preferred,
  FAT32 refused if an image is over 4 GB; big enough; everything but
  macOS's files and BlueSCSI firmware update packages (which would make
  it reflash itself; includable deliberately); one file at a time, under
  a hidden temporary name, renamed once its read-back matches; only the
  app's own files removed on failure; written without extended
  attributes; the whole card checked afterwards; the new card recorded
  as the old one's replacement.
- **B14, sparse copies** (the owner's choice of the options offered):
  each snapshot is a full, independent copy, but runs of zeros inside a
  file (a disk image's never-used space) are left as holes in the copy,
  which keeps its full size and exact bytes; restored, every byte is
  written out again. No sharing between snapshots; block-level
  deduplication is a candidate for version 2.

### 20.3 Stage 1: the backup engine (2026-10-09)

Built and tested on generated cards only; no real card has been read.

- A test card (three disk images, one in a folder; `bluescsi.ini`, both
  logs, a firmware package; macOS's `._` file, `.fseventsd` and
  `.DS_Store`; an empty file, an empty folder, a name with an accent, a
  tick and brackets) is backed up as a verified snapshot holding every
  file byte for byte, its manifest equal to the one written; only the
  snapshot's folder is left in Snapshots.
- B14: a 64 MB image with 110 KB of data takes under 4 MB in the
  snapshot, and its SHA-256 matches; in `mbu`'s run, a 67 MB card became
  a 316 KB snapshot.
- A file changed on the source after it was copied makes the snapshot
  *inconsistent*; an unreadable file, *failed*; cancelling, *cancelled*;
  none is named, and none verifies. A symbolic link is noted and
  skipped, and the snapshot still verifies.
- Too little room (an 8 MB disk made with `hdiutil`) is refused before
  anything is copied.
- A second backup is a new snapshot, and the first is untouched (its
  manifest's SHA-256 the same; it still verifies).
- Verifying later finds a changed byte, a missing file and an
  unexpected one, and refuses a damaged manifest or one whose totals
  disagree; a later schema's extra fields are read past. A snapshot
  verifies with its source deleted.
- Found and fixed: the manifest's dates must keep milliseconds (written
  from a whole number, as a formatter can be a millisecond out), and the
  source's re-check compares against the inventory's own, finer dates.

### 20.4 Stage 2: the catalogue and recovery (2026-10-09)

Built and tested on generated cards only.

- Each backup is catalogued; the last backup is the latest restore
  point; a failed job is listed as incomplete, never as a restore point.
- The catalogue deleted, then made unreadable, then put back out of date
  (missing the newest snapshot): each time rebuilt from the manifests,
  and every file in Snapshots byte-for-byte as before. A snapshot whose
  manifest is damaged is listed with its problem, not as a restore
  point; a folder of the owner's own in Snapshots is ignored.
- A whole snapshot restored into "Restored <name>" matches the card file
  for file; a second goes into "... 2"; no temporary files are left.
  One file and one folder restore with their paths; files not asked for
  aren't touched.
- A file already there: Skip leaves it; Keep Both adds "CD3 2.iso";
  Replace puts the backup's in its place; each time the owner is asked,
  once. A backup file damaged after the backup is caught while restoring,
  and nothing is put in place. An incomplete snapshot can't be restored
  from. macOS's own files and firmware packages can be left out.
- Deleting: refused unless confirmed, unless the ID matches, and for any
  folder that isn't one of the repository's snapshots ("..", "Catalog",
  a folder of the owner's, a path inside a snapshot); a confirmed one
  goes (in the tests, to a folder of their own, not the Trash) and the
  other snapshot still verifies; abandoned work can be cleared.
- `mbu list`, `show`, `restore` (whole, a folder, with Keep Both) and a
  rebuilt catalogue, tried by hand in the scratchpad.
- An implementation choice: deleting moves a snapshot to the Trash
  rather than erasing it, so a mistake can be undone.

### 20.5 Stage 3 decisions: the window (approved by the owner, 2026-10-09)

- **W1, one window:** the status at the top (state, card, last successful
  backup, latest result); the source card on the left (name, location,
  filesystem, capacity and use; after a scan, files, size, BlueSCSI
  images, configuration and logs, warnings); the history on the right
  (date and time, name, card, files, size, space taken, status,
  warnings), the selected snapshot's manifest below it.
- **W2, the actions:** Back Up Now, Browse Backups, Verify Backup,
  Restore…, Open Backup Folder, Settings (Command-comma).
- **W3, the card in Stage 3:** Choose Card… (a folder picker); recognising
  cards comes in Stage 4. Tested only on generated folders and images.
- **W4, the reminder** (the owner's revision): the card has to come out of
  the Plus to be backed up, so there's nothing to ask about its being in
  use. While waiting for a card, the window reminds: shut the Plus down
  with Shut Down in the Special menu, and switch it off when it says so,
  before taking the card out (losing power while the Plus is using the
  card can damage its disks: the owner has had to restore a backup after
  just that). The backup sheet shows the scan's summary, the space needed
  and free, and warnings, with Back Up and Cancel; Back Up is the
  confirmation. Afterwards: eject the card in the Finder, and put it back
  before switching the Plus on.
- **W5, progress:** the stage, files and megabytes done of the totals, the
  current file, Cancel.
- **W6, results:** verified, with warnings, inconsistent, failed,
  cancelled, in plain words with details.
- **W7, restoring** in a sheet: the whole snapshot or chosen files and
  folders; the destination; each conflict asked (Skip, Keep Both,
  Replace, "do the same for the rest"); the result.
- **W8, verifying** a snapshot, with progress; problems by file and kind.
- **W9, deleting** from a snapshot's menu: confirmed, with an extra warning
  for a card's last restore point; to the Trash.
- **W10, incomplete jobs** apart from the history, with Clear… (confirmed).
- **W11, Settings:** the backup folder (Choose…, Use Default); thinning
  (W14) on or off.
- **W12, the app:** "Macintosh Backup Utility.app", `tools/build-app.sh`,
  ad-hoc signed; the work off the main thread; quitting mid-job asks;
  the icon in the family style (made now, the owner's choice).
- **W13, disks not shut down cleanly:** an HFS volume's header records
  whether it was put away properly (its "unmounted cleanly" attribute);
  the scan reads it in each disk image (read-only: the partition map,
  then two bytes of the volume header) and warns of any image without
  it, before the backup and in the manifest. The backup still goes ahead.
- **W14, thinning older snapshots** (the owner's addition, changing the
  brief's §10 and §17: automatic deletion, on by default): per card,
  after each verified backup only, of verified snapshots only: the newest
  of each day for 7 days, of each week (from Monday) to a month, of each
  month to a year, none older; always at least two (the newest kept to
  make two); never incomplete jobs, another card's, or a snapshot pinned
  Keep; where a period has one, the newest cleanly shut down snapshot
  kept in preference to a newer one that wasn't (W13); removed to the
  Trash; reported after the backup; a setting to turn it off.

### 20.6 Stage 3: the window (2026-10-09)

Built; the library's parts tested (45 tests), the window to be tried by
the owner (it isn't seen here: no screenshots).

- W13: the clean-shutdown mark read from images made byte by byte
  (partitioned as BlueSCSI's, and plain as a floppy's; HFS and HFS Plus;
  set and clear), from a disk `hformat` made (clean), and from the
  Transfer Utility's Plus test image (attributes 0x100: clean). A
  backup of a card with an image whose mark was cleared verifies, with
  the warning, and the catalogue marks it.
- W14: over 420 days of daily backups, 7 kept in the last week, one a
  week to a month, one a month to a year, none older; the newest of a
  day kept; at least two always; a pinned one kept; the newest always
  kept, and a clean one preferred to a newer unclean one in the same
  period; after real backups, the oldest of three the same day thinned,
  a pinned one kept, an incomplete job untouched.
- Settings remembered (the backup folder; thinning on by default).
- The app doesn't make `~/Mac Plus Backups` until the first backup.
- A test card for the owner: `~/MacPlusProjects/backup-work/Test Card`
  (the Transfer Utility's image, a copy with its mark cleared as after a
  power cut, `bluescsi.ini`, a log, a `._` file).

### 20.7 Stage 4 decisions and findings: recognising the card (2026-10-09)

Decisions C1-C8 (approved by the owner): C1 watching (mount, unmount,
rename notifications; the disks at launch; only external, removable or
ejectable ones); C2 evidence, read only (strong: `bluescsi.ini`, or a
log naming BlueSCSI; likely: image names; else ignored); C3 the card
register (`Catalog/cards.json`; the same UUID is the card; the same
name, size and format with another UUID: ask; snapshots record the
card's ID; thinning by card); C4 one offer per insertion, in the window,
and one notification in the background; C5 the card removed mid-job
(the job isn't a restore point), Eject afterwards; C6 a plain message if
macOS hasn't allowed access; C7 the tests; C8 the first reading of the
owner's real card, by the owner, step by step (reading only).

Found, on folders and disk images only:
- Evidence: strong from `bluescsi.ini`, or a `log.txt`/`lastlog.txt`
  naming BlueSCSI; likely from image names; none for a camera's card, a
  log that isn't BlueSCSI's, or only `._` files.
- The register: a known card; a reformatted one (a new UUID, the same
  name, size and format) asked about, and confirmed; a different card
  new; renamed; saved and read back (its dates to the millisecond, as
  the manifest's).
- The watcher: the Mac's own disks and disks with no sign of BlueSCSI
  ignored; one offer however many notifications; gone, and back, offered
  again as the registered card.
- Thinning per card: two cards' snapshots thinned apart, each keeping two.
- Real mounts: exFAT and FAT32 disk images (made with `hdiutil`) are
  candidates (external, ejectable), with a UUID and a format; evidence
  none until `bluescsi.ini` is written to them, then strong.
- A note for testing: on this Mac, `hdiutil create` works from the test
  runner but is refused ("Operation not permitted") from the shell, so
  test images are made only inside the tests.
- The owner's real card: not yet read (C8).

**The owner's real card (C8; 2026-10-09):** done by the owner, step by
step, and "it works": recognised, registered as "Mac Plus BlueSCSI",
backed up, verified, ejected, recognised again, restored to folders,
and returned to the Plus. From the snapshots' manifests (read here, not
the card): a 15.5 GB FAT32 card, BLUESCSI, in a reader reporting
"STORAGE DEVICE"; six disk images (System 20 MB, Work 30 MB,
Applications 40 MB, Utilities 20 MB, Scratch 1980 MB, Transfer), with
`bluescsi.ini` and `log.txt`: 13 files, 2.26 GB, all verified.
- W13: every image was marked as cleanly put away, after a proper Shut
  Down: the check reads real Plus disks. That System 6 *clears* the mark
  while a disk is in use stays PROVISIONAL (it would take a power cut to
  see).
- B14: each snapshot takes 2.1 GB, near its full size: the images' free
  space isn't zeros (old data), so leaving zeros out saves little here.
- Found and fixed: a snapshot made before the card was registered (the
  owner's first, from Stage 3) carried no card ID, so thinning and the
  last-backup warning would have counted it as another card's; a
  snapshot without a card ID now counts as the registered card's when
  its volume's UUID matches, and the history shows the card's name.

### 20.8 Stage 4b: Restore to a New Card (B13; 2026-10-09)

The detail settled: "the replacement" means the new card takes over the
old card's entry in the register (its name, its ID, so its backups and
thinning carry on as one history), the old volume UUID kept as a
previous identity, so the old card turning up again is asked about.
Writing to a card is plain (every byte, in order), not sparse: FAT has
no holes, and one write keeps an image in one piece.

Found, on exFAT and FAT32 disk images only (the owner's spare card not
yet used):
- The checks: an empty card (macOS's and Windows's own items only)
  passes; anything else refused, naming it; not FAT (APFS) refused; a
  5 GB image refused on FAT32 and allowed on exFAT; too little room
  refused.
- Onto an empty exFAT, and an empty FAT32, image: every file the same as
  the card it was backed up from; no temporary names, no firmware
  package, no `._` files left; the empty folder made.
- A card with a photo on it: refused, and nothing written.
- A backup file damaged after the backup: the restore stops, and the
  card is as it was.
- The register: the new card known by its UUID under the old name and
  ID; the old UUID kept; the old card turning up asked about.
- The owner's spare card: to be tried later (2026-10-09). Until then,
  Restore to a New Card is verified on disk images only. The steps, the
  owner's to take (the real card stays in the Plus): format a spare card
  of at least 2.5 GB in Disk Utility (Erase; ExFAT; Master Boot Record);
  insert it; in the history, a Mac Plus BlueSCSI snapshot's Restore to a
  New Card…, the spare card, Restore to Card…, confirm; don't use it as
  the replacement if it's only a test; Eject; then, for the full test,
  shut the Plus down, put the spare card in the BlueSCSI and start it
  (it should come up as before), and swap the real card back.

### 20.9 Stage 5: reliability (F1-F6, approved by the owner; 2026-10-09)

- F1: a 3 GB image (1 MB of data at each end, the rest empty) backed up,
  verified, and restored to a folder, matching; the process's peak
  memory under 512 MB. **Found and fixed:** it had peaked at about 2 GB:
  each 1 MiB chunk's memory wasn't released until the whole file was
  done; now an autorelease pool per chunk (hashing and copying alike, so
  restoring to a card too). The owner's 1980 MB Scratch image would
  have taken about that much.
- F2: a 40 MB disk image filled mid-copy (the space check switched off
  for the test): the job fails, no snapshot is named, the catalogue has
  the one restore point, and the earlier snapshot verifies. **Found and
  fixed:** on a disk that isn't APFS, macOS's "available for important
  use" can read 0, so a roomy disk was refused; the larger of that and
  the plain free space is used.
- F3: a `.incomplete-` folder with no manifest (as if the app or the Mac
  stopped mid-backup) is listed as "Interrupted: it has no record...",
  never as a restore point, and clears on request.
- F4: an interrupted restore's `.mbu-restore-<UUID>` is removed by the
  next restore to that folder (only names of exactly that form; another
  file starting `.mbu-restore-` is left), and on a new card it doesn't
  make the card "not empty".
- F5: the card's folder deleted mid-backup: the job fails, no restore
  point, the earlier snapshot intact.
- F6: after each of these, the earlier snapshot verifies, and its
  manifest is byte for byte the same.

### 20.10 Stage 6: packaging (2026-10-09)

- `--self-test` in the app: a small card in a temporary folder (a disk
  image put away cleanly, `bluescsi.ini`, a log) recognised, backed up,
  verified, verified again from the snapshot alone, restored to a folder
  and compared, catalogued; everything removed. It passes in the
  packaged app, and the owner's backups are untouched.
- `tools/make-release.sh`, as the other utilities': committed source
  only; the tests; the app; the self-test on a copy outside the
  repository; the zip, release notes, SHA256SUMS, a git bundle of the
  source, the checks. No third-party code, so no licences to carry.
- The release notes, BUILDING.md and TESTING.md. Version 1.0; the tag
  after the owner's acceptance.
