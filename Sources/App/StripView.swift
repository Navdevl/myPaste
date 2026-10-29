import SwiftUI
import MyPasteCore

struct StripView: View {
    @EnvironmentObject var model: AppModel
    @FocusState private var searchFocused: Bool

    var body: some View {
        ZStack {
            VStack(spacing: 10) {
                topBar
                cards
            }
            // On an inner view: an identifier on the root propagates to every unlabelled descendant,
            // which hid the shortcut bar's and toast's own identifiers from UI tests.
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("strip")
            .padding(.top, 12)
            .padding(.bottom, 6)
            if let editor = model.editor {
                Color.black.opacity(0.25).onTapGesture { model.editor = nil }
                switch editor {
                case .pinPicker(let id): PinPickerView(itemID: id)
                case .info(let id): InfoView(itemID: id)
                case .actions(let id): ActionsView(itemID: id)
                default: EditorView()
                }
            }
        }
        .overlay(alignment: .bottom) {
            if model.editMode && model.editor == nil {
                ShortcutBar().padding(.bottom, 8).transition(.move(edge: .bottom).combined(with: .opacity))
                    .accessibilityElement(children: .contain)
                    .accessibilityIdentifier("shortcut.bar")
            } else if model.plainMode && model.editor == nil {
                HStack(spacing: 8) {
                    Image(systemName: "textformat.size.smaller").foregroundStyle(.orange)
                    Text("Plain-text mode").font(.system(size: 12, weight: .semibold))
                    Text("↩ · ⌘1–9 · double-click paste without formatting · release ⇧ to cancel")
                        .font(.system(size: 12)).foregroundStyle(.secondary)
                }
                .padding(.horizontal, 16).padding(.vertical, 9)
                .glassSurface(cornerRadius: 16)
                .padding(.bottom, 8)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .overlay(alignment: .top) {
            if let toast = model.toast {
                Text(toast).font(.system(size: 12, weight: .semibold))
                    .padding(.horizontal, 14).padding(.vertical, 7)
                    .glassSurface(cornerRadius: 14)
                    .padding(.top, 10)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier("toast")
            }
        }
        .onChange(of: model.focusToken) { _, _ in searchFocused = true }
        .onAppear { searchFocused = true }
    }

    // MARK: Top bar

    private var topBar: some View {
        HStack(spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Search · /img /link /code · @app · #tag", text: $model.search)
                    .textFieldStyle(.plain).font(.system(size: 14)).focused($searchFocused)
                    .frame(width: 280)
                if !model.search.isEmpty {
                    Button { model.search = "" } label: { Image(systemName: "xmark.circle.fill") }
                        .buttonStyle(.plain).foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 10).padding(.vertical, 6)
            .background(.quaternary.opacity(0.6), in: RoundedRectangle(cornerRadius: 8))

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    TabChip(title: "History", color: nil, symbol: "clock", active: model.tab == .history) { model.tab = .history }
                    ForEach(model.pinboards) { board in
                        TabChip(title: board.name, color: Color(hex: board.colorHex), symbol: nil, active: model.tab == .board(board.id)) {
                            model.tab = .board(board.id)
                        }
                        .dropDestination(for: String.self) { ids, _ in
                            for id in ids.compactMap(Int64.init) { try? model.store.pin(id, to: board.id) }
                            return true
                        }
                        .contextMenu {
                            Button("Edit Pinboard…") { model.editor = .editBoard(board.id) }
                            Button("Delete Pinboard", role: .destructive) { try? model.store.deletePinboard(board.id) }
                        }
                    }
                    Button { model.editor = .newBoard(pinItem: nil) } label: {
                        Image(systemName: "plus").font(.system(size: 12, weight: .semibold)).frame(width: 26, height: 26)
                    }
                    .buttonStyle(.plain).background(.quaternary.opacity(0.5), in: Circle())
                    .help("New pinboard (drag cards onto a pinboard to pin)")
                }
            }

            Spacer(minLength: 8)
            filterMenus
            Button { model.onOpenSettings?() } label: { Image(systemName: "gearshape").font(.system(size: 14)) }
                .buttonStyle(.plain).foregroundStyle(.secondary).help("Settings (⌘,)")
        }
        .padding(.horizontal, 20)
    }

    private var filterMenus: some View {
        HStack(spacing: 6) {
            Menu {
                Button("All Types") { model.kindFilter = .all }
                Divider()
                ForEach(ContentKind.allCases, id: \.self) { k in
                    Button { model.kindFilter = .kind(k) } label: { Label(k.label, systemImage: k.symbol) }
                }
                Divider()
                Button { model.kindFilter = .sensitive } label: { Label("Sensitive", systemImage: "lock") }
            } label: {
                FilterLabel(text: kindLabel, symbol: "line.3.horizontal.decrease.circle", active: model.kindFilter != .all)
            }
            .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()

            Menu {
                Button("All Apps") { model.appFilter = nil }
                Divider()
                ForEach(model.sourceApps, id: \.id) { app in
                    Button { model.appFilter = app.id } label: {
                        Label { Text(app.name) } icon: { Image(nsImage: Visuals.shared.icon(for: app.id)) }
                    }
                }
            } label: {
                FilterLabel(text: appLabel, symbol: "app.dashed", active: model.appFilter != nil)
            }
            .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()

            if model.kindFilter != .all || model.appFilter != nil {
                Button("Clear") { model.kindFilter = .all; model.appFilter = nil }
                    .buttonStyle(.plain).font(.system(size: 12)).foregroundStyle(.secondary)
            }
        }
    }

    private var kindLabel: String {
        switch model.kindFilter {
        case .all: return "Type"
        case .kind(let k): return k.label
        case .sensitive: return "Sensitive"
        }
    }

    private var appLabel: String {
        guard let id = model.appFilter else { return "App" }
        return model.sourceApps.first { $0.id == id }?.name ?? id
    }

    // MARK: Cards

    private var cards: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 14) {
                    ForEach(Array(model.visible.enumerated()), id: \.element.id) { idx, item in
                        CardView(item: item, index: idx).id(item.id)
                            .transition(.asymmetric(insertion: .scale(scale: 0.85).combined(with: .opacity),
                                                    removal: .scale(scale: 0.5).combined(with: .opacity)))
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 12) // headroom for the edit-mode ✕ and ⌘N badges
            }
            .overlay {
                if model.visible.isEmpty { emptyState }
            }
            .onChange(of: model.selectedID) { _, id in
                guard let id else { return }
                withAnimation(.easeOut(duration: 0.15)) { proxy.scrollTo(id) }
            }
        }
        .frame(height: CardView.size.height + 24)
    }

    private var emptyState: some View {
        VStack(spacing: 6) {
            Image(systemName: model.search.isEmpty ? "doc.on.clipboard" : "magnifyingglass")
                .font(.system(size: 30)).foregroundStyle(.tertiary)
            Text(emptyText).foregroundStyle(.secondary)
        }
    }

    private var emptyText: String {
        if !model.search.isEmpty { return "No matches for “\(model.search)”" }
        if case .board = model.tab { return "Drag cards here, or right-click a card → Pin to" }
        return model.prefs.capturePaused ? "Capture is paused" : "Copy something and it will show up here"
    }
}

private struct TabChip: View {
    let title: String
    let color: Color?
    let symbol: String?
    let active: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                if let color { Circle().fill(color).frame(width: 8, height: 8) }
                if let symbol { Image(systemName: symbol).font(.system(size: 11)) }
                Text(title).font(.system(size: 12.5, weight: active ? .semibold : .regular)).lineLimit(1)
            }
            .padding(.horizontal, 11).padding(.vertical, 5)
            .background(active ? AnyShapeStyle(Color.accentColor.opacity(0.22)) : AnyShapeStyle(.quaternary.opacity(0.5)), in: Capsule())
            .overlay(Capsule().strokeBorder(active ? Color.accentColor.opacity(0.6) : .clear))
        }
        .buttonStyle(.plain)
    }
}

private struct FilterLabel: View {
    let text: String
    let symbol: String
    let active: Bool

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: symbol)
            Text(text).lineLimit(1)
        }
        .font(.system(size: 12))
        .padding(.horizontal, 9).padding(.vertical, 5)
        .background(active ? AnyShapeStyle(Color.accentColor.opacity(0.22)) : AnyShapeStyle(.quaternary.opacity(0.5)), in: Capsule())
    }
}

// MARK: Editors

/// Inline editor overlay. Kept inside the panel rather than as a sheet, so the panel never loses key status.
struct EditorView: View {
    @EnvironmentObject var model: AppModel
    @State private var text = ""
    @State private var color = Format.boardColors[0]
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title).font(.headline)
            switch model.editor {
            case .editText:
                TextEditor(text: $text).font(.system(size: 13, design: .monospaced))
                    .focused($focused).frame(width: 520, height: 150)
                    .scrollContentBackground(.hidden).padding(6)
                    .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 6))
            default:
                TextField(placeholder, text: $text).textFieldStyle(.roundedBorder).focused($focused)
                    .frame(width: 360).onSubmit(save)
            }
            if isBoardEditor {
                HStack(spacing: 8) {
                    ForEach(Format.boardColors, id: \.self) { hex in
                        Circle().fill(Color(hex: hex)).frame(width: 20, height: 20)
                            .overlay(Circle().strokeBorder(.white, lineWidth: color == hex ? 2.5 : 0))
                            .onTapGesture { color = hex }
                    }
                }
            }
            if case .tags = model.editor, !existingTags.isEmpty {
                Text("Existing: " + existingTags.map { "#" + $0 }.joined(separator: " "))
                    .font(.caption).foregroundStyle(.secondary).lineLimit(2).frame(width: 360, alignment: .leading)
            }
            HStack {
                Spacer()
                Button("Cancel") { model.editor = nil }.keyboardShortcut(.cancelAction)
                Button("Save", action: save).keyboardShortcut(.defaultAction)
            }
        }
        .fixedSize()
        .padding(18)
        .background(Color.solidSurface, in: RoundedRectangle(cornerRadius: 14))
        .shadow(radius: 20)
        .onAppear(perform: load)
    }

    private var isBoardEditor: Bool {
        switch model.editor { case .newBoard, .editBoard: return true; default: return false }
    }

    private var existingTags: [String] { (try? model.store.allTags()) ?? [] }

    private var title: String {
        switch model.editor {
        case .rename: return "Rename"
        case .tags: return "Tags"
        case .editText: return "Edit Text"
        case .newBoard: return "New Pinboard"
        case .editBoard: return "Edit Pinboard"
        case .pinPicker, .info, .actions, nil: return ""
        }
    }

    private var placeholder: String {
        switch model.editor {
        case .rename: return "Title (empty to clear)"
        case .tags: return "Comma or space separated, e.g. work, sql"
        default: return "Name"
        }
    }

    private func load() {
        switch model.editor {
        case .rename(let id): text = model.item(id)?.title ?? ""
        case .tags(let id): text = model.item(id)?.tags.joined(separator: ", ") ?? ""
        case .editText(let id): text = model.item(id)?.text ?? ""
        case .editBoard(let id):
            if let b = model.pinboards.first(where: { $0.id == id }) { text = b.name; color = b.colorHex }
        case .newBoard:
            color = Format.boardColors[model.pinboards.count % Format.boardColors.count]
        case .pinPicker, .info, .actions, nil: break
        }
        DispatchQueue.main.async { focused = true }
    }

    private func save() {
        let store = model.store
        switch model.editor {
        case .rename(let id): try? store.rename(id, title: text)
        case .tags(let id):
            try? store.setTags(id, text.split(whereSeparator: { $0 == "," || $0.isWhitespace }).map(String.init))
        case .editText(let id): try? store.editText(id, text: text)
        case .newBoard(let pinItem): model.createBoard(name: text, color: color, pin: pinItem)
        case .editBoard(let id):
            if !text.trimmingCharacters(in: .whitespaces).isEmpty { try? store.updatePinboard(id, name: text, colorHex: color) }
        case .pinPicker, .info, .actions, nil: break
        }
        model.editor = nil
    }
}

// MARK: Quick Look

struct QuickLookView: View {
    let item: ClipItem
    @EnvironmentObject var model: AppModel
    @State private var revealed = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Image(nsImage: Visuals.shared.icon(for: item.sourceBundleID)).resizable().frame(width: 28, height: 28)
                VStack(alignment: .leading, spacing: 1) {
                    Text(item.displayTitle ?? item.kind.label).font(.headline)
                    Text([item.sourceAppName, item.lastUsedAt.formatted(date: .abbreviated, time: .shortened), Format.footer(item)]
                        .compactMap { $0 }.joined(separator: " · "))
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Text("Space to close").font(.caption).foregroundStyle(.tertiary)
            }
            .padding(14)
            Divider()
            content.frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Color.solidSurface, in: RoundedRectangle(cornerRadius: 16))
    }

    @ViewBuilder private var content: some View {
        switch item.kind {
        case .image:
            ZStack(alignment: .bottomTrailing) {
                AsyncThumbnail(item: item, store: model.store, maxSide: 8192) { img in
                    ZoomableImage(image: img).padding(8)
                } placeholder: {
                    ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                Text("Pinch to zoom · double-click for 100%").font(.caption2).foregroundStyle(.secondary)
                    .padding(.horizontal, 8).padding(.vertical, 4).glassSurface(cornerRadius: 8).padding(12)
            }
        case .color:
            RoundedRectangle(cornerRadius: 12).fill(Color(hex: item.text ?? "")).padding(24)
        case .file:
            List(item.filePaths, id: \.self) { path in
                HStack {
                    Image(nsImage: NSWorkspace.shared.icon(forFile: path)).resizable().frame(width: 32, height: 32)
                    Text(path).textSelection(.enabled)
                }
            }
            .scrollContentBackground(.hidden)
        default:
            if item.maskedPreview != nil && !revealed {
                VStack(spacing: 12) {
                    Label(item.sensitiveLabel ?? "Sensitive", systemImage: "lock.shield.fill").foregroundStyle(.orange)
                    Text(item.maskedPreview ?? "").font(.system(size: 28, weight: .semibold, design: .monospaced))
                        .accessibilityIdentifier("ql.masked")
                    Button("Reveal") { revealed = true }.accessibilityIdentifier("ql.reveal")
                    Text("Paste always uses the full value.").font(.caption).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
            ScrollView {
                Group {
                    if item.kind == .richText {
                        AsyncRichText(item: item, store: model.store, limit: 50_000) { Text(item.text ?? "") }
                    } else {
                        if item.kind == .code {
                            Text(CodeStyle.highlighted(item.text ?? ""))
                        } else {
                            Text(item.text ?? "").font(.system(size: 13.5)).accessibilityIdentifier("ql.text")
                        }
                    }
                }
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(16)
                if let ocr = item.ocrText, !ocr.isEmpty {
                    Text(ocr).font(.callout).foregroundStyle(.secondary).padding(16)
                }
            }
            }
        }
    }
}

// MARK: Hold-⌘ shortcut bar

private struct ShortcutBar: View {
    private let hints: [(String, String)] = [
        ("⌘1–9", "Paste"), ("⌘J", "Smart action"), ("⌘K", "Actions"), ("⌘⇧⌫", "Delete"), ("⌘Z", "Undo"), ("⌘P", "Pin"), ("⌘⇧P", "Pin to…"),
        ("⌘O", "Open"), ("⌥⌘C", "Copy plain"), ("⌘I", "Info"), ("⌘R", "Rename"), ("⌘T", "Tags"),
        ("⌘E", "Edit"), ("⌘↑↓", "First/last"), ("⌥0–9", "Boards"),
    ]

    var body: some View {
        HStack(spacing: 14) {
            ForEach(hints, id: \.0) { key, label in
                HStack(spacing: 5) {
                    Text(key).font(.system(size: 11.5, weight: .semibold, design: .rounded))
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(.primary.opacity(0.12), in: RoundedRectangle(cornerRadius: 5))
                    Text(label).font(.system(size: 11.5)).foregroundStyle(.secondary)
                }
                .fixedSize()
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 9)
        .glassSurface(cornerRadius: 16)
        .shadow(color: .black.opacity(0.2), radius: 8, y: 2)
    }
}

// MARK: Pin picker (⌘⇧P)

private struct PinPickerView: View {
    let itemID: Int64
    @EnvironmentObject var model: AppModel

    var body: some View {
        let item = model.item(itemID)
        VStack(alignment: .leading, spacing: 8) {
            Text("Pin to…").font(.headline)
            ForEach(Array(model.pinboards.prefix(9).enumerated()), id: \.element.id) { i, board in
                Button {
                    if let item { model.togglePin(item, board: board.id) }
                    model.editor = nil
                } label: {
                    HStack(spacing: 8) {
                        Text("\(i + 1)").font(.system(size: 11, weight: .semibold, design: .rounded)).foregroundStyle(.secondary).frame(width: 14)
                        Circle().fill(Color(hex: board.colorHex)).frame(width: 9, height: 9)
                        Text(board.name)
                        Spacer(minLength: 20)
                        if item?.pinboardIDs.contains(board.id) == true { Image(systemName: "checkmark").foregroundStyle(.tint) }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            Divider()
            Button("New Pinboard… (⌘N)") { model.editor = .newBoard(pinItem: itemID) }.buttonStyle(.plain).foregroundStyle(.tint)
            Text("Press 1–9 to toggle · Esc to close").font(.caption).foregroundStyle(.secondary)
        }
        .frame(width: 260)
        .padding(16)
        .background(Color.solidSurface, in: RoundedRectangle(cornerRadius: 14))
        .shadow(radius: 20)
    }
}

// MARK: Info (⌘I)

private struct InfoView: View {
    let itemID: Int64
    @EnvironmentObject var model: AppModel

    var body: some View {
        if let item = model.item(itemID) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    Image(nsImage: Visuals.shared.icon(for: item.sourceBundleID)).resizable().frame(width: 28, height: 28)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(item.displayTitle ?? item.kind.label).font(.headline).lineLimit(1)
                        Text(item.sourceAppName ?? "Unknown app").font(.caption).foregroundStyle(.secondary)
                    }
                }
                Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 5) {
                    row("Type", item.kind.label + (item.isSensitive ? " · Sensitive (\(item.sensitiveReason ?? "?"))" : ""))
                    row("Size", Format.footer(item) + (item.kind == .image || item.kind == .file ? "" : " · " + Format.bytes(item.byteSize)))
                    row("Copied", item.createdAt.formatted(date: .abbreviated, time: .shortened))
                    row("Last used", item.lastUsedAt.formatted(date: .abbreviated, time: .shortened))
                    if let exp = item.expiresAt, !item.isPinned { row("Expires", exp.formatted(date: .omitted, time: .shortened)) }
                    if !item.pinboardIDs.isEmpty {
                        row("Pinned to", model.pinboards.filter { item.pinboardIDs.contains($0.id) }.map(\.name).joined(separator: ", "))
                    }
                    if !item.tags.isEmpty { row("Tags", item.tags.map { "#" + $0 }.joined(separator: " ")) }
                    if let bundle = item.sourceBundleID { row("Bundle", bundle) }
                    if let ocr = item.ocrText, !ocr.isEmpty { row("Text in image", String(ocr.prefix(120))) }
                }
                Text("⌘I or Esc to close").font(.caption).foregroundStyle(.tertiary)
            }
            .frame(width: 380, alignment: .leading)
            .padding(16)
            .background(Color.solidSurface, in: RoundedRectangle(cornerRadius: 14))
            .shadow(radius: 20)
        }
    }

    private func row(_ label: String, _ value: String) -> some View {
        GridRow {
            Text(label).foregroundStyle(.secondary)
            Text(value).lineLimit(2).textSelection(.enabled)
        }
        .font(.system(size: 12))
    }
}

// MARK: Actions (⌘K)

private struct ActionsView: View {
    let itemID: Int64
    @EnvironmentObject var model: AppModel
    @State private var filter = ""
    @State private var highlighted = 0
    @State private var options: [ActionOption] = []
    @FocusState private var focused: Bool

    /// One row in the ⌘K list: a smart suggestion (may open a URL) or a text transform.
    struct ActionOption: Identifiable {
        let id: String
        let group: String
        let title: String
        let keywords: String
        let result: String
        var url: URL? = nil
    }

    private var shown: [ActionOption] {
        let q = filter.lowercased().trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return options }
        return options.filter { ($0.title + " " + $0.keywords + " " + $0.group).lowercased().contains(q) }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Image(systemName: "wand.and.stars").foregroundStyle(.tint)
                    TextField("Filter actions", text: $filter)
                        .textFieldStyle(.plain).font(.system(size: 13)).focused($focused)
                        .onChange(of: filter) { _, _ in highlighted = 0 }
                        .onKeyPress(.upArrow) { move(-1); return .handled }
                        .onKeyPress(.downArrow) { move(1); return .handled }
                        .onKeyPress(.return, phases: .down) { press in
                            run(save: press.modifiers.contains(.command)); return .handled
                        }
                }
                .padding(8)
                .background(.quaternary.opacity(0.6), in: RoundedRectangle(cornerRadius: 7))
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 1) {
                            ForEach(Array(shown.enumerated()), id: \.element.id) { i, option in
                                if i == 0 || shown[i - 1].group != option.group {
                                    Text(option.group.uppercased())
                                        .font(.system(size: 9.5, weight: .bold)).foregroundStyle(.secondary)
                                        .padding(.top, i == 0 ? 2 : 8).padding(.leading, 6)
                                }
                                Label(option.title, systemImage: option.url != nil ? "arrow.up.forward.square" : "text.cursor")
                                    .labelStyle(.titleAndIcon)
                                    .font(.system(size: 12.5))
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.horizontal, 8).padding(.vertical, 4)
                                    .background(i == highlighted ? Color.accentColor.opacity(0.85) : .clear, in: RoundedRectangle(cornerRadius: 5))
                                    .foregroundStyle(i == highlighted ? .white : .primary)
                                    .contentShape(Rectangle())
                                    .onTapGesture { highlighted = i }
                                    .onTapGesture(count: 2) { highlighted = i; run(save: false) }
                                    .id(option.id)
                            }
                        }
                    }
                    .onChange(of: highlighted) { _, i in if i < shown.count { proxy.scrollTo(shown[i].id) } }
                }
            }
            .frame(width: 250)
            Divider().padding(.horizontal, 12)
            VStack(alignment: .leading, spacing: 8) {
                Text("Result").font(.system(size: 10, weight: .bold)).foregroundStyle(.secondary)
                ScrollView {
                    Text(highlighted < shown.count ? String(shown[highlighted].result.prefix(4000)) : "No actions fit this item")
                        .font(.system(size: 12, design: .monospaced))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                }
                Spacer(minLength: 0)
                Text(highlighted < shown.count && shown[highlighted].url != nil ? "↩ open · Esc" : "↩ paste result · ⌘↩ save as new card · Esc")
                    .font(.caption).foregroundStyle(.tertiary)
            }
            .frame(width: 330)
        }
        .frame(height: 250)
        .padding(14)
        .background(Color.solidSurface, in: RoundedRectangle(cornerRadius: 14))
        .shadow(radius: 20)
        .onAppear {
            let text = model.item(itemID)?.text ?? ""
            let smart = model.item(itemID).map(model.chips(for:)) ?? []
            options = smart.enumerated().map { i, c in
                switch c.action {
                case .open(let url): return ActionOption(id: "smart.\(i)", group: "Suggested", title: c.title, keywords: c.label, result: url.absoluteString, url: url)
                case .text(let t): return ActionOption(id: "smart.\(i)", group: "Suggested", title: c.title, keywords: c.label, result: t)
                }
            } + Transform.available(for: text).map { t, out in
                ActionOption(id: t.id, group: t.group.rawValue, title: t.title, keywords: t.keywords, result: out)
            }
            DispatchQueue.main.async { focused = true }
        }
    }

    private func move(_ d: Int) {
        guard !shown.isEmpty else { return }
        highlighted = max(0, min(shown.count - 1, highlighted + d))
    }

    private func run(save: Bool) {
        guard highlighted < shown.count else { NSSound.beep(); return }
        let option = shown[highlighted]
        model.editor = nil
        if let url = option.url { model.onOpenURL?(url); return }
        if save { model.saveAsNewItem(option.result) } else { model.onPasteText?(option.result) }
    }
}
