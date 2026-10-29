import AppKit
import MyPasteCore
import SwiftUI

/// Paste Stack: while active, every copy is queued; each ⌘V in any app pastes the next item in order.
final class PasteStack: ObservableObject {
    @Published private(set) var isActive = false
    @Published private(set) var queue: [ClipItem] = []

    private let store: ClipStore
    private let monitor: PasteboardMonitor
    private var keyMonitor: Any?
    private var hud: NSPanel?

    init(store: ClipStore, monitor: PasteboardMonitor) {
        self.store = store
        self.monitor = monitor
    }

    func toggle() { isActive ? stop() : start() }

    func start() {
        guard !isActive else { return }
        isActive = true
        queue = []
        if !Paster.isTrusted { Paster.requestTrust() }
        // Global key monitors only see other apps' events and need Accessibility; (re)install each start.
        keyMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            let flags = event.modifierFlags.intersection([.command, .shift, .option, .control])
            if event.keyCode == 0x09, flags == .command { self?.didPaste() }
        }
        showHUD()
    }

    func stop() {
        isActive = false
        queue = []
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        keyMonitor = nil
        hud?.orderOut(nil)
    }

    /// Called for each captured copy while active, and from "Add to Paste Stack".
    func append(_ item: ClipItem) {
        if !isActive { start() }
        guard !queue.contains(where: { $0.id == item.id }) else { return }
        queue.append(item)
        loadHead()
    }

    private func didPaste() {
        guard !queue.isEmpty else { return }
        // Let the target app read the pasteboard before we swap in the next item.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
            guard let self, !self.queue.isEmpty else { return }
            self.queue.removeFirst()
            if self.queue.isEmpty { self.stop() } else { self.loadHead() }
        }
    }

    private func loadHead() {
        guard let head = queue.first else { return }
        Paster.write(head, store: store, plainText: false)
        monitor.skipCurrent()
    }

    private func showHUD() {
        if hud == nil {
            let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 320, height: 96),
                                styleMask: [.nonactivatingPanel, .borderless], backing: .buffered, defer: false)
            panel.level = .statusBar
            panel.isOpaque = false
            panel.backgroundColor = .clear
            panel.hasShadow = true
            panel.ignoresMouseEvents = false
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
            panel.contentView = NSHostingView(rootView: StackHUD(stack: self))
            hud = panel
        }
        guard let hud, let screen = NSScreen.main else { return }
        let f = screen.visibleFrame
        hud.setFrameOrigin(NSPoint(x: f.maxX - 340, y: f.maxY - 116))
        hud.orderFrontRegardless()
    }
}

struct StackHUD: View {
    @ObservedObject var stack: PasteStack

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: "square.stack.3d.up.fill").foregroundStyle(.tint)
                Text("Paste Stack").font(.headline)
                Spacer()
                Text("\(stack.queue.count)").font(.headline.monospacedDigit())
                Button { stack.stop() } label: { Image(systemName: "xmark.circle.fill") }
                    .buttonStyle(.plain).foregroundStyle(.secondary)
            }
            if let next = stack.queue.first {
                Text("Next: " + (next.title ?? next.text ?? next.kind.label).replacingOccurrences(of: "\n", with: " "))
                    .lineLimit(1).font(.callout)
            } else {
                Text("Copy items to queue them.").font(.callout)
            }
            Text("⌘V pastes the next item · ⇧⌘C ends").font(.caption).foregroundStyle(.secondary)
        }
        .padding(14)
        .frame(width: 320, height: 96)
        .glassSurface(cornerRadius: 14)
    }
}
