import AppKit
import MyPasteCore
import KeyboardShortcuts
import ServiceManagement
import SwiftUI
import UniformTypeIdentifiers

/// System Settings-style window: glass sidebar with coloured tiles, a gradient header per pane.
struct SettingsView: View {
    @ObservedObject var prefs: Preferences
    @ObservedObject var model: AppModel
    var onShowWelcome: () -> Void = {}
    @ObservedObject private var router = SettingsRouter.shared
    private var pane: Pane { router.pane }

    enum Pane: String, CaseIterable, Identifiable {
        case general, appearance, shortcuts, history, privacy, pinboards, backup, about
        var id: String { rawValue }

        var title: String { rawValue.capitalized }

        var symbol: String {
            switch self {
            case .general: return "gearshape.fill"
            case .appearance: return "sparkles"
            case .shortcuts: return "command"
            case .history: return "clock.fill"
            case .privacy: return "hand.raised.fill"
            case .pinboards: return "pin.fill"
            case .backup: return "externaldrive.fill"
            case .about: return "info.circle.fill"
            }
        }

        var tint: Color {
            switch self {
            case .general: return .gray
            case .appearance: return .purple
            case .shortcuts: return .indigo
            case .history: return .orange
            case .privacy: return .blue
            case .pinboards: return .pink
            case .backup: return .green
            case .about: return .teal
            }
        }

        var subtitle: String {
            switch self {
            case .general: return "Startup, pasting and permissions"
            case .appearance: return "Motion, sounds, gestures and board switching"
            case .shortcuts: return "Global hotkeys and panel keys"
            case .history: return "What's kept, and for how long"
            case .privacy: return "Excluded apps, secrets and enrichment"
            case .pinboards: return "Collections that are never pruned"
            case .backup: return "Export and import your pinboards"
            case .about: return "Version, data and logs"
            }
        }
    }

    var body: some View {
        NavigationSplitView {
            List(Pane.allCases, selection: $router.pane) { p in
                Label { Text(p.title) } icon: { Tile(symbol: p.symbol, tint: p.tint, size: 22) }
                    .tag(p)
                    .padding(.vertical, 2)
                    .accessibilityIdentifier("settings.pane.\(p.rawValue)")
            }
            .navigationSplitViewColumnWidth(190)
        } detail: {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    PaneHeader(pane: pane)
                    switch pane {
                    case .general: GeneralPane(prefs: prefs, model: model, onShowWelcome: onShowWelcome)
                    case .appearance: AppearancePane(prefs: prefs)
                    case .shortcuts: ShortcutsPane(prefs: prefs)
                    case .history: HistoryPane(prefs: prefs, model: model)
                    case .privacy: PrivacyPane(prefs: prefs)
                    case .pinboards: PinboardsPane(model: model)
                    case .backup: BackupPane(model: model)
                    case .about: AboutPane(model: model, onShowWelcome: onShowWelcome)
                    }
                }
                .padding(24)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(Color(nsColor: .windowBackgroundColor))
        }
        .frame(width: 840, height: 580)
    }
}

// MARK: Building blocks

struct Tile: View {
    let symbol: String
    let tint: Color
    var size: CGFloat = 28

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: size * 0.52, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(
                RoundedRectangle(cornerRadius: size * 0.26, style: .continuous)
                    .fill(LinearGradient(colors: [tint.opacity(0.95), tint.opacity(0.7)], startPoint: .top, endPoint: .bottom))
            )
            .shadow(color: tint.opacity(0.35), radius: 2, y: 1)
    }
}

private struct PaneHeader: View {
    let pane: SettingsView.Pane

    var body: some View {
        HStack(spacing: 14) {
            Tile(symbol: pane.symbol, tint: pane.tint, size: 44)
            VStack(alignment: .leading, spacing: 2) {
                Text(pane.title).font(.system(size: 22, weight: .bold))
                Text(pane.subtitle).foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(LinearGradient(colors: [pane.tint.opacity(0.22), pane.tint.opacity(0.05)], startPoint: .topLeading, endPoint: .bottomTrailing))
        )
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(pane.tint.opacity(0.25)))
    }
}

/// Grouped card, like a System Settings section.
private struct Card<Content: View>: View {
    var title: String?
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let title { Text(title).font(.system(size: 12, weight: .semibold)).foregroundStyle(.secondary).padding(.leading, 4) }
            VStack(alignment: .leading, spacing: 12) { content }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.primary.opacity(0.045)))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Color.primary.opacity(0.07)))
        }
    }
}

private struct Row<Trailing: View>: View {
    let title: String
    var detail: String?
    @ViewBuilder let trailing: Trailing

    var body: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                if let detail { Text(detail).font(.caption).foregroundStyle(.secondary) }
            }
            Spacer(minLength: 16)
            trailing
        }
    }
}

private struct KeyChip: View {
    let keys: String
    let label: String

    var body: some View {
        HStack(spacing: 6) {
            Text(keys).font(.system(size: 11.5, weight: .semibold, design: .rounded))
                .padding(.horizontal, 7).padding(.vertical, 3)
                .background(RoundedRectangle(cornerRadius: 5).fill(Color.primary.opacity(0.1)))
            Text(label).font(.system(size: 12)).foregroundStyle(.secondary)
        }
    }
}

// MARK: General

private struct GeneralPane: View {
    @ObservedObject var prefs: Preferences
    @ObservedObject var model: AppModel
    var onShowWelcome: () -> Void
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var loginError: String?
    @State private var trusted = Paster.isTrusted
    private let timer = Timer.publish(every: 1.5, on: .main, in: .common).autoconnect()

    var body: some View {
        OverviewCard(model: model)
        Card(title: "Startup") {
            Row(title: "Launch at login") {
                Toggle("", isOn: $launchAtLogin).toggleStyle(.switch).labelsHidden()
                    .onChange(of: launchAtLogin) { _, on in setLaunchAtLogin(on) }
            }
            if let loginError { Text(loginError).font(.caption).foregroundStyle(.red) }
            Divider()
            Row(title: "Pause capture", detail: "Stop recording copies, e.g. while screen sharing") {
                Toggle("", isOn: $prefs.capturePaused).toggleStyle(.switch).labelsHidden()
            }
        }
        Card(title: "Pasting") {
            Row(title: "Paste directly into the active app", detail: "Off: choosing an item only copies it; you press ⌘V yourself") {
                Toggle("", isOn: $prefs.directPaste).toggleStyle(.switch).labelsHidden()
            }
        }
        Card(title: "Smart actions") {
            Row(title: "Suggest actions on cards", detail: "JWT decode, GitHub PRs, timestamps, UUIDs, JSON/SQL. Press ⌘J or click the chip.") {
                Toggle("", isOn: $prefs.smartActions).toggleStyle(.switch).labelsHidden()
            }
        }
        Card(title: "Permissions") {
            Row(title: "Accessibility", detail: "Needed for direct paste") {
                if trusted {
                    Label("Granted", systemImage: "checkmark.seal.fill").foregroundStyle(.green)
                } else {
                    Button("Grant Access…") { Paster.requestTrust(); Paster.openAccessibilitySettings() }.buttonStyle(.borderedProminent)
                }
            }
        }
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

private struct OverviewCard: View {
    @ObservedObject var model: AppModel
    @State private var storage = "…"

    private var topApps: [(id: String, count: Int)] {
        Dictionary(grouping: model.items.compactMap(\.sourceBundleID), by: { $0 })
            .map { (id: $0.key, count: $0.value.count) }.sorted { $0.count > $1.count }.prefix(4).map { $0 }
    }

    var body: some View {
        HStack(spacing: 12) {
            Stat(value: "\(model.items.count)", label: "Items", tint: .indigo)
            Stat(value: "\(model.items.filter(\.isPinned).count)", label: "Pinned", tint: .pink)
            Stat(value: "\(model.items.filter(\.isSensitive).count)", label: "Sensitive", tint: .orange)
            Stat(value: storage, label: "On disk", tint: .green)
            VStack(alignment: .leading, spacing: 6) {
                Text("Top sources").font(.caption).foregroundStyle(.secondary)
                HStack(spacing: -6) {
                    ForEach(topApps, id: \.id) { app in
                        Image(nsImage: Visuals.shared.icon(for: app.id)).resizable().frame(width: 30, height: 30)
                            .help("\(app.count) items")
                    }
                }
            }
            .padding(12)
            .frame(minWidth: 130, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 12).fill(Color.primary.opacity(0.045)))
        }
        .fixedSize(horizontal: false, vertical: true)
        .task { storage = await Self.diskUsage() }
    }

    static func diskUsage() async -> String {
        await Task.detached {
            let dir = AppDelegate.dataDirectory
            let files = FileManager.default.enumerator(at: dir, includingPropertiesForKeys: [.fileSizeKey])
            var total: Int64 = 0
            while let url = files?.nextObject() as? URL {
                total += Int64((try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
            }
            return ByteCountFormatter.string(fromByteCount: total, countStyle: .file)
        }.value
    }
}

private struct Stat: View {
    let value: String
    let label: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value).font(.system(size: 22, weight: .bold, design: .rounded)).foregroundStyle(tint).lineLimit(1).minimumScaleFactor(0.6)
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
        .padding(12)
        .frame(minWidth: 70, maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12).fill(tint.opacity(0.1)))
    }
}

// MARK: Appearance

private struct AppearancePane: View {
    @ObservedObject var prefs: Preferences

    var body: some View {
        Card(title: "Moving between cards") {
            toggle("Gliding highlight", "The selection ring slides from card to card instead of jumping", $prefs.glideSelection, "appearance.glide")
            Divider()

            toggle("Trackpad haptics", "A light tap on each selection change (Force Touch trackpads)", $prefs.haptics, "appearance.haptics")
        }
        Card(title: "Hints") {
            toggle("Key hints along the bottom", "A quiet line of the usual shortcuts (paste, pin, rename, info, actions, delete) under the cards. ⌘M shows the rest", $prefs.showHintLine, "appearance.hints")
        }
        Card(title: "Opening the strip") {
            toggle("Staggered card entrance", "Cards spring in one after another when the strip opens. Off: they're simply there, which is faster", $prefs.entranceAnimation, "appearance.entrance")
        }
        Card(title: "Sounds") {
            toggle("Sound effects", "Short, quiet clicks generated by myPaste", $prefs.soundsEnabled, "appearance.sounds")
            if prefs.soundsEnabled {
                Divider()
                Row(title: "Volume") {
                    HStack(spacing: 8) {
                        Image(systemName: "speaker.fill").foregroundStyle(.secondary)
                        Slider(value: $prefs.soundVolume, in: 0.05...1) { editing in if !editing { SoundFX.shared.play(.paste, force: true) } }
                            .frame(width: 180)
                        Image(systemName: "speaker.wave.3.fill").foregroundStyle(.secondary)
                    }
                }
                ForEach(SoundFX.Effect.allCases, id: \.self) { effect in
                    Divider()
                    SoundRow(effect: effect, prefs: prefs, enabled: binding(for: effect))
                }
            }
        }
        Card(title: "Quick pin (double-tap ⌃)") {
            toggle("In the strip", "Double-tap Control to pin the selected card", $prefs.doubleCtrlInPanel, "appearance.ctrlPanel")
            Divider()
            toggle("Anywhere", "Double-tap Control in any app to pin what you copied last", $prefs.doubleCtrlGlobal, "appearance.ctrlGlobal")
        }
        Card(title: "Pinboards") {
            toggle("Open shortcut cycles boards", "Pressing ⇧⌘C again while the strip is open moves to the next board", $prefs.hotkeyCyclesTabs, "appearance.cycle")
            Divider()
            toggle("Search everywhere", "Searching from a pinboard also finds History and other boards. Off: search stays inside the open tab", $prefs.searchEverywhere, "appearance.searchEverywhere")
            Text("Also: ⌃Tab / ⌃⇧Tab next and previous board · ⌥0–9 jumps straight to a board.")
                .font(.caption).foregroundStyle(.secondary)
        }
        Button("Turn everything off (1.1 behaviour)") {
            prefs.glideSelection = false; prefs.haptics = false
            prefs.doubleCtrlInPanel = false; prefs.doubleCtrlGlobal = false; prefs.hotkeyCyclesTabs = false
            prefs.soundsEnabled = false
        }
        .buttonStyle(.link)
    }

    private func binding(for e: SoundFX.Effect) -> Binding<Bool> {
        switch e {
        case .copy: return $prefs.soundCopy
        case .paste: return $prefs.soundPaste
        case .delete: return $prefs.soundDelete
        }
    }

    private func toggle(_ title: String, _ detail: String, _ on: Binding<Bool>, _ id: String) -> some View {
        Row(title: title, detail: detail) {
            Toggle("", isOn: on).toggleStyle(.switch).labelsHidden().accessibilityIdentifier(id)
        }
    }
}

/// One event's sound: built-in pack menu (designed-for sounds first), custom file, preview, on/off.
private struct SoundRow: View {
    let effect: SoundFX.Effect
    @ObservedObject var prefs: Preferences
    @Binding var enabled: Bool
    @State private var error: String?

    private var selection: Binding<String> {
        Binding(get: { SoundFX.shared.selection(for: effect) },
                set: { SoundFX.shared.setSelection($0, for: effect); SoundFX.shared.play(effect, force: true) })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 10) {
                Text(effect.label)
                Spacer(minLength: 12)
                Picker("", selection: selection) {
                    Section("Made for \(effect.label.lowercased())") {
                        ForEach(SoundFX.builtIns.filter { $0.suits == effect }) { Text($0.name).tag($0.id) }
                    }
                    Section("Other sounds") {
                        ForEach(SoundFX.builtIns.filter { $0.suits != effect }) { Text($0.name).tag($0.id) }
                    }
                    if let name = SoundFX.shared.customName(for: effect), SoundFX.shared.customFile(for: effect) != nil {
                        Section("Your file") { Text(name).tag(SoundFX.customID) }
                    }
                }
                .labelsHidden().frame(width: 190)
                .accessibilityIdentifier("appearance.sound.\(effect.rawValue).menu")
                Button("Choose…") { choose() }
                    .accessibilityIdentifier("appearance.sound.\(effect.rawValue).choose")
                Button { SoundFX.shared.play(effect, force: true) } label: { Image(systemName: "play.circle.fill").font(.title3) }
                    .buttonStyle(.borderless).help("Play")
                    .accessibilityIdentifier("appearance.sound.\(effect.rawValue).play")
                Toggle("", isOn: $enabled).toggleStyle(.switch).labelsHidden()
            }
            if let error { Text(error).font(.caption).foregroundStyle(.red) }
        }
    }

    private func choose() {
        let file: URL
        if let testFile = UITest.soundFile {
            file = testFile
        } else {
            let panel = NSOpenPanel()
            panel.allowedContentTypes = [.audio]
            panel.message = "Choose a short sound for \(effect.label.lowercased()) (under a second works best)"
            guard panel.runModal() == .OK, let picked = panel.url else { return }
            file = picked
        }
        do {
            try SoundFX.shared.installCustom(file, for: effect)
            error = nil
            prefs.objectWillChange.send()
            SoundFX.shared.play(effect, force: true)
        } catch {
            self.error = "Couldn't use that file: \(error.localizedDescription)"
            AppLog.error("Custom sound rejected", error)
        }
    }
}

// MARK: Shortcuts

private struct ShortcutsPane: View {
    @ObservedObject var prefs: Preferences

    private let panelKeys: [(String, String)] = [
        ("← →", "Select"), ("↑ ↓", "Pinboards"), ("↩", "Paste"), ("⇧↩", "Paste plain"), ("⌘1–9", "Quick paste"),
        ("⌘/", "Show shortcuts"), ("hold ⇧", "Plain mode"), ("Space", "Quick Look"), ("⌘J", "Smart action"), ("⌘K", "Actions"), ("⌘M", "Card menu"),
        ("⌘⇧⌫", "Delete"), ("⌘Z", "Undo delete"), ("⌘P", "Pin"), ("⌘⇧P", "Pin to…"), ("⌃⌃", "Quick pin"), ("⌘O", "Open"),
        ("⌘C", "Copy"), ("⌥⌘C", "Copy plain"), ("⌘I", "Info"), ("⌘R", "Rename"), ("⌘T", "Tags"), ("⌘E", "Edit"),
        ("⌘↑ ⌘↓", "First / last"), ("Tab", "Type filter"), ("⌃Tab", "Next board"), ("⇧⌘C again", "Next board"),
        ("⌥0–9", "Jump to board"), ("Esc", "Close"),
    ]

    var body: some View {
        Card(title: "Global") {
            Row(title: "Open myPaste") { ShortcutRecorder(name: .openPanel) }
        }
        Card(title: "In the panel") {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), alignment: .leading)], alignment: .leading, spacing: 10) {
                ForEach(panelKeys, id: \.0) { KeyChip(keys: $0.0, label: $0.1) }
            }
        }
        Card(title: "Search") {
            HStack(spacing: 14) {
                KeyChip(keys: "/img /link /code…", label: "Type")
                KeyChip(keys: "@slack", label: "Source app")
                KeyChip(keys: "#tag", label: "Tag")
            }
        }
    }
}

// MARK: History

private struct HistoryPane: View {
    @ObservedObject var prefs: Preferences
    @ObservedObject var model: AppModel
    @State private var confirmClear = false

    var body: some View {
        Card(title: "Keep unpinned history for") {
            Row(title: "At most") {
                Picker("", selection: $prefs.maxItems) {
                    ForEach([200, 500, 1000, 2000, 5000], id: \.self) { Text("\($0) items").tag($0) }
                }.labelsHidden().fixedSize()
            }
            Divider()
            Row(title: "For up to") {
                Picker("", selection: $prefs.maxDays) {
                    ForEach([1, 7, 30, 90, 365], id: \.self) { Text($0 == 1 ? "1 day" : "\($0) days").tag($0) }
                }.labelsHidden().fixedSize()
            }
            Text("Whichever limit is reached first. Pinned items are never removed.").font(.caption).foregroundStyle(.secondary)
        }
        Card(title: "Sensitive items") {
            Row(title: "Delete after", detail: "OTPs, keys, cards, PAN/Aadhaar/account numbers, password-like text") {
                Picker("", selection: $prefs.sensitiveMinutes) {
                    ForEach([1, 5, 10, 30, 60, 240], id: \.self) { Text("\($0) min").tag($0) }
                }.labelsHidden().fixedSize()
            }
        }
        Card {
            Row(title: "Clear history", detail: "Deletes every unpinned item. Pinboards stay.") {
                Button("Clear…", role: .destructive) { confirmClear = true }
            }
        }
        .confirmationDialog("Delete all unpinned items?", isPresented: $confirmClear) {
            Button("Clear History", role: .destructive) { try? model.store.clearHistory() }
        }
    }
}

// MARK: Privacy

private struct PrivacyPane: View {
    @ObservedObject var prefs: Preferences
    @State private var selection: String?

    var body: some View {
        Card(title: "Never record copies from") {
            ForEach(prefs.excludedBundleIDs, id: \.self) { id in
                HStack {
                    Image(nsImage: Visuals.shared.icon(for: id)).resizable().frame(width: 22, height: 22)
                    Text(appName(id))
                    Text(id).font(.caption).foregroundStyle(.tertiary)
                    Spacer()
                    Button { prefs.excludedBundleIDs.removeAll { $0 == id } } label: { Image(systemName: "minus.circle.fill") }
                        .buttonStyle(.plain).foregroundStyle(.secondary)
                }
            }
            Button("Add App…", action: addApp)
            Text("Items that apps mark as concealed or transient (most password managers do) are always skipped.")
                .font(.caption).foregroundStyle(.secondary)
        }
        Card(title: "Sensitive detection") {
            Label("PAN, Aadhaar, IFSC, UPI IDs, account and card numbers are masked in previews (e.g. ••••1234) and expire.", systemImage: "lock.shield.fill")
                .font(.callout)
            Label("OTPs, API keys, JWTs, private keys and password-like text are blurred and expire.", systemImage: "eye.slash.fill")
                .font(.callout)
        }
        Card(title: "Enrichment") {
            Row(title: "Fetch link previews", detail: "Title, image and favicon for copied URLs") {
                Toggle("", isOn: $prefs.linkPreviews).toggleStyle(.switch).labelsHidden()
            }
            Divider()
            Row(title: "Recognise text in images", detail: "On-device (Vision); makes screenshots searchable") {
                Toggle("", isOn: $prefs.ocr).toggleStyle(.switch).labelsHidden()
            }
        }
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

// MARK: Pinboards

private struct PinboardsPane: View {
    @ObservedObject var model: AppModel

    var body: some View {
        Card {
            if model.pinboards.isEmpty { Text("No pinboards yet. Press ⌘P on a card to create one.").foregroundStyle(.secondary) }
            ForEach(model.pinboards) { board in
                BoardRow(board: board, count: model.items.filter { $0.pinboardIDs.contains(board.id) }.count, store: model.store)
                if board.id != model.pinboards.last?.id { Divider() }
            }
            Button {
                _ = try? model.store.createPinboard(name: "Pinboard \(model.pinboards.count + 1)",
                                                    colorHex: Format.boardColors[model.pinboards.count % Format.boardColors.count])
            } label: { Label("Add Pinboard", systemImage: "plus") }
        }
    }
}

private struct BoardRow: View {
    let board: Pinboard
    let count: Int
    let store: ClipStore
    @State private var name = ""

    var body: some View {
        HStack(spacing: 10) {
            Menu {
                ForEach(Format.boardColors, id: \.self) { hex in
                    Button { try? store.updatePinboard(board.id, name: board.name, colorHex: hex) } label: {
                        Label(hex, systemImage: "circle.fill")
                    }
                }
            } label: { Circle().fill(Color(hex: board.colorHex)).frame(width: 16, height: 16) }
                .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
            TextField("Name", text: $name).textFieldStyle(.plain).font(.body.weight(.medium))
                .onSubmit { if !name.isEmpty { try? store.updatePinboard(board.id, name: name, colorHex: board.colorHex) } }
            Text("\(count) items").foregroundStyle(.secondary)
            Button(role: .destructive) { try? store.deletePinboard(board.id) } label: { Image(systemName: "trash") }
                .buttonStyle(.borderless)
        }
        .onAppear { name = board.name }
    }
}

// MARK: Backup

private struct BackupPane: View {
    @ObservedObject var model: AppModel
    @State private var includeHistory = false
    @State private var status: String?
    @State private var busy = false

    var body: some View {
        Card(title: "Export") {
            Row(title: "Include unpinned history", detail: "Pinboards, tags and images are always included") {
                Toggle("", isOn: $includeHistory).toggleStyle(.switch).labelsHidden()
                    .accessibilityIdentifier("backup.includeHistory")
            }
            Text("Sensitive items (OTPs, keys, PAN, Aadhaar, account numbers…) are never exported.").font(.caption).foregroundStyle(.secondary)
            Button { export() } label: { Label("Export Backup…", systemImage: "square.and.arrow.up") }
                .buttonStyle(.borderedProminent).disabled(busy)
                .accessibilityIdentifier("backup.export")
        }
        Card(title: "Import") {
            Text("Merges into your current data: pinboards by name, items by content. Duplicates are skipped.")
                .font(.callout).foregroundStyle(.secondary)
            Button { importBackup() } label: { Label("Import Backup…", systemImage: "square.and.arrow.down") }.disabled(busy)
                .accessibilityIdentifier("backup.import")
        }
        if let status {
            Label(status, systemImage: "checkmark.circle.fill").foregroundStyle(.green).font(.callout)
                .accessibilityIdentifier("backup.status")
        }
    }

    private func export() {
        let url: URL
        if let testURL = UITest.saveURL {
            url = testURL
        } else {
            let panel = NSSavePanel()
            panel.nameFieldStringValue = "myPaste Backup \(Date().formatted(.iso8601.year().month().day())).mypaste"
            panel.allowedContentTypes = [UTType(filenameExtension: "mypaste") ?? .zip]
            guard panel.runModal() == .OK, let picked = panel.url else { return }
            url = picked
        }
        busy = true
        let store = model.store, history = includeHistory
        Task.detached {
            let result = Result { try BackupArchive.export(store: store, includeHistory: history, to: url) }
            await MainActor.run {
                busy = false
                switch result {
                case .success(let s): status = "Exported \(s.items) items and \(s.pinboards) pinboards" + (s.skippedSensitive > 0 ? " (\(s.skippedSensitive) sensitive skipped)" : "")
                case .failure(let e): status = nil; AppLog.error("Export failed", e); NSAlert(error: e).runModal()
                }
            }
        }
    }

    private func importBackup() {
        let url: URL
        if let testURL = UITest.openURL {
            url = testURL
        } else {
            let panel = NSOpenPanel()
            panel.allowedContentTypes = [UTType(filenameExtension: "mypaste") ?? .zip, .zip]
            guard panel.runModal() == .OK, let picked = panel.url else { return }
            url = picked
        }
        busy = true
        let store = model.store
        Task.detached {
            let result = Result { try BackupArchive.importArchive(url, into: store) }
            await MainActor.run {
                busy = false
                switch result {
                case .success(let s): status = "Imported \(s.items) items" + (s.skippedDuplicates > 0 ? ", \(s.skippedDuplicates) already here" : "")
                case .failure(let e): status = nil; AppLog.error("Import failed", e); NSAlert(error: e).runModal()
                }
            }
        }
    }
}

// MARK: About

private struct AboutPane: View {
    @ObservedObject var model: AppModel
    var onShowWelcome: () -> Void
    @State private var crashes = AppLog.systemCrashReports

    var body: some View {
        Card {
            HStack(spacing: 14) {
                Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 64, height: 64)
                VStack(alignment: .leading, spacing: 3) {
                    Text("myPaste").font(.title2.bold())
                    Text("Version \(AppVersion.display) · local-only clipboard manager")
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Show Welcome…", action: onShowWelcome)
            }
        }
        Card(title: "Data") {
            Row(title: "Data folder", detail: AppDelegate.dataDirectory.path.replacingOccurrences(of: NSHomeDirectory(), with: "~")) {
                Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([AppDelegate.dataDirectory]) }
            }
        }
        Card(title: "Diagnostics") {
            Row(title: "App log", detail: "Errors and maintenance events. Never contains clipboard contents.") {
                Button("Open Logs") {
                    try? FileManager.default.createDirectory(at: AppLog.directory, withIntermediateDirectories: true)
                    NSWorkspace.shared.open(AppLog.directory)
                }
            }
            Divider()
            Row(title: "Crash reports", detail: crashes.isEmpty ? "None. Nice." : "\(crashes.count) from macOS, newest \(crashes[0].lastPathComponent)") {
                if let latest = crashes.first { Button("Show Latest") { NSWorkspace.shared.activateFileViewerSelecting([latest]) } }
            }
        }
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
        // (stop() re-enables only names that are switched on.)
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
