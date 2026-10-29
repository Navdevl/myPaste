import Foundation

/// The search box mini-language: `/img` type filters, `@slack` source-app filters, `#tag` filters,
/// and everything else as full-text terms. Tokens combine with AND.
public struct SearchQuery: Equatable {
    public var kinds: Set<ContentKind> = []
    public var sensitiveOnly = false
    public var apps: [String] = []
    public var tags: [String] = []
    public var text = ""

    public var isEmpty: Bool { kinds.isEmpty && !sensitiveOnly && apps.isEmpty && tags.isEmpty && text.isEmpty }

    /// Aliases per kind; any prefix of 2+ characters of an alias also matches ("/im" → image).
    public static let kindAliases: [(ContentKind, [String])] = [
        (.image, ["image", "img", "picture", "photo", "screenshot"]),
        (.link, ["link", "url"]),
        (.code, ["code", "snippet"]),
        (.richText, ["rich", "richtext", "formatted"]),
        (.text, ["text", "plain"]),
        (.file, ["file", "doc"]),
        (.color, ["color", "colour", "hex"]),
        (.email, ["email", "mail"]),
        (.phone, ["phone", "tel"]),
    ]
    static let sensitiveAliases = ["secret", "sensitive", "otp", "key"]

    public init() {}

    public static func parse(_ raw: String) -> SearchQuery {
        var q = SearchQuery()
        var words: [String] = []
        for token in raw.split(whereSeparator: \.isWhitespace).map(String.init) {
            let body = String(token.dropFirst()).lowercased()
            switch token.first {
            case "/" where !body.isEmpty:
                if let kind = kind(for: body) { q.kinds.insert(kind) }
                else if matches(body, sensitiveAliases) { q.sensitiveOnly = true }
                else { words.append(token) } // e.g. a path like /usr stays a text term
            case "@" where !body.isEmpty: q.apps.append(body)
            case "#" where !body.isEmpty: q.tags.append(body)
            default: words.append(token)
            }
        }
        q.text = words.joined(separator: " ")
        return q
    }

    public static func kind(for word: String) -> ContentKind? {
        kindAliases.first { matches(word, $0.1) }?.0
    }

    private static func matches(_ word: String, _ aliases: [String]) -> Bool {
        word.count >= 2 && aliases.contains { $0.hasPrefix(word) }
    }

    /// Non-text filters only; full-text terms go through ClipStore.search.
    public func matches(_ item: ClipItem) -> Bool {
        if !kinds.isEmpty && !kinds.contains(item.kind) { return false }
        if sensitiveOnly && !item.isSensitive { return false }
        for app in apps {
            let name = item.sourceAppName?.lowercased() ?? ""
            let id = item.sourceBundleID?.lowercased() ?? ""
            if !name.contains(app) && !id.contains(app) { return false }
        }
        for tag in tags where !item.tags.contains(where: { $0.lowercased().hasPrefix(tag) }) { return false }
        return true
    }
}
