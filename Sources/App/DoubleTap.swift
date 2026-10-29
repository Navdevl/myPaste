import AppKit

/// Detects a double tap of a lone modifier (default ⌃): press–release, press–release, each tap under
/// `tapMax` and the second starting within `gapMax` of the first. Any other key or modifier in
/// between cancels, so ⌃C, ⌃Tab and ⌃-click never count.
final class DoubleTapDetector {
    private let modifier: NSEvent.ModifierFlags
    private let tapMax: TimeInterval = 0.3
    private let gapMax: TimeInterval = 0.35
    private var downAt: TimeInterval?
    private var lastTapAt: TimeInterval?
    private var global: Any?
    private var local: Any?
    var onDoubleTap: (() -> Void)?

    init(modifier: NSEvent.ModifierFlags = .control) { self.modifier = modifier }

    /// Feed every .flagsChanged and .keyDown event seen by the caller.
    func handle(_ e: NSEvent) {
        let now = e.timestamp
        guard e.type == .flagsChanged else { reset(); return }
        let flags = e.modifierFlags.intersection([.command, .shift, .option, .control, .function])
        if flags == modifier {
            downAt = now
        } else if flags.isEmpty, let down = downAt {
            downAt = nil
            guard now - down <= tapMax else { reset(); return }
            if let last = lastTapAt, now - last <= gapMax + tapMax {
                lastTapAt = nil
                onDoubleTap?()
            } else {
                lastTapAt = now
            }
        } else {
            reset()
        }
    }

    private func reset() {
        downAt = nil
        lastTapAt = nil
    }

    /// System-wide monitoring (needs Accessibility). Events into our own app arrive via the local monitor.
    func startGlobal() {
        guard global == nil else { return }
        global = NSEvent.addGlobalMonitorForEvents(matching: [.flagsChanged, .keyDown]) { [weak self] e in self?.handle(e) }
        local = NSEvent.addLocalMonitorForEvents(matching: [.flagsChanged, .keyDown]) { [weak self] e in self?.handle(e); return e }
    }

    func stopGlobal() {
        if let global { NSEvent.removeMonitor(global) }
        if let local { NSEvent.removeMonitor(local) }
        global = nil
        local = nil
        reset()
    }
}
