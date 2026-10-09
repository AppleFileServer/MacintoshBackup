# Changelog

## 0.1.0 (in development)

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
