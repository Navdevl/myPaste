# Changelog

Versions follow semver. The build number (CFBundleVersion) is the git commit count, stamped by `make app`.

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
