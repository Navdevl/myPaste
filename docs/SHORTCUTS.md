# Shortcuts and features

## Keys

| Key | Action |
| --- | --- |
| ⇧⌘V | Open / close the strip |
| hold ⌘ | Edit mode: cards jiggle, ✕ delete buttons, ⌘1–9 badges, shortcut bar |
| ← → / ↑ ↓ | Select card / switch History and pinboard tabs |
| ⇧⌘V again, ⌃Tab / ⌃⇧Tab | Next / previous board |
| hold ⌥ | Show ⌥0–9 board numbers |
| ⌃⌃ (double-tap Control) | Pin picker for the selected card; outside the strip, for your latest copy |
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
| ⇧⌘C (global) | Paste Stack, if enabled in Settings → Shortcuts (off by default): copy several things, then each ⌘V pastes the next |

Hold ⇧ in the strip for plain-text mode: ↩, ⌘1–9 and double-click all paste without formatting.
Drag a card onto a pinboard tab to pin it. Right-click a card for everything else.

## Search

Search covers History and every pinboard, whichever tab is open (Settings → Appearance → Pinboards →
Search everywhere). Words match text, titles, file names, link titles and text in images.

- `/img` `/link` `/code` `/text` `/rich` `/file` `/color` `/email` `/phone` `/secret` filter by type (prefixes work: `/im`)
- `@slack` filters by source app
- `#tag` filters by tag

Tokens combine, e.g. `/code #sql users`.

## Snippets

A pinned item containing `{date}` `{time}` `{datetime}` `{clipboard}` `{uuid}` or `{cursor}` is expanded
when you paste it; the caret lands at `{cursor}`.

## Privacy

OTPs, API keys, JWTs, private keys and password-like text are blurred. PAN, Aadhaar, IFSC, UPI IDs, account
and card numbers are always masked in previews (e.g. `••••1234`). All of them expire after a few minutes
unless pinned, and you can still find them by searching for what they are ("ifsc", "api key").

## Everything else

- **Sounds:** Settings → Appearance → Sounds. Pick from the built-in pack or use your own audio file.
- **Backup:** Settings → Backup exports your pinboards (optionally history) as a `.mypaste` file. Sensitive items are never exported.
- **Coming from Maccy:** Settings → Backup → Import Pins from Maccy copies its pinned items onto a "Maccy" pinboard.
