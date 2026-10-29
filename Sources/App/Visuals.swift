import AppKit
import MyPasteCore
import ImageIO
import SwiftUI

/// Caches for app icons, icon-derived accent colours, image thumbnails and rendered rich text.
final class Visuals {
    static let shared = Visuals()

    private var icons: [String: NSImage] = [:]
    private var colors: [String: NSColor] = [:]
    private let thumbs = NSCache<NSString, NSImage>()
    private let rich = NSCache<NSString, NSAttributedString>()

    init() {
        thumbs.countLimit = 300
        rich.countLimit = 200
    }

    func icon(for bundleID: String?) -> NSImage {
        let key = bundleID ?? "?"
        if let cached = icons[key] { return cached }
        let image: NSImage
        if let id = bundleID, let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) {
            image = NSWorkspace.shared.icon(forFile: url.path)
        } else {
            image = NSImage(systemSymbolName: "questionmark.app", accessibilityDescription: nil) ?? NSImage()
        }
        icons[key] = image
        return image
    }

    /// Average of the icon's saturated, opaque pixels, darkened so white text stays readable.
    func accent(for bundleID: String?) -> Color {
        let key = bundleID ?? "?"
        if let c = colors[key] { return Color(nsColor: c) }
        let c = Self.dominantColor(icon(for: bundleID)) ?? NSColor(calibratedWhite: 0.35, alpha: 1)
        colors[key] = c
        return Color(nsColor: c)
    }

    private static func dominantColor(_ image: NSImage) -> NSColor? {
        let side = 24
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: side, pixelsHigh: side, bitsPerSample: 8,
                                         samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                                         bytesPerRow: 0, bitsPerPixel: 0) else { return nil }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        image.draw(in: NSRect(x: 0, y: 0, width: side, height: side))
        NSGraphicsContext.restoreGraphicsState()
        // Bucket saturated pixels by hue and take the heaviest bucket: averaging a multi-colour
        // icon (Slack, Chrome) would give mud. Mostly-grey icons fall back to their mean grey.
        let buckets = 12
        var weight = [Double](repeating: 0, count: buckets)
        var hue = [Double](repeating: 0, count: buckets)
        var sat = [Double](repeating: 0, count: buckets)
        var bri = [Double](repeating: 0, count: buckets)
        var grey = 0.0, greyCount = 0.0
        for x in 0..<side {
            for y in 0..<side {
                guard let c = rep.colorAt(x: x, y: y), c.alphaComponent > 0.5 else { continue }
                let s = c.saturationComponent, v = c.brightnessComponent
                guard s > 0.25, v > 0.2 else { grey += v; greyCount += 1; continue }
                let i = min(buckets - 1, Int(c.hueComponent * Double(buckets)))
                let w = s * v
                weight[i] += w; hue[i] += c.hueComponent * w; sat[i] += s * w; bri[i] += v * w
            }
        }
        guard let best = weight.indices.max(by: { weight[$0] < weight[$1] }), weight[best] > 1.5 else {
            return greyCount > 0 ? NSColor(deviceWhite: min(grey / greyCount, 0.45), alpha: 1) : nil
        }
        let w = weight[best]
        return NSColor(deviceHue: hue[best] / w, saturation: min(1, sat[best] / w * 1.05),
                       brightness: min(bri[best] / w, 0.62), alpha: 1)
    }

    /// Pays the first-open cost at launch: icons and accent colours for recent apps (main thread, a few ms
    /// each) and thumbnails for the first screenful (background).
    func prewarm(_ items: [ClipItem], store: ClipStore) {
        var seen = Set<String?>()
        for item in items.prefix(200) where seen.insert(item.sourceBundleID).inserted {
            _ = icon(for: item.sourceBundleID)
            _ = accent(for: item.sourceBundleID)
        }
        for item in items.prefix(12) {
            if item.hasImage { decodeQueue.async { _ = self.thumbnail(for: item, store: store) } }
            if item.hasLinkImage { decodeQueue.async { _ = self.thumbnail(for: item, store: store, ext: "link.png") } }
            if item.hasLinkIcon { decodeQueue.async { _ = self.thumbnail(for: item, store: store, ext: "icon.png", maxSide: 64) } }
        }
    }

    private let decodeQueue = DispatchQueue(label: "mypaste.thumbs", qos: .userInitiated, attributes: .concurrent)

    func cachedThumbnail(for item: ClipItem, ext: String, maxSide: Int) -> NSImage? {
        thumbs.object(forKey: "\(item.uuid).\(ext).\(maxSide)" as NSString)
    }

    /// Decodes off the main thread; screenshots took 100–400 ms each to downsample on the main thread.
    func loadThumbnail(for item: ClipItem, store: ClipStore, ext: String, maxSide: Int) async -> NSImage? {
        await withCheckedContinuation { cont in
            decodeQueue.async { cont.resume(returning: self.thumbnail(for: item, store: store, ext: ext, maxSide: maxSide)) }
        }
    }

    func thumbnail(for item: ClipItem, store: ClipStore, ext: String = "png", maxSide: Int = 480) -> NSImage? {
        let key = "\(item.uuid).\(ext).\(maxSide)" as NSString
        if let t = thumbs.object(forKey: key) { return t }
        let url = store.blobURL(item.uuid, ext)
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil),
              let cg = CGImageSourceCreateThumbnailAtIndex(src, 0, [
                  kCGImageSourceCreateThumbnailFromImageAlways: true,
                  kCGImageSourceThumbnailMaxPixelSize: maxSide,
                  kCGImageSourceCreateThumbnailWithTransform: true,
              ] as CFDictionary) else { return nil }
        let image = NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
        thumbs.setObject(image, forKey: key)
        return image
    }

    func cachedRichText(for item: ClipItem, limit: Int) -> AttributedString? {
        rich.object(forKey: "\(item.uuid).\(limit)" as NSString).flatMap { try? AttributedString($0, including: \.appKit) }
    }

    /// RTF parses on a background queue; HTML import uses WebKit and must stay on the main thread,
    /// so it runs after the card's first frame instead of blocking it.
    func loadRichText(for item: ClipItem, store: ClipStore, limit: Int) async -> AttributedString? {
        if item.hasRTF {
            return await withCheckedContinuation { cont in
                decodeQueue.async { cont.resume(returning: self.richText(for: item, store: store, limit: limit)) }
            }
        }
        await Task.yield()
        return await MainActor.run { richText(for: item, store: store, limit: limit) }
    }

    /// Rendered RTF/HTML, truncated for card previews.
    func richText(for item: ClipItem, store: ClipStore, limit: Int = 1500) -> AttributedString? {
        let key = "\(item.uuid).\(limit)" as NSString
        if let cached = rich.object(forKey: key) { return try? AttributedString(cached, including: \.appKit) }
        var attr: NSAttributedString?
        if item.hasRTF, let data = store.blob(item, "rtf") {
            attr = NSAttributedString(rtf: data, documentAttributes: nil)
        } else if item.hasHTML, let data = store.blob(item, "html"), data.count < 400_000 {
            attr = NSAttributedString(html: data, documentAttributes: nil)
        }
        guard let full = attr else { return nil }
        let cut = full.length > limit ? full.attributedSubstring(from: NSRange(location: 0, length: limit)) : full
        // Drop backgrounds and force the system text colour on near-black text so dark mode stays readable.
        let m = NSMutableAttributedString(attributedString: cut)
        m.removeAttribute(.backgroundColor, range: NSRange(location: 0, length: m.length))
        m.enumerateAttribute(.foregroundColor, in: NSRange(location: 0, length: m.length)) { value, range, _ in
            if let c = (value as? NSColor)?.usingColorSpace(.deviceRGB), c.brightnessComponent < 0.25 {
                m.addAttribute(.foregroundColor, value: NSColor.labelColor, range: range)
            }
        }
        rich.setObject(m, forKey: key)
        return try? AttributedString(m, including: \.appKit)
    }
}

extension Color {
    init(hex: String) {
        let c = Classifier.rgba(from: hex) ?? (0.5, 0.5, 0.5, 1)
        self.init(.sRGB, red: c.r, green: c.g, blue: c.b, opacity: c.a)
    }
}

enum Format {
    static let relative: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .abbreviated
        return f
    }()

    static func ago(_ date: Date, now: Date) -> String {
        now.timeIntervalSince(date) < 30 ? "Just now" : relative.localizedString(for: date, relativeTo: now)
    }

    static func bytes(_ n: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: n, countStyle: .file)
    }

    static func footer(_ item: ClipItem) -> String {
        switch item.kind {
        case .image: return "\(item.imageWidth) × \(item.imageHeight)"
        case .file:
            let n = item.filePaths.count
            return n == 1 ? bytes(item.byteSize) : "\(n) files · \(bytes(item.byteSize))"
        case .link: return URL(string: item.text ?? "")?.host ?? "Link"
        case .color: return item.text ?? ""
        default:
            let n = item.charCount
            return "\(n.formatted()) character\(n == 1 ? "" : "s")"
        }
    }

    static let boardColors = ["#3B82F6", "#10B981", "#F59E0B", "#EF4444", "#8B5CF6", "#EC4899", "#14B8A6", "#64748B"]
}

extension View {
    /// Liquid Glass on macOS 26; an opaque window-coloured fill elsewhere, so text stays readable
    /// over whatever sits behind a borderless panel.
    @ViewBuilder func glassSurface(cornerRadius: CGFloat) -> some View {
        if #available(macOS 26.0, *) {
            glassEffect(.regular, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        } else {
            background(Color(nsColor: .windowBackgroundColor).opacity(0.97), in: RoundedRectangle(cornerRadius: cornerRadius))
        }
    }
}

extension ClipItem {
    var sensitiveKind: SensitiveDetector.Reason? { sensitiveReason.flatMap(SensitiveDetector.Reason.init(rawValue:)) }
    var sensitiveLabel: String? { sensitiveKind?.label }

    /// Masked value for KYC/banking identifiers and cards; nil for everything else.
    var maskedPreview: String? {
        guard isSensitive, let reason = sensitiveKind, reason.isMasked, let text else { return nil }
        return SensitiveDetector.masked(text, reason: reason)
    }

    /// Pinned text with {date}/{clipboard}/{cursor}… placeholders, expanded at paste time.
    var isSnippet: Bool { isPinned && text.map(Snippet.hasPlaceholders) == true }

    /// Whether plain-text paste differs from a normal paste.
    var hasFormatting: Bool { hasRTF || hasHTML || kind == .link }

    /// One-line summary that never leaks a masked value (HUDs, toasts).
    var safeSummary: String {
        (maskedPreview ?? title ?? text ?? kind.label).replacingOccurrences(of: "\n", with: " ")
    }
}

/// Thumbnail that never decodes on the main thread: cached image immediately, else placeholder until loaded.
struct AsyncThumbnail<Content: View, Placeholder: View>: View {
    let item: ClipItem
    let store: ClipStore
    var ext = "png"
    var maxSide = 480
    @ViewBuilder let content: (NSImage) -> Content
    @ViewBuilder let placeholder: () -> Placeholder
    @State private var image: NSImage?

    var body: some View {
        Group {
            if let img = image ?? Visuals.shared.cachedThumbnail(for: item, ext: ext, maxSide: maxSide) {
                content(img)
            } else {
                placeholder()
            }
        }
        .task(id: "\(item.uuid).\(ext)") {
            guard Visuals.shared.cachedThumbnail(for: item, ext: ext, maxSide: maxSide) == nil else { return }
            image = await Visuals.shared.loadThumbnail(for: item, store: store, ext: ext, maxSide: maxSide)
        }
    }
}

/// Rich-text preview that shows plain text first and swaps in the styled version once parsed.
struct AsyncRichText<Fallback: View>: View {
    let item: ClipItem
    let store: ClipStore
    var limit = 1500
    @ViewBuilder let fallback: () -> Fallback
    @State private var attr: AttributedString?

    var body: some View {
        Group {
            if let a = attr ?? Visuals.shared.cachedRichText(for: item, limit: limit) { Text(a) } else { fallback() }
        }
        .task(id: item.uuid) {
            guard Visuals.shared.cachedRichText(for: item, limit: limit) == nil else { return }
            attr = await Visuals.shared.loadRichText(for: item, store: store, limit: limit)
        }
    }
}
