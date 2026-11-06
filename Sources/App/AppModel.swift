import AppKit
import MyPasteCore
import Combine
import CryptoKit
import SwiftUI

enum Tab: Hashable {
    case history
    case board(Int64)
}

enum Editor: Equatable {
    case rename(Int64)
    case tags(Int64)
    case editText(Int64)
    case newBoard(pinItem: Int64?)
    case editBoard(Int64)
    case pinPicker(Int64)
    case info(Int64)
    case actions(Int64)
    case cardMenu(Int64)
}

/// UI state for the strip: all items in memory (≤ a few thousand), filtered on the main thread.
final class AppModel: ObservableObject {
    let store: ClipStore
    let prefs: Preferences

    @Published private(set) var items: [ClipItem] = []
    @Published private(set) var pinboards: [Pinboard] = []
    @Published private(set) var visible: [ClipItem] = []
    @Published var tab: Tab = .history { didSet { if tab != oldValue { recompute(resetSelection: true) } } }
    @Published var search = "" { didSet { if search != oldValue { recompute(resetSelection: true) } } }
    @Published var kindFilter: KindFilter = .all { didSet { if kindFilter != oldValue { recompute(resetSelection: true) } } }
    @Published var appFilter: String? { didSet { if appFilter != oldValue { recompute(resetSelection: true) } } }
    @Published var selectedID: Int64?
    @Published var editor: Editor?
    @Published var quickLookID: Int64?
    @Published var hoveredID: Int64?
    @Published var now = Date()
    /// Bumped each time the panel opens so the search field re-takes focus.
    @Published var focusToken = 0
    /// The shortcut bar, toggled by the keyboard button in the top bar or ⌘/.
    @Published var showKeys = false
    /// Hold-⇧ mode: every paste path (↩, ⌘1–9, double-click) drops formatting.
    @Published var plainMode = false
    /// Bumped on every open; cards use it to run the staggered entrance.
    @Published var entranceToken = 0
    private(set) var shownAt = Date.distantPast
    /// Card that just got pasted (pulse) or pinned (pin drop).
    @Published var pulseID: Int64?
    @Published var pinDropID: Int64?
    @Published private(set) var toast: String?

    /// (item, plainText) → paste into the frontmost app.
    var onPaste: ((ClipItem, Bool) -> Void)?
    /// (item, plainText) → copy without pasting.
    var onCopy: ((ClipItem, Bool) -> Void)?
    var onOpenSettings: (() -> Void)?
    var onOpen: ((ClipItem) -> Void)?
    /// Paste arbitrary text (⌘K results).
    var onPasteText: ((String) -> Void)?
    var onOpenURL: ((URL) -> Void)?

    private var chipCache: [String: [SmartChip]] = [:]

    /// Smart suggestions for a card. Cached per content; masked identifiers never get chips.
    func chips(for item: ClipItem) -> [SmartChip] {
        guard prefs.smartActions, item.maskedPreview == nil, let text = item.text,
              [.text, .richText, .code, .link, .color].contains(item.kind) else { return [] }
        let key = item.contentHash
        if let cached = chipCache[key] { return cached }
        let chips = SmartDetector.chips(for: text)
        chipCache[key] = chips
        return chips
    }

    /// ⌘J / chip click: links open directly; text results open ⌘K with the suggestion highlighted.
    func runSmart(_ item: ClipItem) {
        guard let chip = chips(for: item).first else { NSSound.beep(); return }
        switch chip.action {
        case .open(let url): onOpenURL?(url)
        case .text: editor = .actions(item.id)
        }
    }

    /// ⌘⌘K "save as new card": goes through the normal capture path so it's classified and searchable.
    func saveAsNewItem(_ text: String) {
        let kind = Classifier.kind(for: CaptureFacts(string: text))
        let reason = SensitiveDetector.reason(for: text)
        let capture = NewCapture(kind: reason?.isIdentifier == true ? .text : kind, text: text,
                                 sourceBundleID: Bundle.main.bundleIdentifier, sourceAppName: "myPaste",
                                 contentHash: kind.rawValue + ":" + SHA256.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined(),
                                 sensitiveReason: reason?.rawValue)
        if let id = try? store.insert(capture, sensitiveTTL: prefs.sensitiveTTL) {
            reload()
            selectedID = id
            showToast("Saved as new card")
        }
    }

    /// Deleted from the UI but not yet from disk, newest last, so ⌘Z can bring them back.
    private var pendingDeletes: [Int64] = []
    private var toastTimer: Timer?
    private var reloadScheduled = false
    static let undoWindow: TimeInterval = 10
    static let maxUndo = 10

    init(store: ClipStore, prefs: Preferences) {
        self.store = store
        self.prefs = prefs
        reload()
    }

    // MARK: Loading

    /// Coalesces bursts of store writes into one reload on the next main-loop turn.
    func scheduleReload() {
        guard !reloadScheduled else { return }
        reloadScheduled = true
        DispatchQueue.main.async { [weak self] in
            self?.reloadScheduled = false
            self?.reload()
        }
    }

    func reload() {
        if chipCache.count > 2000 { chipCache.removeAll() }
        items = Perf.measure("reload") { (try? store.allItems()) ?? [] }
        pinboards = (try? store.pinboards()) ?? []
        if case .board(let id) = tab, !pinboards.contains(where: { $0.id == id }) { tab = .history }
        recompute(resetSelection: false)
    }

    var query: SearchQuery { SearchQuery.parse(search) }

    /// A search on a pinboard tab widens to History + every board (Settings → Appearance → Pinboards).
    var searchesEverywhere: Bool { prefs.searchEverywhere && !query.isEmpty }

    func recompute(resetSelection: Bool) {
        Perf.measure("recompute") { recomputeNow(resetSelection: resetSelection) }
    }

    private func recomputeNow(resetSelection: Bool) {
        let pending = Set(pendingDeletes)
        var list = items.filter { !pending.contains($0.id) }
        if case .board(let id) = tab, !searchesEverywhere { list = list.filter { $0.pinboardIDs.contains(id) } }
        switch kindFilter {
        case .all: break
        case .kind(let k): list = list.filter { $0.kind == k }
        case .sensitive: list = list.filter(\.isSensitive)
        }
        if let app = appFilter { list = list.filter { $0.sourceBundleID == app } }

        let q = query
        list = list.filter(q.matches)
        if !q.text.isEmpty {
            let ids = (try? store.search(q.text)) ?? []
            list = list.filter { ids.contains($0.id) }
        }
        visible = list
        if resetSelection || selectedID == nil || !list.contains(where: { $0.id == selectedID }) {
            selectedID = list.first?.id
        }
    }

    // MARK: Selection

    var selectedItem: ClipItem? { visible.first { $0.id == selectedID } }

    func item(_ id: Int64) -> ClipItem? { items.first { $0.id == id } }

    /// All user-driven selection changes go through here: glide animation + haptic tick when enabled.
    func select(_ id: Int64?) {
        guard id != selectedID else { return }
        if prefs.glideSelection {
            withAnimation(.spring(response: 0.32, dampingFraction: 0.8)) { selectedID = id }
        } else {
            selectedID = id
        }
        if prefs.haptics { NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now) }
        if quickLookID != nil { quickLookID = selectedID }
    }

    func moveSelection(_ delta: Int) {
        guard !visible.isEmpty else { return }
        let idx = visible.firstIndex { $0.id == selectedID } ?? 0
        select(visible[max(0, min(visible.count - 1, idx + delta))].id)
    }

    func selectEdge(last: Bool) {
        select(last ? visible.last?.id : visible.first?.id)
    }

    private var tabs: [Tab] { [.history] + pinboards.map { .board($0.id) } }

    func switchTab(_ delta: Int) {
        let idx = tabs.firstIndex(of: tab) ?? 0
        tab = tabs[(idx + delta + tabs.count) % tabs.count]
    }

    /// 0 = History, 1–9 = Nth pinboard.
    func jumpToTab(_ n: Int) {
        guard n < tabs.count else { NSSound.beep(); return }
        tab = tabs[n]
    }

    /// Tab / ⇧Tab: All → each kind → Sensitive → All.
    func cycleKindFilter(_ delta: Int) {
        let order: [KindFilter] = [.all] + ContentKind.allCases.map { .kind($0) } + [.sensitive]
        let idx = order.firstIndex(of: kindFilter) ?? 0
        kindFilter = order[(idx + delta + order.count) % order.count]
    }

    func prepareForShow() {
        now = Date()
        editor = nil
        quickLookID = nil
        showKeys = false
        plainMode = false
        if !search.isEmpty { search = "" }
        recompute(resetSelection: true)
        focusToken += 1
        shownAt = Date()
        entranceToken += 1
    }

    /// Distinct source apps across all items, most recent first, for the app filter menu.
    var sourceApps: [(id: String, name: String)] {
        var seen = Set<String>()
        var out: [(String, String)] = []
        for item in items {
            guard let id = item.sourceBundleID, !seen.contains(id) else { continue }
            seen.insert(id)
            out.append((id, item.sourceAppName ?? id))
        }
        return out.map { (id: $0.0, name: $0.1) }
    }

    // MARK: Paste / copy

    /// Pulses the card, then hands off; the short delay lets the pulse register before the panel closes.
    func paste(_ item: ClipItem, plain explicitPlain: Bool = false) {
        let plain = explicitPlain || plainMode
        withAnimation(.spring(response: 0.18, dampingFraction: 0.5)) { pulseID = item.id }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { [weak self] in
            self?.pulseID = nil
            self?.onPaste?(item, plain)
        }
    }

    func pasteSelected(plain: Bool) {
        if let item = selectedItem { paste(item, plain: plain) }
    }

    func quickPaste(index: Int, plain: Bool) {
        guard index < visible.count else { NSSound.beep(); return }
        paste(visible[index], plain: plain)
    }

    // MARK: Delete / undo

    /// Hides the card now and deletes it from disk after the undo window.
    func delete(_ item: ClipItem) {
        let idx = visible.firstIndex { $0.id == item.id } ?? 0
        if quickLookID == item.id { quickLookID = nil }
        pendingDeletes.append(item.id)
        SoundFX.shared.play(.delete)
        if pendingDeletes.count > Self.maxUndo { commit(pendingDeletes.removeFirst()) }
        withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) { recompute(resetSelection: false) }
        if !visible.isEmpty { selectedID = visible[min(idx, visible.count - 1)].id }
        showToast("Deleted · ⌘Z to undo")
        let id = item.id
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.undoWindow) { [weak self] in
            guard let self, let i = self.pendingDeletes.firstIndex(of: id) else { return }
            self.commit(self.pendingDeletes.remove(at: i))
        }
    }

    var canUndo: Bool { !pendingDeletes.isEmpty }

    func undoDelete() {
        guard let id = pendingDeletes.popLast() else { NSSound.beep(); return }
        withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) { recompute(resetSelection: false) }
        selectedID = id
        showToast("Restored")
    }

    /// Flush pending deletes, e.g. on quit.
    func commitPendingDeletes() {
        pendingDeletes.forEach(commit)
        pendingDeletes.removeAll()
    }

    private func commit(_ id: Int64) { try? store.delete(id) }

    func showToast(_ text: String) {
        withAnimation(.easeOut(duration: 0.15)) { toast = text }
        toastTimer?.invalidate()
        toastTimer = Timer.scheduledTimer(withTimeInterval: 2.5, repeats: false) { [weak self] _ in
            withAnimation(.easeIn(duration: 0.2)) { self?.toast = nil }
        }
    }

    // MARK: Pinning

    private var lastBoardID: Int64? {
        get { (AppDefaults.store.object(forKey: "lastPinboardID") as? NSNumber)?.int64Value }
        set { AppDefaults.store.set(newValue.map(NSNumber.init(value:)), forKey: "lastPinboardID") }
    }

    func togglePin(_ item: ClipItem, board: Int64) {
        if item.pinboardIDs.contains(board) {
            try? store.unpin(item.id, from: board)
        } else {
            try? store.pin(item.id, to: board)
            lastBoardID = board
            dropPin(on: item.id)
        }
    }

    /// ⌘P: unpin everywhere if pinned, else pin to the last-used board (creating "Pinned" if none exist).
    func quickPin(_ item: ClipItem) {
        if item.isPinned {
            unpinAll(item)
            showToast("Unpinned")
            return
        }
        let board = pinboards.first { $0.id == lastBoardID } ?? pinboards.first
        let boardID = board?.id ?? (try? store.createPinboard(name: "Pinned", colorHex: Format.boardColors[0]))
        guard let boardID else { return }
        togglePin(item, board: boardID)
        showToast("Pinned to \(board?.name ?? "Pinned")")
    }

    func unpinAll(_ item: ClipItem) {
        for b in item.pinboardIDs { try? store.unpin(item.id, from: b) }
    }

    private func dropPin(on id: Int64) {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.55)) { pinDropID = id }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) { [weak self] in
            if self?.pinDropID == id { withAnimation(.easeOut(duration: 0.2)) { self?.pinDropID = nil } }
        }
    }

    func createBoard(name: String, color: String, pin itemID: Int64?) {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, let id = try? store.createPinboard(name: trimmed, colorHex: color) else { return }
        if let itemID { try? store.pin(itemID, to: id); lastBoardID = id; dropPin(on: itemID) }
        reload()
    }

    func toggleQuickLook() {
        quickLookID = quickLookID == nil ? selectedID : nil
    }
}
