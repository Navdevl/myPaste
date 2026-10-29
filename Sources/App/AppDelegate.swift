import AppKit
import MyPasteCore
import KeyboardShortcuts
import ServiceManagement
import SwiftUI

@main
enum MyPasteMain {
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        withExtendedLifetime(delegate) { app.run() }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let prefs = Preferences.shared
    private var store: ClipStore!
    private var model: AppModel!
    private var monitor: PasteboardMonitor!
    private var panel: PanelController!
    private var stack: PasteStack!
    private var enrichment: Enrichment!
    private var statusItem: NSStatusItem!
    private var settingsWindow: NSWindow?
    private var pruneTimer: Timer?

    /// MYPASTE_DATA_DIR lets a test instance run against a throwaway database.
    static var dataDirectory: URL {
        if let custom = ProcessInfo.processInfo.environment["MYPASTE_DATA_DIR"] {
            return URL(fileURLWithPath: custom, isDirectory: true)
        }
        return FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("myPaste", isDirectory: true)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        do {
            store = try ClipStore(directory: Self.dataDirectory)
        } catch {
            let alert = NSAlert()
            alert.messageText = "myPaste couldn't open its database"
            alert.informativeText = "\(error)"
            alert.runModal()
            NSApp.terminate(nil)
            return
        }
        model = AppModel(store: store, prefs: prefs)
        store.onChange = { [weak self] in self?.model.scheduleReload() }
        monitor = PasteboardMonitor(prefs: prefs)
        enrichment = Enrichment(store: store, prefs: prefs)
        stack = PasteStack(store: store, monitor: monitor)
        panel = PanelController(model: model)

        monitor.onCapture = { [weak self] capture in self?.didCapture(capture) }
        model.onPaste = { [weak self] item, plain in self?.paste(item, plain: plain) }
        model.onCopy = { [weak self] item, plain in self?.copy(item, plain: plain) }
        model.onOpen = { [weak self] item in self?.open(item) }
        model.onAddToStack = { [weak self] item in self?.panel.hide(); self?.stack.append(item) }
        model.onOpenSettings = { [weak self] in self?.openSettings() }

        registerHotKeys()
        setupStatusItem()
        monitor.start()

        _ = try? store.prune(prefs.retention)
        pruneTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            guard let self else { return }
            _ = try? self.store.prune(self.prefs.retention)
        }
        enrichment.backfill()

        // Scripting hook: `notifyutil`-style toggle from other tools, e.g. a Raycast script.
        DistributedNotificationCenter.default().addObserver(forName: .init("local.mypaste.toggle"), object: nil, queue: .main) { [weak self] _ in
            self?.panel.toggle()
        }

        if !UserDefaults.standard.bool(forKey: "didPromptAccessibility") {
            UserDefaults.standard.set(true, forKey: "didPromptAccessibility")
            if !Paster.isTrusted { Paster.requestTrust() }
        }

        // Launch at login defaults to on, but only for the installed copy, not build/ or test runs.
        let installed = Bundle.main.bundlePath.hasPrefix("/Applications/")
            || Bundle.main.bundlePath.hasPrefix(NSHomeDirectory() + "/Applications/")
        if installed, !UserDefaults.standard.bool(forKey: "didSetupLoginItem") {
            UserDefaults.standard.set(true, forKey: "didSetupLoginItem")
            try? SMAppService.mainApp.register()
        }
    }

    // MARK: Capture / paste

    private func didCapture(_ capture: NewCapture) {
        guard let id = try? store.insert(capture, sensitiveTTL: prefs.sensitiveTTL) else { return }
        _ = try? store.prune(prefs.retention)
        guard let item = try? store.item(id: id) else { return }
        enrichment.process(item)
        if stack.isActive { stack.append(item) }
    }

    private func paste(_ item: ClipItem, plain: Bool) {
        Paster.write(item, store: store, plainText: plain)
        monitor.skipCurrent()
        try? store.touch(item.id)
        panel.hideNow()
        guard prefs.directPaste else { return }
        guard Paster.isTrusted else {
            Paster.requestTrust()
            return
        }
        // Give the window server a beat to return key focus to the previous app.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) { Paster.postCommandV() }
    }

    private func copy(_ item: ClipItem, plain: Bool) {
        Paster.write(item, store: store, plainText: plain)
        monitor.skipCurrent()
        try? store.touch(item.id)
        panel.hide()
    }

    /// ⌘O: links open in the default browser, files are revealed in Finder.
    private func open(_ item: ClipItem) {
        switch item.kind {
        case .link:
            guard let url = URL(string: (item.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)) else { return NSSound.beep() }
            panel.hide()
            NSWorkspace.shared.open(url)
        case .file:
            panel.hide()
            NSWorkspace.shared.activateFileViewerSelecting(item.filePaths.map { URL(fileURLWithPath: $0) })
        case .email:
            if let url = URL(string: "mailto:" + (item.text ?? "")) { panel.hide(); NSWorkspace.shared.open(url) }
        default:
            NSSound.beep()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        model?.commitPendingDeletes()
    }

    // MARK: Hotkeys

    /// KeyboardShortcuts re-binds automatically when the user records a new combo in Settings.
    private func registerHotKeys() {
        KeyboardShortcuts.onKeyDown(for: .openPanel) { [weak self] in self?.panel.toggle() }
        KeyboardShortcuts.onKeyDown(for: .pasteStack) { [weak self] in self?.stack.toggle() }
    }

    // MARK: Status item

    private var pauseItem: NSMenuItem!
    private var openItem: NSMenuItem!
    private var stackItem: NSMenuItem!

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName: "doc.on.clipboard", accessibilityDescription: "myPaste")
        let menu = NSMenu()
        menu.delegate = self
        openItem = menu.addItem(withTitle: "Open myPaste", action: #selector(openPanel), keyEquivalent: "")
        stackItem = menu.addItem(withTitle: "Start Paste Stack", action: #selector(toggleStack), keyEquivalent: "")
        pauseItem = menu.addItem(withTitle: "Pause Capture", action: #selector(togglePause), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit myPaste", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        for item in menu.items where item.action != #selector(NSApplication.terminate(_:)) { item.target = self }
        statusItem.menu = menu
        updateMenuShortcuts()
        updateStatusIcon()
    }

    func menuWillOpen(_ menu: NSMenu) {
        pauseItem.title = prefs.capturePaused ? "Resume Capture" : "Pause Capture"
        stackItem.title = stack.isActive ? "End Paste Stack" : "Start Paste Stack"
        updateMenuShortcuts()
    }

    private func updateMenuShortcuts() {
        openItem?.title = "Open myPaste    " + (KeyboardShortcuts.getShortcut(for: .openPanel)?.description ?? "")
        stackItem?.toolTip = KeyboardShortcuts.getShortcut(for: .pasteStack)?.description
    }

    private func updateStatusIcon() {
        let symbol = prefs.capturePaused ? "pause.circle" : "doc.on.clipboard"
        statusItem.button?.image = NSImage(systemSymbolName: symbol, accessibilityDescription: "myPaste")
    }

    @objc private func openPanel() {
        // Let the menu finish closing first, or the panel resigns key immediately.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { self.panel.show() }
    }

    @objc private func toggleStack() { stack.toggle() }

    @objc private func togglePause() {
        prefs.capturePaused.toggle()
        updateStatusIcon()
        model.objectWillChange.send()
    }

    @objc private func openSettings() {
        panel.hide()
        if settingsWindow == nil {
            let view = SettingsView(prefs: prefs, model: model)
            let window = NSWindow(contentViewController: NSHostingController(rootView: view))
            window.title = "myPaste Settings"
            window.styleMask = [.titled, .closable]
            window.isReleasedWhenClosed = false
            window.center()
            settingsWindow = window
        }
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.makeKeyAndOrderFront(nil)
    }
}
