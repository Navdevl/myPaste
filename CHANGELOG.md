# Changelog

Versions follow semver. The build number (CFBundleVersion) is the git commit count, stamped by `make app`.

## 1.6.2 (2026-11-06)

- Opening the strip is faster. The staggered card entrance (the first ten cards springing in 35 ms apart, about half a second) is now off by default; turn it back on in Settings → Appearance → Opening the strip. The slide and fade are also shorter (0.13 s and 0.09 s, from 0.2 s and 0.16 s).
- The first open after launch no longer stalls 110–155 ms: the strip is rendered once, invisibly, a second after launch.
- `MYPASTE_PERF=1` also logs the open path (`show.*`), and `MYPASTE_UITEST_AUTOTOGGLE=n` opens and closes the strip n times by itself for timing runs.

## 1.6.1 (2026-11-05)

- One-line install: `scripts/install.sh` downloads the latest release (universal, Apple silicon + Intel), so you don't need developer tools. `--source` builds from a clone or a fresh checkout after checking for the Command Line Tools and Swift 6. `--uninstall [--purge]` removes it.
- `make dist` and `scripts/release.sh` build and publish that release.
- Builds with Swift 6.0/6.1 and pre-macOS 26 SDKs (Liquid Glass is compiled only when the SDK has it).

## 1.6.0 (2026-11-03)

- Removed Paste Stack entirely: the ⇧⌘C shortcut, the menu-bar item, the "Add to Paste Stack" card action, the HUD and the Settings switch. The leftover setting and stored shortcut are cleaned up on launch.
- The default Open shortcut is now ⇧⌘C (was ⇧⌘V). If you already recorded your own, it is kept.
- The shortcut-clash check now compares only your Open shortcut against other clipboard apps' defaults.
- UI tests no longer depend on the Open shortcut you recorded.

## 1.5.0 (2026-10-30)

- Open source under the MIT licence. README covers running it on your own Mac, with screenshots.
- The Jira site has no default; set yours in Settings to get Jira chips (existing settings are kept).
- Link titles decode more HTML entities (`&hellip;`, curly quotes, `&copy;`…); `&amp;lt;` no longer turns into `<`.

## 1.4.2 (2026-10-29)

- Masked items are searchable by their label: "account", "ifsc", "api key", "pan" and so on find them even though the value is hidden. Migration v3 re-indexes existing masked items.

## 1.4.1 (2026-10-29)

- Search from a pinboard tab now covers History and every pinboard, not just the open board. An "All boards" badge shows next to the search field while that's happening. Turn it off in Settings → Appearance → Pinboards → Search everywhere.

## 1.4.0 (2026-10-29)

- New sound pack: 15 WAVs (48 kHz/24-bit) rendered by `scripts/make-sounds.swift` (modal wood/glass,
  filtered noise, pitch-enveloped drops, small room reverb), loudness-matched to about -20 dBFS RMS.
  Copy: Wood Knock (new default), Soft Key, Glass Tick, Paper Snap, Bubble, Marimba, Classic Tick.
  Paste: Soft Pop, Water Drop, Thock, Chime. Delete: Whoosh, Crumple, Swipe, Soft Thud.
- Settings → Appearance → Sounds: pick any sound per event (auditions on selection), Play buttons, or
  "Choose…" your own audio file (copied into myPaste's data folder).

## 1.3.0 (2026-10-29)

- Import pins from Maccy (Settings → Backup): Maccy's pinned items land on a "Maccy" pinboard with their
  formatting, source app and copy dates. Reads a temporary copy of Maccy's store; safe to re-run.
- Sound effects: subtle synthesized clicks for copy, paste and delete. On at 40%, with volume, per-event
  switches and Play buttons in Settings → Appearance (silent during UI tests).

## 1.2.1 (2026-10-29)

- Paste Stack is now optional and off by default (Settings → Shortcuts). While off, ⇧⌘C isn't registered,
  its menu entries are hidden, and it's ignored by the shortcut-conflict check.
- Shortcuts pane re-checks for clashing apps when Paste Stack is switched on.
- UI tests run with their own wiped settings domain, so a test run never changes your preferences.

## 1.2.0 (2026-10-29)

- Quick pin: double-tap ⌃ in the strip pins the selected card; anywhere else it pins your latest copy.
  New pin picker with coloured board chips, 1–9, type-to-filter and ↩ to create a board.
- Board switching: ⇧⌘V again cycles tabs, ⌃Tab / ⌃⇧Tab, hold ⌥ to see ⌥0–9 numbers.
- Motion: gliding selection ring, light sweep, neighbour parallax, trackpad haptics.
- Settings → Appearance: a switch for each of the above (all off = 1.1 behaviour).
- Build: plain SwiftPM (Command Line Tools workaround removed); UI tests cover the new features.

## 1.1.0 (2026-10-29)

- Smart actions: JWT decode, Jira keys → open in Jira, UUIDs, Unix timestamps (IST), GitHub PR/issue refs.
- Quick Look: syntax-highlighted code; zoom and pan for images.
- Orphaned preview images are swept at launch.
- Accessibility-driven UI test suite (`make uitest`).
- Version and build shown in Settings → About; launch log records version and Accessibility status.
- Lowercase SQL is classified as code; Quick Look and overlays use an opaque surface on macOS 26.
- Build applies the Command Line Tools overlay only while the stale files exist.

## 1.0.0 (2026-10-29)

- Bottom strip with Liquid Glass, capture of text, rich text, links, images, files, colours, code, email, phone.
- Direct paste, Paste Stack, pinboards, tags, rename/edit, search with `/type @app #tag`.
- Sensitive detection with blur and expiry; PAN/Aadhaar/IFSC/UPI/account numbers masked.
- Hold ⌘ edit mode, hold ⇧ plain mode, ⌘K transforms, snippets with placeholders, undoable deletes.
- Link previews via Open Graph with LinkPresentation fallback, OCR for images.
- Settings redesign, onboarding, app icon, backup/export, local error and crash log.
