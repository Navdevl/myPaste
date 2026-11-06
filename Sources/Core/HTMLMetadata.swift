import Foundation

/// Link-preview fields scraped from a page's <head>: Open Graph / Twitter card tags, <title>, icons.
/// LinkPresentation fails on many ordinary pages ("Frame load interrupted"), so this is the primary path.
public struct HTMLMetadata: Equatable {
    public var title: String?
    public var imageURL: URL?
    public var iconURL: URL?

    public init(title: String? = nil, imageURL: URL? = nil, iconURL: URL? = nil) {
        self.title = title
        self.imageURL = imageURL
        self.iconURL = iconURL
    }

    private static let tagRegex = try! NSRegularExpression(pattern: #"<(meta|link)\b[^>]*>"#, options: [.caseInsensitive])
    private static let attrRegex = try! NSRegularExpression(
        pattern: #"([a-zA-Z_:][-a-zA-Z0-9_:.]*)\s*=\s*(?:"([^"]*)"|'([^']*)'|([^\s"'>]+))"#)
    private static let titleRegex = try! NSRegularExpression(
        pattern: #"<title[^>]*>([\s\S]*?)</title>"#, options: [.caseInsensitive])

    /// Parses the first ~512 KB of `html`; relative URLs resolve against `base` (the final, post-redirect URL).
    public static func parse(html fullHTML: String, base: URL) -> HTMLMetadata {
        let html = String(fullHTML.prefix(512_000))
        let range = NSRange(html.startIndex..., in: html)
        var meta: [String: String] = [:]
        var icons: [(rank: Int, href: String)] = []

        for match in tagRegex.matches(in: html, range: range) {
            guard let tagRange = Range(match.range, in: html), let nameRange = Range(match.range(at: 1), in: html) else { continue }
            let tag = String(html[tagRange])
            let attrs = attributes(of: tag)
            if html[nameRange].lowercased() == "meta" {
                let key = (attrs["property"] ?? attrs["name"] ?? "").lowercased()
                if let content = attrs["content"], !key.isEmpty, meta[key] == nil { meta[key] = content }
            } else if let rel = attrs["rel"]?.lowercased(), let href = attrs["href"] {
                // Prefer large touch icons, then explicit icons, then legacy "shortcut icon".
                if rel.contains("apple-touch-icon") { icons.append((0, href)) }
                else if rel.split(separator: " ").contains("icon") { icons.append((1, href)) }
            }
        }

        var title = meta["og:title"] ?? meta["twitter:title"]
        if title == nil, let m = titleRegex.firstMatch(in: html, range: range), let r = Range(m.range(at: 1), in: html) {
            title = String(html[r])
        }
        title = title.map(decodeEntities).map { $0.split(whereSeparator: \.isWhitespace).joined(separator: " ") }
        if title?.isEmpty == true { title = nil }

        let image = (meta["og:image:secure_url"] ?? meta["og:image"] ?? meta["og:image:url"] ?? meta["twitter:image"] ?? meta["twitter:image:src"])
            .flatMap { resolve($0, base) }
        let icon = icons.sorted { $0.rank < $1.rank }.first.flatMap { resolve($0.href, base) }
            ?? URL(string: "/favicon.ico", relativeTo: base)?.absoluteURL
        return HTMLMetadata(title: title, imageURL: image, iconURL: icon)
    }

    /// Where a "Redirecting…" stub page sends the browser: `<meta http-equiv="refresh" content="0; url=…">`
    /// with a short delay. HTTP redirects are followed by URLSession; this is the HTML kind it can't see.
    public static func refreshTarget(html fullHTML: String, base: URL) -> URL? {
        let html = String(fullHTML.prefix(64_000))
        for match in tagRegex.matches(in: html, range: NSRange(html.startIndex..., in: html)) {
            guard let r = Range(match.range, in: html) else { continue }
            let attrs = attributes(of: String(html[r]))
            guard attrs["http-equiv"]?.lowercased() == "refresh", let content = attrs["content"] else { continue }
            let parts = content.split(separator: ";", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
            guard parts.count == 2, (Double(parts[0]) ?? 99) <= 5, parts[1].lowercased().hasPrefix("url=") else { continue }
            let target = parts[1].dropFirst(4).trimmingCharacters(in: CharacterSet(charactersIn: " \"'"))
            return resolve(target, base)
        }
        return nil
    }

    static func attributes(of tag: String) -> [String: String] {
        var out: [String: String] = [:]
        for m in attrRegex.matches(in: tag, range: NSRange(tag.startIndex..., in: tag)) {
            guard let k = Range(m.range(at: 1), in: tag) else { continue }
            let value = (2...4).lazy.compactMap { Range(m.range(at: $0), in: tag) }.first.map { String(tag[$0]) } ?? ""
            out[tag[k].lowercased()] = decodeEntities(value)
        }
        return out
    }

    private static func resolve(_ raw: String, _ base: URL) -> URL? {
        let s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !s.isEmpty, !s.hasPrefix("data:") else { return nil }
        guard let url = URL(string: s, relativeTo: base)?.absoluteURL, ["http", "https"].contains(url.scheme?.lowercased() ?? "") else { return nil }
        return url
    }

    static func decodeEntities(_ s: String) -> String {
        guard s.contains("&") else { return s }
        var out = s
        // &amp; last, so "&amp;lt;" stays the literal text "&lt;".
        for (entity, ch) in [("&quot;", "\""), ("&#39;", "'"), ("&apos;", "'"), ("&lt;", "<"), ("&gt;", ">"),
                             ("&nbsp;", " "), ("&ndash;", "–"), ("&mdash;", "—"), ("&middot;", "·"), ("&hellip;", "…"),
                             ("&lsquo;", "‘"), ("&rsquo;", "’"), ("&ldquo;", "“"), ("&rdquo;", "”"), ("&bull;", "•"),
                             ("&laquo;", "«"), ("&raquo;", "»"), ("&copy;", "©"), ("&reg;", "®"), ("&trade;", "™"),
                             ("&amp;", "&")] {
            out = out.replacingOccurrences(of: entity, with: ch)
        }
        let numeric = try! NSRegularExpression(pattern: #"&#(x[0-9a-fA-F]+|[0-9]+);"#)
        for m in numeric.matches(in: out, range: NSRange(out.startIndex..., in: out)).reversed() {
            guard let whole = Range(m.range, in: out), let numR = Range(m.range(at: 1), in: out) else { continue }
            let num = out[numR]
            let value = num.hasPrefix("x") ? UInt32(num.dropFirst(), radix: 16) : UInt32(num)
            if let v = value, let scalar = Unicode.Scalar(v) { out.replaceSubrange(whole, with: String(Character(scalar))) }
        }
        return out
    }
}
