import AppKit
import KeyboardShortcuts

/// Running clipboard managers whose *default* shortcut collides with ours. macOS has no API to ask who
/// owns a global hotkey, so this is a known-apps table; users may have rebound theirs.
enum ShortcutConflicts {
    struct Conflict: Identifiable {
        let app: NSRunningApplication
        let name: String
        var id: String { app.bundleIdentifier ?? name }
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
        guard let mine = KeyboardShortcuts.getShortcut(for: .openPanel) else { return [] }
        var out: [Conflict] = []
        for app in NSWorkspace.shared.runningApplications {
            guard let id = app.bundleIdentifier else { continue }
            for k in known where k.bundleID == id {
                let theirs = KeyboardShortcuts.Shortcut(k.key, modifiers: k.mods)
                if mine == theirs { out.append(Conflict(app: app, name: k.name)) }
            }
        }
        return out
    }

    /// One alert per launch at most, and never again for an app the user said to ignore.
    static func warnIfNeeded(openSettings: @escaping () -> Void) {
        let ignored = Set(AppDefaults.store.stringArray(forKey: "ignoredConflicts") ?? [])
        guard let c = current().first(where: { !ignored.contains($0.id) }) else { return }
        let alert = NSAlert()
        alert.messageText = "\(c.name) may be using \(KeyboardShortcuts.getShortcut(for: .openPanel)?.description ?? "")"
        alert.informativeText = "\(c.name) is running, and its default shortcut is the same as myPaste's \"Open myPaste\". Only one app gets the key press."
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
