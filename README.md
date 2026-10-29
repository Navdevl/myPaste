# myPaste

A personal, local-only clipboard manager for macOS modelled on Paste. No sync, no account, no telemetry.

## Build

```
make cert      # once: self-signed "myPaste Dev" identity, keeps the Accessibility grant across rebuilds
make test      # Swift Testing suite for Core (classifier, sensitive detection, GRDB store, search, retention)
make install   # swift build -c release, bundle, sign, copy to ~/Applications/myPaste.app and launch
```

SwiftPM package: GRDB for storage, KeyboardShortcuts for global hotkeys, Liquid Glass on macOS 26.
Always build through the Makefile, not bare `swift build`. The local Command Line Tools still carry two
stale files from an older install (`usr/include/swift/module.modulemap` and PackageDescription's
`.private.swiftinterface`). `build-support/clt-overlay.yaml.in` hides them per build without sudo.
Deleting those two files with sudo fixes this for good.

KeyboardShortcuts is pinned to 1.15.0, the last release without `#Preview` macros (those need Xcode).
Settings uses its own recorder rather than `KeyboardShortcuts.Recorder`, whose localized strings
come from a SwiftPM resource bundle it looks for at the .app root, where a signed app can't hold one.

## Use

| Key | Action |
| --- | --- |
| ⇧⌘V | Open / close the strip |
| hold ⌘ | Edit mode: cards jiggle, ✕ delete buttons, ⌘1–9 badges, shortcut bar |
| ← → / ↑ ↓ | Select card / switch History and pinboard tabs |
| ⌘↑ ⌘↓ (Home/End) | First / last card |
| Tab / ⇧Tab | Cycle the type filter |
| ⌥0–9 | History / Nth pinboard |
| ↩ / ⇧↩ | Paste / paste as plain text |
| ⌘1–9 (⇧ for plain) | Quick paste the Nth card |
| Space | Quick Look |
| ⌘⇧⌫ | Delete card (⌘Z undoes, up to 10, for 10 s) |
| ⌘⌫ / ⌥⌫ | Delete text in the search field |
| ⌘P / ⌘⇧P | Pin to last pinboard (or unpin) / pick a pinboard |
| ⌘O | Open link / show file in Finder |
| ⌘C / ⌥⌘C | Copy / copy as plain text, without pasting |
| ⌘I | Info |
| ⌘J | Smart action: open Jira key / GitHub PR, decode JWT, convert timestamp |
| ⌘K | Actions: JSON/SQL formatting, text cleanup, case, URL cleanup, encode/decode, hashes, epoch ↔ IST |
| ⌘R ⌘T ⌘E | Rename / tags / edit text |
| ⌘N | New pinboard |
| ⇧⌘C (global) | Start / end Paste Stack (each ⌘V pastes the next queued copy) |

Search: words match text, titles, file names, link titles and text in images. `/img` `/link` `/code` `/text`
`/rich` `/file` `/color` `/email` `/phone` `/secret` filter by type (prefixes work: `/im`), `@slack` filters by
source app, `#tag` by tag. Tokens combine.

Drag a card onto a pinboard tab to pin it. Right-click a card for everything else.

Hold ⇧ in the panel for plain-text mode: ↩, ⌘1–9 and double-click all paste without formatting.

Snippets: a pinned item containing `{date}` `{time}` `{datetime}` (IST) `{clipboard}` `{uuid}` or
`{cursor}` is expanded at paste time; the caret lands at `{cursor}`.

Privacy: OTPs, API keys, JWTs, private keys and password-like text are blurred; PAN, Aadhaar, IFSC,
UPI IDs, account and card numbers are always masked in previews (e.g. `••••1234`). All of them expire
after the sensitive TTL unless pinned, and existing history is re-scanned at launch.

Backup: Settings → Backup exports a `.mypaste` zip of pinboards (optionally history). Sensitive items are
never exported. Import merges pinboards by name and items by content.

Diagnostics: errors go to `~/Library/Application Support/myPaste/logs/` (never clipboard contents);
`MYPASTE_PERF=1` logs main-thread hangs over 100 ms. `scripts/make-icon.sh` regenerates the app icon.

Data: `~/Library/Application Support/myPaste/` (SQLite + blobs). Set `MYPASTE_DATA_DIR` to run against
a throwaway database. Post the distributed notification `local.mypaste.toggle` to toggle the strip from scripts.

## Layout

- `Sources/Core` (MyPasteCore): no AppKit. Classifier, sensitive detection, `ClipStore` on GRDB (migrations, FTS5 trigram search, retention).
- `Sources/App`: AppKit/SwiftUI. Pasteboard polling, hotkeys, panel, cards, Paste Stack, OCR/link enrichment, settings.
- `Tests/MyPasteCoreTests`: Swift Testing suites for Core.
