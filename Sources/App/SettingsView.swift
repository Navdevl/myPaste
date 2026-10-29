import AppKit
import MyPasteCore
import KeyboardShortcuts
import ServiceManagement
import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @ObservedObject var prefs: Preferences
    @ObservedObject var model: AppModel

    var body: some View {
        TabView {
            GeneralSettings(prefs: prefs)
                .tabItem { Label("General", systemImage: "gearshape") }
            HistorySettings(prefs: prefs, model: model)
                .tabItem { Label("History", systemImage: "clock") }
            PrivacySettings(prefs: prefs)
                .tabItem { Label("Privacy", systemImage: "hand.raised") }
            PinboardSettings(model: model)
                .tabItem { Label("Pinboards", systemImage: "pin") }
        }
        .frame(width: 560, height: 430)
    }
}

private struct GeneralSettings: View {
    @ObservedObject var prefs: Preferences
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var loginError: String?
    @State private var trusted = Paster.isTrusted
    private let timer = Timer.publish(every: 1.5, on: .main, in: .common).autoconnect()

    var body: some View {
        Form {
            Section {
                Toggle("Launch at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, on in setLaunchAtLogin(on) }
                if let loginError { Text(loginError).font(.caption).foregroundStyle(.red) }
                Toggle("Paste directly into the active app", isOn: $prefs.directPaste)
                Text("Off: choosing an item only copies it; you press ⌘V yourself.").font(.caption).foregroundStyle(.secondary)
            }
            Section("Shortcuts") {
                LabeledContent("Open myPaste") { ShortcutRecorder(name: .openPanel) }
                LabeledContent("Paste Stack") { ShortcutRecorder(name: .pasteStack) }
                Text("In the panel: ←/→ select · ↑/↓ tabs · ↩ paste · ⇧↩ plain · ⌘1–9 quick paste · Space Quick Look · ⌘K actions · ⌘⇧⌫ delete · ⌘Z undo · ⌘P pin · ⌘⇧P pin to… · ⌘O open · ⌥⌘C copy plain · ⌘I info · ⌘R rename · ⌘T tags · ⌘E edit · ⌘↑/↓ first/last · Tab type filter · ⌥0–9 boards. Hold ⌘ for hints. Search: /img /link /code … @app #tag.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Permissions") {
                LabeledContent("Accessibility") {
                    HStack {
                        Text(trusted ? "Granted" : "Needed for direct paste and Paste Stack")
                            .foregroundStyle(trusted ? .green : .orange)
                        if !trusted { Button("Open Settings") { Paster.requestTrust(); Paster.openAccessibilitySettings() } }
                    }
                }
            }
        }
        .formStyle(.grouped)
        .onReceive(timer) { _ in trusted = Paster.isTrusted }
    }

    private func setLaunchAtLogin(_ on: Bool) {
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            loginError = nil
        } catch {
            loginError = error.localizedDescription
            launchAtLogin = SMAppService.mainApp.status == .enabled
        }
    }
}

private struct HistorySettings: View {
    @ObservedObject var prefs: Preferences
    @ObservedObject var model: AppModel
    @State private var confirmClear = false

    var body: some View {
        Form {
            Section("Keep unpinned history for") {
                Picker("Items", selection: $prefs.maxItems) {
                    ForEach([200, 500, 1000, 2000, 5000], id: \.self) { Text("\($0) items").tag($0) }
                }
                Picker("Days", selection: $prefs.maxDays) {
                    ForEach([1, 7, 30, 90, 365], id: \.self) { Text($0 == 1 ? "1 day" : "\($0) days").tag($0) }
                }
                Text("Whichever limit is reached first. Pinned items are never removed.").font(.caption).foregroundStyle(.secondary)
            }
            Section("Sensitive items") {
                Picker("Delete after", selection: $prefs.sensitiveMinutes) {
                    ForEach([1, 5, 10, 30, 60, 240], id: \.self) { Text("\($0) min").tag($0) }
                }
                Text("OTPs, API keys, card numbers and password-like text are blurred and expire unless pinned.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section {
                LabeledContent("Stored") { Text("\(model.items.count) items, \(model.items.filter(\.isPinned).count) pinned") }
                Button("Clear History…", role: .destructive) { confirmClear = true }
            }
        }
        .formStyle(.grouped)
        .confirmationDialog("Delete all unpinned items?", isPresented: $confirmClear) {
            Button("Clear History", role: .destructive) { try? model.store.clearHistory() }
        }
    }
}

private struct PrivacySettings: View {
    @ObservedObject var prefs: Preferences
    @State private var selection: String?

    var body: some View {
        Form {
            Section("Never record copies from") {
                List(selection: $selection) {
                    ForEach(prefs.excludedBundleIDs, id: \.self) { id in
                        HStack {
                            Image(nsImage: Visuals.shared.icon(for: id)).resizable().frame(width: 18, height: 18)
                            Text(appName(id))
                            Spacer()
                            Text(id).font(.caption).foregroundStyle(.tertiary)
                        }
                    }
                }
                .frame(height: 150)
                HStack {
                    Button("Add App…", action: addApp)
                    Button("Remove") { prefs.excludedBundleIDs.removeAll { $0 == selection } }.disabled(selection == nil)
                }
                Text("Items that apps mark as concealed or transient (most password managers do) are always skipped.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Enrichment") {
                Toggle("Fetch link previews (title and image)", isOn: $prefs.linkPreviews)
                Toggle("Recognise text in images for search", isOn: $prefs.ocr)
            }
        }
        .formStyle(.grouped)
    }

    private func appName(_ id: String) -> String {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) else { return id }
        return FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
    }

    private func addApp() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.allowsMultipleSelection = true
        guard panel.runModal() == .OK else { return }
        for url in panel.urls {
            if let id = Bundle(url: url)?.bundleIdentifier, !prefs.excludedBundleIDs.contains(id) { prefs.excludedBundleIDs.append(id) }
        }
    }
}

private struct PinboardSettings: View {
    @ObservedObject var model: AppModel

    var body: some View {
        Form {
            Section("Pinboards") {
                if model.pinboards.isEmpty { Text("No pinboards yet.").foregroundStyle(.secondary) }
                ForEach(model.pinboards) { board in
                    BoardRow(board: board, count: model.items.filter { $0.pinboardIDs.contains(board.id) }.count, store: model.store)
                }
                Button("Add Pinboard") {
                    _ = try? model.store.createPinboard(name: "Pinboard \(model.pinboards.count + 1)",
                                                    colorHex: Format.boardColors[model.pinboards.count % Format.boardColors.count])
                }
            }
        }
        .formStyle(.grouped)
    }
}

private struct BoardRow: View {
    let board: Pinboard
    let count: Int
    let store: ClipStore
    @State private var name = ""

    var body: some View {
        HStack {
            Menu {
                ForEach(Format.boardColors, id: \.self) { hex in
                    Button(hex) { try? store.updatePinboard(board.id, name: board.name, colorHex: hex) }
                }
            } label: { Circle().fill(Color(hex: board.colorHex)).frame(width: 14, height: 14) }
                .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
            TextField("Name", text: $name).textFieldStyle(.plain)
                .onSubmit { if !name.isEmpty { try? store.updatePinboard(board.id, name: name, colorHex: board.colorHex) } }
            Text("\(count) items").foregroundStyle(.secondary)
            Button(role: .destructive) { try? store.deletePinboard(board.id) } label: { Image(systemName: "trash") }
                .buttonStyle(.borderless)
        }
        .onAppear { name = board.name }
    }
}

/// Click, then press the new combo; Esc cancels. KeyboardShortcuts stores and re-registers it.
/// Not KeyboardShortcuts.Recorder: that view loads localized strings from a SwiftPM resource
/// bundle it looks for at the .app root, where a signed bundle can't hold one.
struct ShortcutRecorder: View {
    let name: KeyboardShortcuts.Name
    @State private var recording = false
    @State private var monitor: Any?
    @State private var current: KeyboardShortcuts.Shortcut?

    var body: some View {
        HStack(spacing: 6) {
            Button(recording ? "Press shortcut…" : (current?.description ?? "Record Shortcut")) {
                recording ? stop() : start()
            }
            .frame(minWidth: 120)
            if current != nil, !recording {
                Button { KeyboardShortcuts.reset(name); current = KeyboardShortcuts.getShortcut(for: name) } label: {
                    Image(systemName: "arrow.uturn.backward")
                }
                .buttonStyle(.borderless).help("Reset to default")
            }
        }
        .onAppear { current = KeyboardShortcuts.getShortcut(for: name) }
        .onDisappear(perform: stop)
    }

    private func start() {
        recording = true
        // Pause the existing binding so pressing the same combo records instead of firing it.
        KeyboardShortcuts.disable(name)
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if event.keyCode == 53 { stop(); return nil }
            let mods = event.modifierFlags.intersection([.command, .option, .control])
            // Without ⌘/⌥/⌃ a global shortcut would swallow normal typing.
            if !mods.isEmpty, let shortcut = KeyboardShortcuts.Shortcut(event: event) {
                KeyboardShortcuts.setShortcut(shortcut, for: name)
                current = shortcut
                stop()
            }
            return nil
        }
    }

    private func stop() {
        guard recording else { return }
        recording = false
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        KeyboardShortcuts.enable(name)
    }
}
