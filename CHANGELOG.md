# Changelog

Versions follow semver. The build number (CFBundleVersion) is the git commit count, stamped by `make app`.

## 1.1.0 (unreleased)

- Smart actions: JWT decode, Jira keys → open in Jira, UUIDs, Unix timestamps (IST), GitHub PR/issue refs.
- Quick Look: syntax-highlighted code; zoom and pan for images.
- Orphaned preview images are swept at launch.
- Accessibility-driven UI test suite (`make uitest`).
- Version and build shown in Settings → About.

## 1.0.0 (2026-10-29)

- Bottom strip with Liquid Glass, capture of text, rich text, links, images, files, colours, code, email, phone.
- Direct paste, Paste Stack, pinboards, tags, rename/edit, search with `/type @app #tag`.
- Sensitive detection with blur and expiry; PAN/Aadhaar/IFSC/UPI/account numbers masked.
- Hold ⌘ edit mode, hold ⇧ plain mode, ⌘K transforms, snippets with placeholders, undoable deletes.
- Link previews via Open Graph with LinkPresentation fallback, OCR for images.
- Settings redesign, onboarding, app icon, backup/export, local error and crash log.
