import AppKit
import MyPasteCore
import SwiftUI

/// Pin picker shared by ⌘⇧P / double-⌃ in the strip and the global double-⌃ panel.
/// Boards as coloured chips numbered 1–9; typing filters, ↩ on an unknown name creates that board.
struct PinPickerView: View {
    let itemID: Int64
    @EnvironmentObject var model: AppModel
    var onDone: () -> Void
    @State private var filter = ""
    @State private var highlighted = 0
    @FocusState private var focused: Bool

    private var item: ClipItem? { model.item(itemID) }

    private var boards: [Pinboard] {
        let q = filter.trimmingCharacters(in: .whitespaces).lowercased()
        return q.isEmpty ? model.pinboards : model.pinboards.filter { $0.name.lowercased().contains(q) }
    }

    /// Typed name that matches no board exactly: offered as "new board".
    private var newName: String? {
        let t = filter.trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty, !model.pinboards.contains(where: { $0.name.caseInsensitiveCompare(t) == .orderedSame }) else { return nil }
        return t
    }

    private var rowCount: Int { boards.count + (newName == nil ? 0 : 1) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "pin.fill").foregroundStyle(.pink)
                Text("Pin “\(String((item?.safeSummary ?? "item").prefix(34)))”").font(.headline).lineLimit(1)
            }
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Type to filter or create a board…", text: $filter)
                    .textFieldStyle(.plain).focused($focused)
                    .accessibilityIdentifier("pinpicker.filter")
                    .onChange(of: filter) { _, _ in highlighted = 0 }
                    .onKeyPress(.upArrow) { move(-1); return .handled }
                    .onKeyPress(.downArrow) { move(1); return .handled }
                    .onKeyPress(.escape) { onDone(); return .handled }
                    .onKeyPress(.return) { choose(highlighted); return .handled }
                    .onKeyPress(characters: .decimalDigits) { press in
                        // Digits pick a board while the filter is empty; otherwise they're part of a name.
                        guard filter.isEmpty, let n = Int(press.characters), (1...9).contains(n), n <= boards.count else { return .ignored }
                        choose(n - 1)
                        return .handled
                    }
            }
            .padding(8)
            .background(.quaternary.opacity(0.6), in: RoundedRectangle(cornerRadius: 8))

            VStack(spacing: 2) {
                ForEach(Array(boards.prefix(9).enumerated()), id: \.element.id) { i, board in
                    row(i, number: "\(i + 1)") {
                        Circle().fill(Color(hex: board.colorHex)).frame(width: 10, height: 10)
                        Text(board.name).fontWeight(.medium)
                        Spacer(minLength: 12)
                        if item?.pinboardIDs.contains(board.id) == true {
                            Image(systemName: "checkmark").font(.system(size: 11, weight: .bold)).foregroundStyle(.tint)
                        }
                    }
                }
                if let name = newName {
                    row(boards.count, number: "↩") {
                        Image(systemName: "plus.circle.fill").foregroundStyle(.green)
                        Text("New board “\(name)”").fontWeight(.medium)
                        Spacer()
                    }
                }
                if model.pinboards.isEmpty && newName == nil {
                    Text("No boards yet. Type a name and press ↩.").font(.callout).foregroundStyle(.secondary).padding(.vertical, 6)
                }
            }
            Text("1–9 pin · ↑↓ ↩ choose · Esc cancel · picking a ✓ board unpins")
                .font(.caption2).foregroundStyle(.tertiary)
        }
        .frame(width: 320)
        .padding(16)
        .background(Color.solidSurface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(.primary.opacity(0.08)))
        .shadow(color: .black.opacity(0.3), radius: 24, y: 8)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("pinpicker")
        .onAppear { DispatchQueue.main.async { focused = true } }
    }

    private func row<C: View>(_ i: Int, number: String, @ViewBuilder content: () -> C) -> some View {
        HStack(spacing: 10) {
            Text(number).font(.system(size: 11, weight: .bold, design: .rounded)).foregroundStyle(.secondary)
                .frame(width: 20, height: 20).background(Circle().fill(.primary.opacity(0.08)))
            content()
        }
        .padding(.horizontal, 8).padding(.vertical, 6)
        .background(i == highlighted ? Color.accentColor.opacity(0.2) : .clear, in: RoundedRectangle(cornerRadius: 8))
        .contentShape(Rectangle())
        .onTapGesture { choose(i) }
        .accessibilityIdentifier("pinpicker.row.\(i)")
    }

    private func move(_ d: Int) {
        guard rowCount > 0 else { return }
        highlighted = max(0, min(rowCount - 1, highlighted + d))
    }

    private func choose(_ i: Int) {
        guard let item else { onDone(); return }
        if i < boards.count {
            model.togglePin(item, board: boards[i].id)
            let pinned = !(item.pinboardIDs.contains(boards[i].id))
            model.showToast(pinned ? "Pinned to \(boards[i].name)" : "Unpinned from \(boards[i].name)")
        } else if let name = newName {
            model.createBoard(name: name, color: Format.boardColors[model.pinboards.count % Format.boardColors.count], pin: item.id)
            model.showToast("Pinned to new board \(name)")
        }
        onDone()
    }
}

/// Floating picker for double-⌃ outside the strip: pins the most recent capture.
final class GlobalPinPicker: NSObject, NSWindowDelegate {
    private let model: AppModel
    private var panel: StripPanel?

    init(model: AppModel) { self.model = model }

    var isVisible: Bool { panel?.isVisible == true }

    func show() {
        guard let item = model.items.first else { NSSound.beep(); return }
        let p = panel ?? makePanel()
        panel = p
        // Padding leaves room for the card's own shadow inside the borderless panel.
        p.contentView = NSHostingView(rootView: PinPickerView(itemID: item.id, onDone: { [weak self] in self?.hide() })
            .padding(28).environmentObject(model))
        let size = p.contentView?.fittingSize ?? NSSize(width: 360, height: 300)
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main ?? NSScreen.screens[0]
        let f = screen.visibleFrame
        p.setFrame(NSRect(x: f.midX - size.width / 2, y: f.maxY - size.height - 40, width: size.width, height: size.height), display: true)
        p.alphaValue = 0
        p.makeKeyAndOrderFront(nil)
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.15
            p.animator().alphaValue = 1
        }
    }

    func hide() {
        panel?.orderOut(nil)
    }

    func windowDidResignKey(_ notification: Notification) { hide() }

    private func makePanel() -> StripPanel {
        let p = StripPanel(contentRect: .zero, styleMask: [.nonactivatingPanel, .borderless, .fullSizeContentView], backing: .buffered, defer: false)
        p.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.popUpMenuWindow)))
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = false
        p.isReleasedWhenClosed = false
        p.delegate = self
        p.setAccessibilityIdentifier("pinpicker.window")
        return p
    }
}
