import AppKit
import MyPasteCore
import ApplicationServices

/// Puts items back on the pasteboard and, with Accessibility permission, sends ⌘V to the frontmost app.
enum Paster {
    static var isTrusted: Bool { AXIsProcessTrusted() }

    @discardableResult
    static func requestTrust() -> Bool {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        return AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
    }

    static func openAccessibilitySettings() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
    }

    static func write(_ item: ClipItem, store: ClipStore, plainText: Bool) {
        let pb = NSPasteboard.general
        pb.clearContents()
        switch item.kind {
        case .image:
            if let png = store.blob(item, "png") {
                pb.setData(png, forType: .png)
                if let tiff = NSImage(data: png)?.tiffRepresentation { pb.setData(tiff, forType: .tiff) }
            }
        case .file:
            let urls = item.filePaths.map { URL(fileURLWithPath: $0) as NSURL }
            pb.writeObjects(urls)
        default:
            let text = item.text ?? ""
            if !plainText {
                if item.hasRTF, let rtf = store.blob(item, "rtf") { pb.setData(rtf, forType: .rtf) }
                if item.hasHTML, let html = store.blob(item, "html") { pb.setData(html, forType: .html) }
                if item.kind == .link, URL(string: text) != nil { pb.setString(text, forType: .URL) }
            }
            pb.setString(text, forType: .string)
        }
        pb.setData(Data(), forType: PasteboardMonitor.internalType)
    }

    /// Synthesises ⌘V. Explicit flags so a still-held Shift (from ⇧↩) doesn't turn it into ⇧⌘V.
    static func postCommandV() {
        let src = CGEventSource(stateID: .combinedSessionState)
        let vKey: CGKeyCode = 0x09
        let down = CGEvent(keyboardEventSource: src, virtualKey: vKey, keyDown: true)
        let up = CGEvent(keyboardEventSource: src, virtualKey: vKey, keyDown: false)
        down?.flags = .maskCommand
        up?.flags = .maskCommand
        down?.post(tap: .cgAnnotatedSessionEventTap)
        up?.post(tap: .cgAnnotatedSessionEventTap)
    }
}
