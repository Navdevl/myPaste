#!/bin/bash
# Installs myPaste into ~/Applications and opens it.
#
#   curl -fsSL https://raw.githubusercontent.com/Navdevl/myPaste/main/scripts/install.sh | bash
#
#   ./scripts/install.sh              download the latest release (no developer tools needed)
#   ./scripts/install.sh --source     build from source instead (needs Apple's Command Line Tools)
#   ./scripts/install.sh --uninstall  remove the app (add --purge to also delete your clipboard history)
set -euo pipefail

REPO="Navdevl/myPaste"
APP_DIR="$HOME/Applications"
APP="$APP_DIR/myPaste.app"
DATA="$HOME/Library/Application Support/myPaste"

say()  { printf '\033[1m==>\033[0m %s\n' "$*"; }
fail() { printf '\033[31mError:\033[0m %s\n' "$*" >&2; exit 1; }

quit_running() {
    osascript -e 'tell application id "local.mypaste.app" to quit' >/dev/null 2>&1 || true
    pkill -x myPaste 2>/dev/null || true
    sleep 0.5
}

check_macos() {
    local major
    major=$(sw_vers -productVersion | cut -d. -f1)
    [ "$major" -ge 14 ] || fail "myPaste needs macOS 14 (Sonoma) or later. This Mac has $(sw_vers -productVersion)."
}

install_release() {
    local url="${MYPASTE_ZIP_URL:-https://github.com/$REPO/releases/latest/download/myPaste.zip}"
    TMP=$(mktemp -d)
    trap 'rm -rf "$TMP"' EXIT
    local tmp="$TMP"
    say "Downloading the latest myPaste"
    curl -fL --progress-bar "$url" -o "$tmp/myPaste.zip" \
        || fail "Couldn't download $url. Check your connection, or build it yourself with --source."
    ditto -x -k "$tmp/myPaste.zip" "$tmp"
    [ -d "$tmp/myPaste.app" ] || fail "The download didn't contain myPaste.app."
    quit_running
    mkdir -p "$APP_DIR"
    rm -rf "$APP"
    mv "$tmp/myPaste.app" "$APP"
    # Not notarized: clear the download flag so macOS doesn't refuse to open it.
    xattr -dr com.apple.quarantine "$APP" 2>/dev/null || true
}

install_source() {
    xcode-select -p >/dev/null 2>&1 || {
        xcode-select --install 2>/dev/null || true
        fail "Apple's Command Line Tools aren't installed. A dialog should have opened to install them; run this again when it finishes."
    }
    local version
    version=$(swift --version 2>&1) || {
        echo "$version" | grep -qi license && fail "Accept the Xcode licence first: sudo xcodebuild -license accept"
        fail "swift didn't run: $version"
    }
    local major
    major=$(echo "$version" | sed -n 's/.*Swift version \([0-9]*\).*/\1/p' | head -1)
    [ "${major:-0}" -ge 6 ] || fail "myPaste needs Swift 6 or later (you have: $(echo "$version" | head -1)). Update the Command Line Tools in System Settings → General → Software Update."

    # Inside a clone, build that checkout; under `curl | bash` there's no script file, so fetch one.
    local src="" here="${BASH_SOURCE[0]:-}"
    if [ -n "$here" ] && [ -f "$here" ] && grep -qs '"myPaste"' "$(dirname "$here")/../Package.swift"; then
        src="$(cd "$(dirname "$here")/.." && pwd)"
    else
        command -v git >/dev/null || fail "git is needed to fetch the source."
        src=$(mktemp -d)/myPaste
        say "Fetching the source"
        git clone --depth 1 "https://github.com/$REPO.git" "$src" >/dev/null
    fi
    say "Building myPaste (the first build takes a few minutes)"
    make -C "$src" install
}

uninstall() {
    quit_running
    rm -rf "$APP"
    say "Removed $APP"
    if [ "${1:-}" = "--purge" ]; then
        rm -rf "$DATA"
        say "Deleted your myPaste history and settings"
    else
        echo "Your history is still in $DATA (run with --uninstall --purge to delete it)."
    fi
}

case "${1:-}" in
    --uninstall) uninstall "${2:-}"; exit 0 ;;
    --source) check_macos; install_source ;;
    ""|--release) check_macos; install_release; open "$APP" ;;
    *) fail "Unknown option $1. Use --source, --uninstall or no option." ;;
esac

cat <<'EOF'

myPaste is installed in ~/Applications and running (look for the clipboard icon in the menu bar).

One more step: when it asks, allow Accessibility access in System Settings → Privacy & Security →
Accessibility. That's how it pastes into the app you were using.

Press ⇧⌘C to open it.

After an update, if pasting stops working: remove myPaste from that Accessibility list and add it again.
EOF
