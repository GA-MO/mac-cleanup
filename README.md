# Mac Cleanup

A native macOS (SwiftUI) disk-cleanup app. Scans for reclaimable space and
moves anything you select to the **Trash** — it never deletes permanently.

## What it finds

| Category | Examples | Default selection |
|----------|----------|-------------------|
| **Developer Junk** | Xcode DerivedData, npm/pip/brew/Gradle/Cargo caches, stale `node_modules`, Rust `target` | Safe items auto-selected |
| **Caches & Logs** | `~/Library/Caches`, `~/Library/Logs`, crash reports | Caches auto-selected, logs flagged Review |
| **Large & Old Files** | 100 MB+ files in Downloads/Documents/Desktop/Movies | Never auto-selected (Caution) |
| **Duplicates** | Identical files by content hash | Keeps the oldest copy, others selectable |

Every item carries a safety badge:

- 🟢 **Safe** — regenerates automatically, auto-selected
- 🟠 **Review** — usually fine, but look first (logs, active build dirs, duplicate keepers)
- 🔴 **Caution** — personal files, never auto-selected

## Architecture

```
Sources/
  CleanupKit/            ← pure-Swift engine, fully unit-tested
    Models.swift           CleanupItem, SafetyLevel, CleanupCategory
    FileSystem.swift       recursive sizing, enumeration helpers
    Scanner.swift          Scanner protocol
    Scanners/              one file per scanner
    CleanupEngine.swift    orchestration + move-to-Trash
  MacCleanup/            ← SwiftUI app shell
    AppModel.swift         @Observable state, scan/clean lifecycle
    *View.swift            UI
Tests/CleanupKitTests/   ← engine tests (no UI needed)
```

The engine has **no UI dependency**, so you can iterate and test the scanning
logic entirely from the command line.

## Develop

```bash
swift build          # compile everything
swift test           # run engine tests
swift run MacCleanup # launch the app (debug)
```

## Build a launchable .app

```bash
./scripts/bundle.sh
open "build/Mac Cleanup.app"
```

Then grant **Full Disk Access** in *System Settings → Privacy & Security* for
complete results (some system caches are otherwise unreadable).

## Safety design

- Deletions use `FileManager.trashItem` — recoverable from Trash.
- Dry-run preview available before any removal (`CleanupEngine.remove(dryRun:)`).
- `node_modules`/build dirs are only flagged when a real project marker
  (`package.json`, `Cargo.toml`, …) is present, and active projects are
  downgraded to *Review*.
- Login/keychain-sensitive caches are on a protected denylist.

## CLI mode

```bash
swift run MacCleanup --scan     # headless, read-only report of reclaimable space
```

## Tools

Four tools in one window (sidebar navigation), plus a menu-bar readout:

1. **Cleanup** — the scanner suite above (dev junk, caches, large files, duplicates, downloads, app leftovers).
2. **Uninstaller** — pick any app and remove the bundle *plus* every support
   file, cache, preference, container, and launch agent it left across `~/Library`.
3. **Disk Map** — squarified treemap of disk usage with drill-down, like DaisyDisk.
4. **Maintenance** — flush DNS, free memory, rebuild Spotlight / Launch Services,
   clear font caches (admin tasks prompt for your password).

**Menu bar:** live free-space gauge with a low-space warning and quick launch.

## Roadmap

- [x] Developer junk, caches & logs, large/old files, duplicates
- [x] Downloads & installers cleanup (old downloads, .dmg/.pkg)
- [x] App-leftover finder + full Smart Uninstaller
- [x] Cross-scanner path de-duplication (no double-counted totals)
- [x] Disk usage treemap (squarified) with drill-down
- [x] Maintenance tasks (DNS / memory / Spotlight / fonts / Launch Services)
- [x] Menu-bar free-space monitor with low-space warning
- [ ] Similar-photo detection (perceptual hash)
- [ ] Privacy: clear browser history/cookies
- [ ] Scheduled / automated scans + ignore list
- [ ] Notarization for distribution
