# Developing myPaste

## Build

```
make cert      # once: self-signed "myPaste Dev" identity, keeps the Accessibility grant across rebuilds
make test      # Swift Testing suite for Core (classifier, sensitive detection, GRDB store, search, retention)
make install   # swift build -c release, bundle, sign, copy to ~/Applications/myPaste.app and launch
make uitest    # UI tests: drives the real app via the Accessibility API (~40 s; don't type meanwhile)
make version   # prints VERSION and the build number
```

SwiftPM package: GRDB for storage, KeyboardShortcuts for global hotkeys, Liquid Glass on macOS 26.
`make` wraps `swift build` and assembles/signs the .app bundle. No Xcode project.

KeyboardShortcuts is pinned to 1.15.0, the last release without `#Preview` macros (those need Xcode).
Settings uses its own recorder rather than `KeyboardShortcuts.Recorder`, whose localized strings
come from a SwiftPM resource bundle it looks for at the .app root, where a signed app can't hold one.

## Layout

- `Sources/Core` (MyPasteCore): no AppKit. Classifier, sensitive detection, `ClipStore` on GRDB (migrations, FTS5 trigram search, retention).
- `Sources/App`: AppKit/SwiftUI. Pasteboard polling, hotkeys, panel, cards, Paste Stack, OCR/link enrichment, settings.
- `Tests/MyPasteCoreTests`: Swift Testing suites for Core.
- `Tests/UITests`: the UI test harness.
- `scripts/`: signing identity, app icon and sound pack generators.

## Data and diagnostics

- Data: `~/Library/Application Support/myPaste/` (SQLite + blobs). Set `MYPASTE_DATA_DIR` to run against a throwaway database.
- Errors go to `logs/` in that folder (never clipboard contents). `MYPASTE_PERF=1` logs main-thread hangs over 100 ms.
- Post the distributed notification `local.mypaste.toggle` to toggle the strip from scripts.
- `scripts/make-icon.sh` regenerates the icon; `swift scripts/make-sounds.swift Resources/Sounds` regenerates the sound pack.

## Releases

`VERSION` holds the semver version; the build number is the git commit count. For a release: update
`CHANGELOG.md`, bump `VERSION`, commit, `git tag vX.Y.Z`, `make install`.

## UI tests

`Tests/UITests` is an AppKit harness (not XCUITest: no Xcode here). It launches `build/myPaste.app` with
`MYPASTE_UITEST=1` and a throwaway data folder, types with CGEvents, and finds/presses controls by
accessibility identifier. Test-only seams (file panels, URL opening, Settings pane routing) live in
`Sources/App/UITestHooks.swift`. The terminal running it needs Accessibility permission. The conflict test
launches a fake app with Maccy's bundle id and is skipped if the real Maccy is running.
