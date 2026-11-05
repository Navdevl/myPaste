#!/bin/bash
# Publishes the current VERSION as a GitHub release with a universal myPaste.zip, which
# scripts/install.sh downloads. Run from a clean tree on the commit tagged vVERSION.
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION=$(cat VERSION)
TAG="v$VERSION"
[ -z "$(git status --porcelain)" ] || { echo "Commit your changes first." >&2; exit 1; }
[ "$(git rev-parse HEAD)" = "$(git rev-parse "$TAG^{commit}" 2>/dev/null)" ] || { echo "HEAD isn't tagged $TAG." >&2; exit 1; }

make dist
# This version's CHANGELOG section becomes the release notes.
NOTES=$(awk -v v="## $VERSION " 'index($0, v) == 1 { on = 1; next } /^## / { on = 0 } on' CHANGELOG.md)
git push origin "$TAG"
gh release create "$TAG" build/dist/myPaste.zip --title "myPaste $VERSION" --notes "$NOTES"
