import SwiftUI
import MyPasteCore

struct CardView: View {
    let item: ClipItem
    let index: Int
    @EnvironmentObject var model: AppModel

    static let size = CGSize(width: 232, height: 244)

    private var selected: Bool { model.selectedID == item.id }
    private var concealed: Bool { item.isSensitive && !selected && model.hoveredID != item.id }

    @State private var appeared = true

    var body: some View {
        card
            .overlay(alignment: .top) { pinDrop }
            .overlay(alignment: .topLeading) { if model.editMode { deleteButton } }
            .overlay(alignment: .topTrailing) { if model.editMode, index < 9 { shortcutBadge } }
            .modifier(Jiggle(active: model.editMode, seed: index))
            .scaleEffect(model.pulseID == item.id ? 1.06 : 1)
            .opacity(appeared ? 1 : 0)
            .offset(y: appeared ? 0 : 36)
            .onAppear { if !entranceShown, Date().timeIntervalSince(model.shownAt) < 0.4 { runEntrance() } }
            .onChange(of: model.entranceToken) { _, _ in runEntrance() }
    }

    /// Only the first screenful staggers in on open; cards scrolled into view later just appear.
    @State private var entranceShown = false

    private func runEntrance() {
        entranceShown = true
        guard index < 10 else { appeared = true; return }
        appeared = false
        withAnimation(.spring(response: 0.42, dampingFraction: 0.78).delay(Double(index) * 0.035)) { appeared = true }
    }

    private var card: some View {
        VStack(spacing: 0) {
            header
            ZStack {
                preview
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .blur(radius: concealed ? 9 : 0)
                if concealed {
                    Label("Sensitive", systemImage: "eye.slash.fill")
                        .font(.callout.weight(.semibold)).foregroundStyle(.secondary)
                }
            }
            .clipped()
            footer
        }
        .frame(width: Self.size.width, height: Self.size.height)
        .background(Color(nsColor: .textBackgroundColor).opacity(0.92))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(selected ? Color.accentColor : Color.primary.opacity(0.08), lineWidth: selected ? 3 : 1)
        )
        .shadow(color: .black.opacity(selected ? 0.28 : 0.12), radius: selected ? 10 : 4, y: 2)
        .scaleEffect(selected ? 1.0 : 0.97)
        .animation(.easeOut(duration: 0.12), value: selected)
        .contentShape(Rectangle())
        .onHover { model.hoveredID = $0 ? item.id : (model.hoveredID == item.id ? nil : model.hoveredID) }
        .onTapGesture(count: 2) { model.paste(item) }
        .onTapGesture { model.selectedID = item.id }
        .draggable(String(item.id))
        .contextMenu { CardMenu(item: item) }
    }

    private var deleteButton: some View {
        Button { model.delete(item) } label: {
            Image(systemName: "xmark")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 22, height: 22)
                .background(Circle().fill(Color.black.opacity(0.75)))
                .overlay(Circle().strokeBorder(.white.opacity(0.85), lineWidth: 1.5))
        }
        .buttonStyle(.plain)
        .offset(x: -7, y: -7)
        .transition(.scale.combined(with: .opacity))
        .help("Delete (⌘⇧⌫)")
    }

    /// Top corner, so the hold-⌘ shortcut bar along the bottom never hides it.
    private var shortcutBadge: some View {
        Text("⌘\(index + 1)")
            .font(.system(size: 11, weight: .bold, design: .rounded))
            .foregroundStyle(.white)
            .padding(.horizontal, 7).padding(.vertical, 3)
            .background(Capsule().fill(Color.accentColor))
            .overlay(Capsule().strokeBorder(.white.opacity(0.85), lineWidth: 1.5))
            .offset(x: 7, y: -7)
            .transition(.scale.combined(with: .opacity))
    }

    @ViewBuilder private var pinDrop: some View {
        if model.pinDropID == item.id {
            Image(systemName: "pin.fill")
                .font(.system(size: 26, weight: .semibold))
                .foregroundStyle(.white, Color.accentColor)
                .shadow(radius: 4)
                .offset(y: 70)
                .transition(.asymmetric(insertion: .offset(y: -60).combined(with: .opacity), removal: .opacity))
        }
    }

    // MARK: Header

    private var header: some View {
        let accent = item.kind == .color ? Color(hex: item.text ?? "") : Visuals.shared.accent(for: item.sourceBundleID)
        return HStack(alignment: .center, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 5) {
                    Text(item.displayTitle ?? item.kind.label).font(.system(size: 13, weight: .semibold)).lineLimit(1)
                    if item.isPinned { Image(systemName: "pin.fill").font(.system(size: 10)) }
                    if item.isSensitive { Image(systemName: "lock.fill").font(.system(size: 10)) }
                }
                Text(Format.ago(item.lastUsedAt, now: model.now) + (item.displayTitle != nil ? " · \(item.kind.label)" : ""))
                    .font(.system(size: 11)).opacity(0.8).lineLimit(1)
            }
            Spacer(minLength: 4)
            Image(nsImage: Visuals.shared.icon(for: item.sourceBundleID))
                .resizable().frame(width: 30, height: 30)
                .help(item.sourceAppName ?? "")
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 12)
        .frame(height: 50)
        .background(LinearGradient(colors: [accent, accent.opacity(0.82)], startPoint: .topLeading, endPoint: .bottomTrailing))
    }

    // MARK: Preview

    @ViewBuilder private var preview: some View {
        switch item.kind {
        case .image:
            if let img = Visuals.shared.thumbnail(for: item, store: model.store) {
                Image(nsImage: img).resizable().aspectRatio(contentMode: .fit)
                    .frame(maxWidth: .infinity, maxHeight: .infinity).padding(8)
            } else {
                placeholder("photo")
            }
        case .file:
            VStack(alignment: .leading, spacing: 6) {
                ForEach(item.filePaths.prefix(3), id: \.self) { path in
                    HStack(spacing: 8) {
                        Image(nsImage: NSWorkspace.shared.icon(forFile: path)).resizable().frame(width: 36, height: 36)
                        VStack(alignment: .leading, spacing: 1) {
                            Text((path as NSString).lastPathComponent).font(.system(size: 12, weight: .medium)).lineLimit(1)
                            Text((path as NSString).deletingLastPathComponent.replacingOccurrences(of: NSHomeDirectory(), with: "~"))
                                .font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                        }
                    }
                }
                if item.filePaths.count > 3 {
                    Text("+\(item.filePaths.count - 3) more").font(.caption).foregroundStyle(.secondary)
                }
            }
            .padding(12)
        case .color:
            VStack(spacing: 8) {
                RoundedRectangle(cornerRadius: 10).fill(Color(hex: item.text ?? ""))
                    .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(.primary.opacity(0.1)))
                Text(item.text ?? "").font(.system(size: 14, weight: .medium, design: .monospaced))
            }
            .padding(12)
        case .link:
            VStack(alignment: .leading, spacing: 6) {
                if item.hasLinkImage, let img = Visuals.shared.thumbnail(for: item, store: model.store, ext: "link.png") {
                    Image(nsImage: img).resizable().aspectRatio(contentMode: .fill)
                        .frame(maxWidth: .infinity).frame(height: 96).clipped()
                }
                VStack(alignment: .leading, spacing: 4) {
                    if !item.hasLinkImage {
                        HStack(spacing: 8) {
                            if item.hasLinkIcon, let icon = Visuals.shared.thumbnail(for: item, store: model.store, ext: "icon.png", maxSide: 64) {
                                Image(nsImage: icon).resizable().frame(width: 28, height: 28).clipShape(RoundedRectangle(cornerRadius: 6))
                            } else {
                                Image(systemName: "globe").font(.system(size: 22)).foregroundStyle(.secondary).frame(width: 28, height: 28)
                            }
                            Text(URL(string: item.text ?? "")?.host ?? "").font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary).lineLimit(1)
                        }
                        .padding(.bottom, 2)
                    }
                    if let title = item.linkTitle { Text(title).font(.system(size: 13, weight: .semibold)).lineLimit(item.hasLinkImage ? 2 : 3) }
                    Text(item.text ?? "").font(.system(size: 11)).foregroundStyle(.blue).lineLimit(item.hasLinkImage ? 2 : 6)
                }
                .padding(.horizontal, 12).padding(.top, item.hasLinkImage ? 0 : 10)
            }
        case .code:
            Text(String((item.text ?? "").prefix(900)))
                .font(.system(size: 11, design: .monospaced)).padding(12)
        case .richText:
            if let attr = Visuals.shared.richText(for: item, store: model.store) {
                Text(attr).font(.system(size: 12)).padding(12)
            } else {
                plainText
            }
        case .email, .phone:
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: item.kind.symbol).foregroundStyle(.secondary)
                Text(item.text ?? "").font(.system(size: 14, weight: .medium)).textSelection(.disabled)
            }
            .padding(12)
        case .text:
            plainText
        }
    }

    private var plainText: some View {
        Text(String((item.text ?? "").prefix(900))).font(.system(size: 12.5)).padding(12)
    }

    private func placeholder(_ symbol: String) -> some View {
        Image(systemName: symbol).font(.largeTitle).foregroundStyle(.tertiary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: Footer

    private var footer: some View {
        HStack(spacing: 4) {
            ForEach(item.tags.prefix(3), id: \.self) { tag in
                Text("#" + tag).font(.system(size: 10, weight: .medium)).lineLimit(1)
                    .padding(.horizontal, 5).padding(.vertical, 2)
                    .background(Color.accentColor.opacity(0.15), in: Capsule())
            }
            Spacer(minLength: 2)
            Text(Format.footer(item)).font(.system(size: 10.5)).foregroundStyle(.secondary).lineLimit(1)
        }
        .padding(.horizontal, 10)
        .frame(height: 26)
    }
}

struct CardMenu: View {
    let item: ClipItem
    @EnvironmentObject var model: AppModel

    var body: some View {
        Button("Paste") { model.paste(item) }
        Button("Paste as Plain Text") { model.paste(item, plain: true) }
        Button("Copy") { model.onCopy?(item, false) }
        Button("Copy as Plain Text") { model.onCopy?(item, true) }
        if item.kind == .link || item.kind == .file { Button(item.kind == .link ? "Open Link" : "Show in Finder") { model.onOpen?(item) } }
        Button("Add to Paste Stack") { model.onAddToStack?(item) }
        Divider()
        Menu("Pin to") {
            ForEach(model.pinboards) { board in
                Button((item.pinboardIDs.contains(board.id) ? "✓ " : "") + board.name) { model.togglePin(item, board: board.id) }
            }
            if !model.pinboards.isEmpty { Divider() }
            Button("New Pinboard…") { model.editor = .newBoard(pinItem: item.id) }
        }
        if item.isPinned { Button("Unpin from All") { model.unpinAll(item) } }
        Button("Tags…") { model.editor = .tags(item.id) }
        Button("Rename…") { model.editor = .rename(item.id) }
        if item.kind != .image && item.kind != .file { Button("Edit Text…") { model.editor = .editText(item.id) } }
        Button("Quick Look") { model.selectedID = item.id; model.quickLookID = item.id }
        Button("Info") { model.editor = .info(item.id) }
        Divider()
        Button("Delete", role: .destructive) { model.delete(item) }
    }
}

/// iOS-style edit-mode wobble; the seed offsets phase so neighbours don't move in lockstep.
private struct Jiggle: ViewModifier {
    let active: Bool
    let seed: Int

    func body(content: Content) -> some View {
        if active {
            TimelineView(.animation) { context in
                let t = context.date.timeIntervalSinceReferenceDate
                let phase = Double(seed % 5) * 1.3
                content
                    .rotationEffect(.degrees(sin(t * 2 * .pi * 3.2 + phase) * 1.4))
                    .offset(y: sin(t * 2 * .pi * 2.6 + phase) * 0.8)
            }
        } else {
            content
        }
    }
}
