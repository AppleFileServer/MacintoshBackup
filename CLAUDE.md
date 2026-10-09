# Macintosh Backup Utility

## Project

A native macOS app that backs up the BlueSCSI SD card of the owner's
Macintosh Plus (System 6.0.7) as dated, verified snapshots, and
restores them, including to a new card. The requirements:
`Documentation/SPECIFICATION.md` (the owner's brief, unedited, calling
it "Mac Plus Backup"; the investigation and decisions B1-B14 in §20).

Related projects (don't change them unless asked): MacMusic
(`~/MacPlusProjects/MacMusicPlayer`), the MacMusic Converter Utility and
the MacMusic Transfer Utility (`~/MacPlusProjects/MacMusicConverter`,
`MacMusicTransfer`), whose disk images it backs up.

## Build and test

    tools/test.sh          # the library's tests (swift test)

## Working rules

- **Plan before coding** with numbered decisions; wait for approval;
  record them in SPECIFICATION.md §20.
- **Stage by stage** (brief §16); run the tests, update the documents,
  report what was actually verified, then commit.
- **Never commit until the owner approves.**
- **Never touch the owner's BlueSCSI SD card** (not even to read it)
  without telling the owner exactly what will happen first, and their go.
- **Never delete or overwrite a completed snapshot**, in code or in tests
  outside a temporary folder.
- **Throwaway diagnostics** in the scratchpad, not the project.
- **No screenshots or Accessibility control** unless the owner asks.
- **Mini vMac:** ask the owner to quit it rather than doing it.
