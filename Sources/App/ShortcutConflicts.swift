import AppKit
import KeyboardShortcuts

/// Running clipboard managers whose *default* shortcut collides with ours. macOS has no API to ask who
/// owns a global hotkey, so this is a known-apps table; users may have rebound theirs.
enum ShortcutConflicts {
    struct Conflict: Identifiable {
        let app: NSRunningApplication
        let name: String
        let shortcut: KeyboardShortcuts.Name
        var id: String { (app.bundleIdentifier ?? name) + shortcut.rawValue }
    }

    private static let known: [(bundleID: String, name: String, key: KeyboardShortcuts.Key, mods: NSEvent.ModifierFlags)] = [
        ("org.p0deje.Maccy", "Maccy", .c, [.command, .shift]),
        ("com.wiheads.paste", "Paste", .v, [.command, .shift]),
        ("com.wiheads.paste-setapp", "Paste", .v, [.command, .shift]),
        ("com.generalarcade.flycut", "Flycut", .v, [.command, .shift]),
        ("com.clipy-app.Clipy", "Clipy", .v, [.command, .shift]),
        ("com.fiplab.copyclip2", "CopyClip 2", .v, [.command, .shift]),
    ]

    static func current() -> [Conflict] {
        let ours: [(KeyboardShortcuts.Name, KeyboardShortcuts.Shortcut?)] = [
            (.openPanel, KeyboardShortcuts.getShortcut(for: .openPanel)),
            (.pasteStack, Preferences.shared.pasteStackEnabled ? KeyboardShortcuts.getShortcut(for: .pasteStack) : nil),
        ]
        var out: [Conflict] = []
        for app in NSWorkspace.shared.runningApplications {
            guard let id = app.bundleIdentifier else { continue }
            for k in known where k.bundleID == id {
                let theirs = KeyboardShortcuts.Shortcut(k.key, modifiers: k.mods)
                for (name, mine) in ours where mine == theirs {
                    out.append(Conflict(app: app, name: k.name, shortcut: name))
                }
            }
        }
        return out
    }

    static func label(_ name: KeyboardShortcuts.Name) -> String {
        name == .openPanel ? "Open myPaste" : "Paste Stack"
    }

    /// One alert per launch at most, and never again for an app the user said to ignore.
    static func warnIfNeeded(openSettings: @escaping () -> Void) {
        let ignored = Set(AppDefaults.store.stringArray(forKey: "ignoredConflicts") ?? [])
        guard let c = current().first(where: { !ignored.contains($0.id) }) else { return }
        let alert = NSAlert()
        alert.messageText = "\(c.name) may be using \(KeyboardShortcuts.getShortcut(for: c.shortcut)?.description ?? "")"
        alert.informativeText = "\(c.name) is running, and its default shortcut is the same as myPaste's \"\(label(c.shortcut))\". Only one app gets the key press."
        alert.addButton(withTitle: "Quit \(c.name)")
        alert.addButton(withTitle: "Change Shortcut…")
        alert.addButton(withTitle: "Ignore")
        NSApp.activate(ignoringOtherApps: true)
        switch alert.runModal() {
        case .alertFirstButtonReturn: c.app.terminate()
        case .alertSecondButtonReturn: openSettings()
        default: AppDefaults.store.set(Array(ignored) + [c.id], forKey: "ignoredConflicts")
        }
    }
}
