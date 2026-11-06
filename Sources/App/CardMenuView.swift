import MyPasteCore
import SwiftUI

/// ⌘M / ⋯ panel: everything you can do with a card, styled like the pin picker. Two columns so the whole
/// list fits in the strip; typing filters, ↑↓ (←→ jumps columns) ↩ runs, Esc closes.
struct CardMenuView: View {
    let itemID: Int64
    @EnvironmentObject var model: AppModel
    @State private var filter = ""
    @State private var highlighted = 0
    @FocusState private var focused: Bool

    private var item: ClipItem? { model.item(itemID) }

    /// Separators and submenus flattened; a submenu row runs its own action (Pin to… opens the pin picker).
    private var rows: [CardMenuItem] {
        guard let item else { return [] }
        let all = model.cardMenu(for: item).compactMap { entry -> CardMenuItem? in
            switch entry {
            case .action(let a), .submenu(let a, _): return a
            case .separator: return nil
            }
        }
        let q = filter.trimmingCharacters(in: .whitespaces).lowercased()
        return q.isEmpty ? all : all.filter { $0.title.lowercased().contains(q) }
    }

    private var half: Int { (rows.count + 1) / 2 }

    var body: some View {
        let rows = rows
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "ellipsis.circle.fill").foregroundStyle(.tint)
                Text("“\(String((item?.safeSummary ?? "item").prefix(48)))”").font(.headline).lineLimit(1)
            }
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Type to filter…", text: $filter)
                    .textFieldStyle(.plain).focused($focused)
                    .accessibilityIdentifier("cardmenu.filter")
                    .onChange(of: filter) { _, _ in highlighted = 0 }
                    .onKeyPress(.upArrow) { move(-1); return .handled }
                    .onKeyPress(.downArrow) { move(1); return .handled }
                    .onKeyPress(.leftArrow) { filter.isEmpty ? { move(-half); return .handled }() : .ignored }
                    .onKeyPress(.rightArrow) { filter.isEmpty ? { move(half); return .handled }() : .ignored }
                    .onKeyPress(.escape) { model.editor = nil; return .handled }
                    .onKeyPress(.return) { run(highlighted); return .handled }
            }
            .padding(8)
            .background(.quaternary.opacity(0.6), in: RoundedRectangle(cornerRadius: 8))

            HStack(alignment: .top, spacing: 8) {
                column(rows, 0..<min(half, rows.count))
                column(rows, min(half, rows.count)..<rows.count)
            }
            if rows.isEmpty {
                Text("Nothing matches “\(filter)”.").font(.callout).foregroundStyle(.secondary).padding(.vertical, 6)
            }
            Text("↑↓ ←→ ↩ choose · Esc close · the keys on the right work without opening this")
                .font(.caption2).foregroundStyle(.tertiary)
        }
        .frame(width: 560)
        .padding(16)
        .background(Color.solidSurface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(.primary.opacity(0.08)))
        .shadow(color: .black.opacity(0.3), radius: 24, y: 8)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("cardmenu")
        .onAppear { DispatchQueue.main.async { focused = true } }
    }

    private func column(_ rows: [CardMenuItem], _ range: Range<Int>) -> some View {
        VStack(spacing: 2) {
            ForEach(range, id: \.self) { i in row(rows[i], i) }
        }
        .frame(maxWidth: .infinity, alignment: .top)
    }

    private func row(_ a: CardMenuItem, _ i: Int) -> some View {
        HStack(spacing: 9) {
            Image(systemName: a.symbol).font(.system(size: 12, weight: .semibold)).foregroundStyle(a.tint)
                .frame(width: 22, height: 22).background(a.tint.opacity(0.14), in: RoundedRectangle(cornerRadius: 6))
            Text(a.title).fontWeight(.medium).foregroundStyle(a.destructive ? Color.red : .primary).lineLimit(1)
            Spacer(minLength: 8)
            if let key = a.key {
                Text(key).font(.system(size: 11, weight: .semibold, design: .rounded)).foregroundStyle(a.tint)
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(a.tint.opacity(0.14), in: RoundedRectangle(cornerRadius: 5))
            }
        }
        .padding(.horizontal, 8).padding(.vertical, 4)
        .background(i == highlighted ? Color.accentColor.opacity(0.2) : .clear, in: RoundedRectangle(cornerRadius: 8))
        .contentShape(Rectangle())
        .onTapGesture { run(i) }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(a.key.map { "\(a.title) \($0)" } ?? a.title)
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier("cardmenu.row.\(i)")
    }

    private func move(_ d: Int) {
        let n = rows.count
        guard n > 0 else { return }
        highlighted = max(0, min(n - 1, highlighted + d))
    }

    /// Close first, then run: actions that open another editor (Tags…, Pin to…) replace this one.
    private func run(_ i: Int) {
        let rows = rows
        guard rows.indices.contains(i) else { return }
        model.editor = nil
        rows[i].run()
    }
}
