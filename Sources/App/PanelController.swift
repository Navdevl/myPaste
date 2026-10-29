import AppKit
import MyPasteCore
import Carbon.HIToolbox
import Combine
import SwiftUI

/// Borderless, non-activating panel: takes keyboard input without stealing focus from the target app.
final class StripPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

final class PanelController: NSObject, NSWindowDelegate {
    static let height: CGFloat = 340

    private let model: AppModel
    private let panel: StripPanel
    private var quickLook: NSPanel?
    private var keyMonitor: Any?
    private var cancellables = Set<AnyCancellable>()
    private(set) var isVisible = false

    init(model: AppModel) {
        self.model = model
        panel = StripPanel(contentRect: NSRect(x: 0, y: 0, width: 1200, height: Self.height),
                           styleMask: [.nonactivatingPanel, .borderless, .fullSizeContentView],
                           backing: .buffered, defer: false)
        super.init()
        panel.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.popUpMenuWindow)))
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.isMovable = false
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.delegate = self

        let host = NSHostingView(rootView: StripView().environmentObject(model))
        panel.contentView = Self.backdrop(hosting: host)

        model.$quickLookID.receive(on: RunLoop.main).sink { [weak self] id in self?.updateQuickLook(id) }.store(in: &cancellables)
    }

    /// Liquid Glass on macOS 26; the HUD blur material elsewhere.
    private static func backdrop(hosting host: NSView) -> NSView {
        if #available(macOS 26.0, *) {
            let glass = NSGlassEffectView()
            glass.cornerRadius = 22
            glass.contentView = host
            return glass
        }
        let blur = NSVisualEffectView()
        blur.material = .hudWindow
        blur.blendingMode = .behindWindow
        blur.state = .active
        blur.wantsLayer = true
        blur.layer?.cornerRadius = 18
        blur.layer?.maskedCorners = [.layerMinXMaxYCorner, .layerMaxXMaxYCorner]
        host.translatesAutoresizingMaskIntoConstraints = false
        blur.addSubview(host)
        NSLayoutConstraint.activate([
            host.leadingAnchor.constraint(equalTo: blur.leadingAnchor),
            host.trailingAnchor.constraint(equalTo: blur.trailingAnchor),
            host.topAnchor.constraint(equalTo: blur.topAnchor),
            host.bottomAnchor.constraint(equalTo: blur.bottomAnchor),
        ])
        return blur
    }

    func toggle() { isVisible ? hide() : show() }

    func show() {
        guard !isVisible else { return }
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main ?? NSScreen.screens[0]
        let target = NSRect(x: screen.frame.minX, y: screen.frame.minY, width: screen.frame.width, height: Self.height)
        model.prepareForShow()
        // Frame is set once; the slide is a layer transform. Animating the window frame re-ran
        // SwiftUI layout every frame (~130 ms of main-thread time per open with 2,000 items).
        if panel.frame != target { panel.setFrame(target, display: false) }
        panel.alphaValue = 0
        panel.makeKeyAndOrderFront(nil)
        isVisible = true
        slide(from: -Self.height * 0.35, to: 0, duration: 0.2)
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.16
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().alphaValue = 1
        }
        installKeyMonitor()
    }

    func hide() {
        guard isVisible else { return }
        isVisible = false
        model.quickLookID = nil
        model.editor = nil
        removeKeyMonitor()
        slide(from: 0, to: -Self.height * 0.35, duration: 0.12)
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.12
            panel.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            guard let self, !self.isVisible else { return }
            self.panel.orderOut(nil)
        })
    }

    /// Vertical slide on the content layer: GPU-only, no AppKit/SwiftUI layout during the animation.
    private func slide(from: CGFloat, to: CGFloat, duration: CFTimeInterval) {
        guard let view = panel.contentView else { return }
        view.wantsLayer = true
        guard let layer = view.layer else { return }
        let anim = CABasicAnimation(keyPath: "transform.translation.y")
        anim.fromValue = from
        anim.toValue = to
        anim.duration = duration
        anim.timingFunction = CAMediaTimingFunction(name: to == 0 ? .easeOut : .easeIn)
        anim.fillMode = .forwards
        anim.isRemovedOnCompletion = to != 0
        layer.add(anim, forKey: "slide")
        layer.transform = CATransform3DMakeTranslation(0, to, 0)
    }

    /// Hides immediately (no animation) so focus is back on the target app before ⌘V is posted.
    func hideNow() {
        isVisible = false
        model.quickLookID = nil
        model.editor = nil
        removeKeyMonitor()
        panel.orderOut(nil)
        panel.contentView?.layer?.removeAnimation(forKey: "slide")
        panel.contentView?.layer?.transform = CATransform3DIdentity
    }

    func windowDidResignKey(_ notification: Notification) {
        // Clicking outside (another app or the desktop) dismisses, like Paste.
        if isVisible { hide() }
    }

    // MARK: Keyboard

    /// Number row and keypad. Used when ⌥ turns the typed character into a symbol (⌥1 → ¡).
    private static let digitKeys: [Int: Int] = [
        kVK_ANSI_0: 0, kVK_ANSI_1: 1, kVK_ANSI_2: 2, kVK_ANSI_3: 3, kVK_ANSI_4: 4,
        kVK_ANSI_5: 5, kVK_ANSI_6: 6, kVK_ANSI_7: 7, kVK_ANSI_8: 8, kVK_ANSI_9: 9,
        kVK_ANSI_Keypad0: 0, kVK_ANSI_Keypad1: 1, kVK_ANSI_Keypad2: 2, kVK_ANSI_Keypad3: 3, kVK_ANSI_Keypad4: 4,
        kVK_ANSI_Keypad5: 5, kVK_ANSI_Keypad6: 6, kVK_ANSI_Keypad7: 7, kVK_ANSI_Keypad8: 8, kVK_ANSI_Keypad9: 9,
    ]

    /// The typed digit (layout-aware) first, the key position as a fallback.
    private static func digit(_ ch: String, _ code: Int) -> Int? {
        (ch.count == 1 ? Int(ch) : nil) ?? digitKeys[code]
    }
    /// How long ⌘ must be held alone before edit mode (jiggle, ✕, badges, shortcut bar) appears.
    private static let holdDelay: TimeInterval = 0.5

    private var holdTimer: Timer?
    private var shiftTimer: Timer?

    private func installKeyMonitor() {
        removeKeyMonitor()
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { [weak self] event in
            guard let self, event.window === self.panel || event.window === nil else { return event }
            if event.type == .flagsChanged { self.flagsChanged(event); return event }
            guard event.window === self.panel else { return event }
            // A chord started before the hold delay: it's a shortcut, not a request for hints.
            self.holdTimer?.invalidate()
            self.shiftTimer?.invalidate()
            return self.handle(event) ? nil : event
        }
    }

    private func removeKeyMonitor() {
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        keyMonitor = nil
        holdTimer?.invalidate()
        shiftTimer?.invalidate()
        if model.editMode { setEditMode(false) }
        model.plainMode = false
    }

    private func flagsChanged(_ e: NSEvent) {
        let flags = e.modifierFlags.intersection([.command, .shift, .option, .control])
        // ⇧ alone, held: plain-text mode. Typing a capital cancels it via the keyDown path.
        if flags == .shift {
            guard !model.plainMode, shiftTimer?.isValid != true, model.editor == nil else { return }
            shiftTimer = Timer.scheduledTimer(withTimeInterval: Self.holdDelay, repeats: false) { [weak self] _ in
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { self?.model.plainMode = true }
            }
        } else if !flags.contains(.shift) {
            shiftTimer?.invalidate()
            if model.plainMode { withAnimation(.easeOut(duration: 0.15)) { model.plainMode = false } }
        }
        if flags.contains(.command) {
            guard !model.editMode, holdTimer?.isValid != true, model.editor == nil else { return }
            holdTimer = Timer.scheduledTimer(withTimeInterval: Self.holdDelay, repeats: false) { [weak self] _ in
                self?.setEditMode(true)
            }
        } else {
            holdTimer?.invalidate()
            if model.editMode { setEditMode(false) }
        }
    }

    private func setEditMode(_ on: Bool) {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { model.editMode = on }
    }

    /// Returns true when the key was consumed. Keys not handled here fall through to the search field,
    /// so ⌘⌫ / ⌥⌫ / ⌘A / ⌘← in text behave like any macOS text field.
    private func handle(_ e: NSEvent) -> Bool {
        let flags = e.modifierFlags.intersection([.command, .shift, .option, .control])
        let code = Int(e.keyCode)
        let ch = e.charactersIgnoringModifiers?.lowercased() ?? ""

        if let editor = model.editor {
            if code == kVK_Escape { model.editor = nil; return true }
            if case .pinPicker(let id) = editor, flags.isEmpty, let n = Self.digit(ch, code), n >= 1 {
                if n <= model.pinboards.count, let item = model.item(id) { model.togglePin(item, board: model.pinboards[n - 1].id) }
                model.editor = nil
                return true
            }
            if case .info = editor, code == kVK_ANSI_I, flags == .command { model.editor = nil; return true }
            return false
        }

        switch (code, flags) {
        case (kVK_Escape, _):
            if model.quickLookID != nil { model.quickLookID = nil } else if !model.search.isEmpty { model.search = "" } else { hide() }
            return true

        // Selection and tabs
        case (kVK_LeftArrow, []), (kVK_LeftArrow, .shift): model.moveSelection(-1); return true
        case (kVK_RightArrow, []), (kVK_RightArrow, .shift): model.moveSelection(1); return true
        case (kVK_LeftArrow, .command) where model.search.isEmpty: model.switchTab(-1); return true
        case (kVK_RightArrow, .command) where model.search.isEmpty: model.switchTab(1); return true
        case (kVK_UpArrow, []): model.switchTab(-1); return true
        case (kVK_DownArrow, []): model.switchTab(1); return true
        case (kVK_UpArrow, .command), (kVK_Home, _): model.selectEdge(last: false); return true
        case (kVK_DownArrow, .command), (kVK_End, _): model.selectEdge(last: true); return true
        case (kVK_Tab, []): model.cycleKindFilter(1); return true
        case (kVK_Tab, .shift): model.cycleKindFilter(-1); return true

        // Paste / preview
        case (kVK_Return, _), (kVK_ANSI_KeypadEnter, _):
            model.pasteSelected(plain: flags.contains(.shift))
            return true
        case (kVK_Space, []) where model.search.isEmpty || model.quickLookID != nil:
            model.toggleQuickLook()
            return true

        // ⌘⇧⌫ deletes the card; plain ⌘⌫ / ⌥⌫ are left to the search field.
        case (kVK_Delete, [.command, .shift]), (kVK_ForwardDelete, [.command, .shift]):
            if let item = model.selectedItem { model.delete(item) } else { NSSound.beep() }
            return true
        default:
            break
        }

        if let n = Self.digit(ch, code) {
            if (flags == .command || flags == [.command, .shift]), n >= 1 {
                model.quickPaste(index: n - 1, plain: flags.contains(.shift))
                return true
            }
            if flags == .option { model.jumpToTab(n); return true }
        }

        if flags == .command {
            let item = model.selectedItem
            switch ch {
            case "z":
                // Undo a card delete; with no pending delete, ⌘Z undoes typing in the search field.
                guard model.canUndo else { return false }
                model.undoDelete(); return true
            case "c": if let item { model.onCopy?(item, false) }; return true
            case "p": if let item { model.quickPin(item) }; return true
            case "o": if let item { model.onOpen?(item) }; return true
            case "i": if let item { model.editor = .info(item.id) }; return true
            case "k":
                if let item, item.text != nil, item.kind != .image, item.kind != .file { model.editor = .actions(item.id) } else { NSSound.beep() }
                return true
            case "r": if let item { model.editor = .rename(item.id) }; return true
            case "t": if let item { model.editor = .tags(item.id) }; return true
            case "e": if let item, item.kind != .image, item.kind != .file { model.editor = .editText(item.id) }; return true
            case "n": model.editor = .newBoard(pinItem: nil); return true
            case ",": model.onOpenSettings?(); return true
            case "w": hide(); return true
            default: return false
            }
        }
        // ⌥⌘C, not ⇧⌘C: the global Paste Stack shortcut owns ⇧⌘C and would fire first.
        if flags == [.command, .option], code == kVK_ANSI_C {
            if let item = model.selectedItem { model.onCopy?(item, true) }
            return true
        }
        if flags == [.command, .shift] {
            let item = model.selectedItem
            switch ch {
            case "p": if let item { model.editor = .pinPicker(item.id) }; return true
            case "n": model.editor = .newBoard(pinItem: nil); return true
            default: return false
            }
        }
        return false
    }

    // MARK: Quick Look

    private func updateQuickLook(_ id: Int64?) {
        guard let id, isVisible, let item = model.item(id) else {
            quickLook?.orderOut(nil)
            return
        }
        if quickLook == nil {
            let p = NSPanel(contentRect: .zero, styleMask: [.nonactivatingPanel, .borderless], backing: .buffered, defer: false)
            p.level = panel.level
            p.isOpaque = false
            p.backgroundColor = .clear
            p.hasShadow = true
            p.collectionBehavior = panel.collectionBehavior
            quickLook = p
        }
        guard let ql = quickLook, let screen = panel.screen else { return }
        let w = min(screen.frame.width * 0.6, 900)
        let h = min(screen.frame.height - Self.height - 80, 620)
        ql.setFrame(NSRect(x: screen.frame.midX - w / 2, y: screen.frame.minY + Self.height + 20, width: w, height: h), display: false)
        ql.contentView = NSHostingView(rootView: QuickLookView(item: item).environmentObject(model))
        ql.orderFront(nil)
    }
}
