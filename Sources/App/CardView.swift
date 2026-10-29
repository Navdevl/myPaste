import SwiftUI
import MyPasteCore

struct CardView: View {
    let item: ClipItem
    let index: Int
    @EnvironmentObject var model: AppModel

    static let size = CGSize(width: 232, height: 244)

    private var selected: Bool { model.selectedID == item.id }
    /// Masked identifiers (PAN, Aadhaar, cards, accounts…) never show raw in a card, so they skip the blur.
    private var concealed: Bool { item.isSensitive && item.maskedPreview == nil && !selected && model.hoveredID != item.id }

    @State private var appeared = true
    @State private var sweep: CGFloat = -1.5
    @Environment(\.selectionNamespace) private var selectionNS

    var body: some View {
        card
            .modifier(Parallax(offset: parallaxOffset))
            .overlay(alignment: .top) { pinDrop }
            .overlay(alignment: .topLeading) { if model.editMode { deleteButton } }
            .overlay(alignment: .topTrailing) { if model.editMode, index < 9 { shortcutBadge } }
            .overlay(alignment: .topTrailing) { if model.plainMode, !model.editMode, item.hasFormatting { plainBadge } }
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
                Group {
                    if let masked = item.maskedPreview { maskedView(masked) } else { preview }
                }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .blur(radius: concealed ? 9 : 0)
                if concealed {
                    Label("Sensitive", systemImage: "eye.slash.fill")
                        .font(.callout.weight(.semibold)).foregroundStyle(.secondary)
                }
            }
            .background(alignment: .bottomTrailing) { watermark }
            .overlay(alignment: .bottomLeading) { smartChip }
            .clipped()
            footer
        }
        .frame(width: Self.size.width, height: Self.size.height)
        .background(Color(nsColor: .textBackgroundColor).opacity(0.92))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(selected && !glide ? Color.accentColor : Color.primary.opacity(0.08), lineWidth: selected && !glide ? 3 : 1)
        )
        .overlay { sweepLayer }
        .overlay {
            // One ring shared across cards via matched geometry: it travels instead of jumping.
            if selected, glide, let selectionNS {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(Color.accentColor, lineWidth: 3)
                    .shadow(color: Color.accentColor.opacity(0.45), radius: 8)
                    .matchedGeometryEffect(id: "selection-ring", in: selectionNS)
                    .allowsHitTesting(false)
            }
        }
        .shadow(color: .black.opacity(selected ? 0.28 : 0.12), radius: selected ? 10 : 4, y: 2)
        .scaleEffect(selected ? 1.0 : 0.97)
        .animation(.easeOut(duration: 0.12), value: selected)
        .contentShape(Rectangle())
        .onHover { model.hoveredID = $0 ? item.id : (model.hoveredID == item.id ? nil : model.hoveredID) }
        .onTapGesture(count: 2) { model.paste(item, plain: NSEvent.modifierFlags.contains(.shift)) }
        .onTapGesture { model.select(item.id) }
        .draggable(String(item.id))
        .contextMenu { CardMenu(item: item) }
        .onChange(of: selected) { _, isSelected in
            guard isSelected, model.prefs.sweepSelection else { return }
            sweep = -1.5
            withAnimation(.easeOut(duration: 0.5).delay(0.06)) { sweep = 1.5 }
        }
    }

    private var glide: Bool { model.prefs.glideSelection }

    /// Signed distance from the selected card, for the neighbour lean (nil = no parallax).
    private var parallaxOffset: Int? {
        guard model.prefs.parallax, let sel = model.selectedIndex else { return nil }
        let d = index - sel
        return abs(d) <= 2 && d != 0 ? d : nil
    }

    /// A soft diagonal band of light that crosses the card once when it becomes selected.
    private var sweepLayer: some View {
        GeometryReader { geo in
            LinearGradient(colors: [.white.opacity(0), .white.opacity(0.22), .white.opacity(0)], startPoint: .leading, endPoint: .trailing)
                .frame(width: geo.size.width * 0.55)
                .rotationEffect(.degrees(18))
                .offset(x: sweep * geo.size.width)
                .blendMode(.plusLighter)
        }
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .opacity(sweep > -1.4 && sweep < 1.4 ? 1 : 0)
        .allowsHitTesting(false)
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

    private var plainBadge: some View {
        Label("Plain text", systemImage: "textformat.size.smaller")
            .font(.system(size: 10.5, weight: .bold))
            .foregroundStyle(.white)
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(Capsule().fill(Color.orange))
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
                    Text(item.displayTitle ?? (item.maskedPreview != nil ? item.sensitiveLabel : nil) ?? item.kind.label).font(.system(size: 13, weight: .semibold)).lineLimit(1)
                    if item.isPinned { Image(systemName: "pin.fill").font(.system(size: 10)) }
                    if item.isSnippet {
                        Text("Snippet").font(.system(size: 9, weight: .bold)).padding(.horizontal, 4).padding(.vertical, 1)
                            .background(.white.opacity(0.25), in: Capsule())
                    }
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
            AsyncThumbnail(item: item, store: model.store) { img in
                Image(nsImage: img).resizable().aspectRatio(contentMode: .fit)
                    .frame(maxWidth: .infinity, maxHeight: .infinity).padding(8)
            } placeholder: {
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
                if item.hasLinkImage {
                    AsyncThumbnail(item: item, store: model.store, ext: "link.png") { img in
                        Image(nsImage: img).resizable().aspectRatio(contentMode: .fill)
                    } placeholder: {
                        Color.primary.opacity(0.06)
                    }
                    .frame(maxWidth: .infinity).frame(height: 96).clipped()
                }
                VStack(alignment: .leading, spacing: 4) {
                    if !item.hasLinkImage {
                        HStack(spacing: 8) {
                            AsyncThumbnail(item: item, store: model.store, ext: item.hasLinkIcon ? "icon.png" : "none", maxSide: 64) { icon in
                                Image(nsImage: icon).resizable().frame(width: 28, height: 28).clipShape(RoundedRectangle(cornerRadius: 6))
                            } placeholder: {
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
            AsyncRichText(item: item, store: model.store) { Text(String((item.text ?? "").prefix(900))) }
                .font(.system(size: 12)).padding(12)
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

    @ViewBuilder private var smartChip: some View {
        let chips = model.chips(for: item)
        if let chip = chips.first {
            Button { model.runSmart(item) } label: {
                HStack(spacing: 4) {
                    Image(systemName: chip.symbol).font(.system(size: 9.5, weight: .semibold))
                    Text(chip.label).font(.system(size: 10.5, weight: .semibold)).lineLimit(1)
                    if chips.count > 1 { Text("+\(chips.count - 1)").font(.system(size: 9.5)).opacity(0.75) }
                }
                .padding(.horizontal, 7).padding(.vertical, 3)
                .foregroundStyle(.white)
                .background(Capsule().fill(Color.accentColor.opacity(0.9)))
            }
            .buttonStyle(.plain)
            .help(chip.title + " (⌘J) · ⌘K for all actions")
            .accessibilityIdentifier("card.chip")
            .padding(8)
        }
    }

    /// Large, faint source-app icon behind the preview: identity at a glance without competing with content.
    private var watermark: some View {
        Image(nsImage: Visuals.shared.icon(for: item.sourceBundleID))
            .resizable()
            .frame(width: 118, height: 118)
            .opacity(0.11)
            .saturation(0.6)
            .rotationEffect(.degrees(-12))
            .offset(x: 26, y: 30)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }

    private func maskedView(_ masked: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(item.sensitiveLabel ?? "Sensitive", systemImage: "lock.shield.fill")
                .font(.system(size: 11, weight: .semibold)).foregroundStyle(.orange)
            Text(masked).font(.system(size: 17, weight: .semibold, design: .monospaced)).lineLimit(2)
            Text("Masked · Space to reveal").font(.system(size: 10.5)).foregroundStyle(.secondary)
        }
        .padding(12)
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
            if selected, item.tags.isEmpty {
                Text(item.hasFormatting ? "↩ paste · ⇧↩ plain" : "↩ paste")
                    .font(.system(size: 10, weight: .medium)).foregroundStyle(.tertiary).lineLimit(1)
            }
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
        if item.text != nil, item.kind != .image, item.kind != .file { Button("Actions… (⌘K)") { model.editor = .actions(item.id) } }
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

/// Neighbours lean slightly toward the selection (1 card away: 6°, 2 away: 3°).
private struct Parallax: ViewModifier {
    let offset: Int?

    func body(content: Content) -> some View {
        let d = offset ?? 0
        let angle = d == 0 ? 0 : Double(d > 0 ? 1 : -1) * (abs(d) == 1 ? 6 : 3)
        content
            .rotation3DEffect(.degrees(angle), axis: (x: 0, y: 1, z: 0), anchor: d > 0 ? .leading : .trailing, perspective: 0.5)
            .scaleEffect(d == 0 ? 1 : 0.985)
    }
}

private struct SelectionNamespaceKey: EnvironmentKey {
    static let defaultValue: Namespace.ID? = nil
}

extension EnvironmentValues {
    var selectionNamespace: Namespace.ID? {
        get { self[SelectionNamespaceKey.self] }
        set { self[SelectionNamespaceKey.self] = newValue }
    }
}
