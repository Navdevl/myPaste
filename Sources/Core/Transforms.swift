import CryptoKit
import Foundation

/// A text action offered in the ⌘K menu. `apply` returns nil when the action doesn't fit the input
/// (e.g. "Pretty-print JSON" on prose), so the menu only lists what will actually work.
public struct Transform: Identifiable {
    public enum Group: String, CaseIterable {
        case json = "JSON & Code"
        case text = "Text Cleanup"
        case web = "URLs & Encoding"
        case info = "Counts & Hashes"
    }

    public let id: String
    public let group: Group
    public let title: String
    public let keywords: String
    public let apply: (String) -> String?

    public init(_ id: String, _ group: Group, _ title: String, keywords: String = "", _ apply: @escaping (String) -> String?) {
        self.id = id
        self.group = group
        self.title = title
        self.keywords = keywords
        self.apply = apply
    }

    /// Transforms that produce a changed result for `input`, in menu order.
    public static func available(for input: String) -> [(Transform, String)] {
        all.compactMap { t in
            guard let out = t.apply(input), out != input else { return nil }
            return (t, out)
        }
    }

    public static let all: [Transform] = [
        // JSON & code
        Transform("json.pretty", .json, "Pretty-print JSON", keywords: "format indent") { json($0, [.prettyPrinted, .withoutEscapingSlashes]) },
        Transform("json.minify", .json, "Minify JSON", keywords: "compact") { json($0, [.withoutEscapingSlashes]) },
        Transform("json.sort", .json, "Sort JSON keys", keywords: "order") { json($0, [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]) },
        Transform("json.yaml", .json, "JSON → YAML", keywords: "convert") { s in parseJSON(s).map { yaml($0, indent: 0).trimmingCharacters(in: .newlines) } },
        Transform("str.escape", .json, "Escape as string literal", keywords: "quote json") { s in
            (try? JSONSerialization.data(withJSONObject: [s], options: [.withoutEscapingSlashes]))
                .flatMap { String(data: $0, encoding: .utf8) }.map { String($0.dropFirst(2).dropLast(2)) } // strip the ["…"] wrapper
        },
        Transform("str.unescape", .json, "Unescape string literal", keywords: "unquote") { s in
            let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
            guard t.contains("\\") || (t.hasPrefix("\"") && t.hasSuffix("\"")) else { return nil }
            let quoted = t.hasPrefix("\"") && t.hasSuffix("\"") && t.count >= 2 ? t : "\"\(t)\""
            return (try? JSONSerialization.jsonObject(with: Data("[\(quoted)]".utf8))).flatMap { ($0 as? [String])?.first }
        },
        Transform("sql.format", .json, "Format SQL", keywords: "query uppercase") { formatSQL($0) },

        // Text cleanup
        Transform("text.trim", .text, "Trim whitespace") { $0.trimmingCharacters(in: .whitespacesAndNewlines) },
        Transform("text.collapse", .text, "Collapse spaces", keywords: "whitespace") { s in
            s.split(separator: "\n", omittingEmptySubsequences: false)
                .map { $0.split(whereSeparator: { $0 == " " || $0 == "\t" }).joined(separator: " ") }.joined(separator: "\n")
        },
        Transform("text.join", .text, "Join lines", keywords: "single line") { s in
            s.contains("\n") ? s.split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }.joined(separator: " ") : nil
        },
        Transform("text.split", .text, "Split on commas into lines", keywords: "list") { s in
            s.contains(",") ? s.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.joined(separator: "\n") : nil
        },
        Transform("text.noblank", .text, "Remove empty lines") { s in
            s.split(separator: "\n", omittingEmptySubsequences: false).filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }.joined(separator: "\n")
        },
        Transform("text.sort", .text, "Sort lines", keywords: "alphabetical") { s in
            lines(s).map { $0.sorted { $0.localizedStandardCompare($1) == .orderedAscending }.joined(separator: "\n") }
        },
        Transform("text.unique", .text, "Unique lines", keywords: "dedupe duplicates") { s in
            lines(s).map { l in var seen = Set<String>(); return l.filter { seen.insert($0).inserted }.joined(separator: "\n") }
        },
        Transform("case.upper", .text, "UPPERCASE") { $0.uppercased() },
        Transform("case.lower", .text, "lowercase") { $0.lowercased() },
        Transform("case.title", .text, "Title Case") { $0.capitalized },
        Transform("case.camel", .text, "camelCase") { s in
            let w = words(s); guard w.count > 1 else { return nil }
            return w[0].lowercased() + w.dropFirst().map { $0.prefix(1).uppercased() + $0.dropFirst().lowercased() }.joined()
        },
        Transform("case.snake", .text, "snake_case") { s in
            let w = words(s); return w.count > 1 ? w.map { $0.lowercased() }.joined(separator: "_") : nil
        },

        // URLs & encoding
        Transform("url.clean", .web, "Strip tracking parameters", keywords: "utm fbclid gclid") { stripTracking($0) },
        Transform("url.encode", .web, "URL-encode", keywords: "percent") { $0.addingPercentEncoding(withAllowedCharacters: .urlQueryValueAllowed) },
        Transform("url.decode", .web, "URL-decode", keywords: "percent") { s in s.contains("%") || s.contains("+") ? s.replacingOccurrences(of: "+", with: " ").removingPercentEncoding : nil },
        Transform("b64.encode", .web, "Base64 encode") { Data($0.utf8).base64EncodedString() },
        Transform("b64.decode", .web, "Base64 decode") { s in
            let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
            var padded = t.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
            while padded.count % 4 != 0 { padded += "=" }
            guard t.count >= 4, let d = Data(base64Encoded: padded), let out = String(data: d, encoding: .utf8),
                  out.unicodeScalars.allSatisfy({ !CharacterSet.controlCharacters.contains($0) || "\n\r\t".unicodeScalars.contains($0) }) else { return nil }
            return out
        },
        Transform("extract.urls", .web, "Extract URLs", keywords: "links") { extract($0, .link) },
        Transform("extract.emails", .web, "Extract emails") { extract($0, .link, emails: true) },

        // Counts & hashes
        Transform("info.count", .info, "Count words, lines, characters", keywords: "length stats") { s in
            let w = s.split(whereSeparator: { $0.isWhitespace }).count
            let l = s.isEmpty ? 0 : s.split(separator: "\n", omittingEmptySubsequences: false).count
            return "\(w) words · \(l) lines · \(s.count) characters"
        },
        Transform("hash.md5", .info, "MD5") { Insecure.MD5.hash(data: Data($0.utf8)).map { String(format: "%02x", $0) }.joined() },
        Transform("hash.sha256", .info, "SHA-256") { SHA256.hash(data: Data($0.utf8)).map { String(format: "%02x", $0) }.joined() },
        Transform("gen.uuid", .info, "New UUID", keywords: "random id") { _ in UUID().uuidString.lowercased() },
        Transform("time.convert", .info, "Epoch ↔ date (IST)", keywords: "timestamp unix") { epochOrDate($0) },
    ]

    // MARK: Helpers

    static let ist = TimeZone(identifier: "Asia/Kolkata")!

    private static func parseJSON(_ s: String) -> Any? {
        let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        guard t.hasPrefix("{") || t.hasPrefix("[") else { return nil }
        return try? JSONSerialization.jsonObject(with: Data(t.utf8), options: [.fragmentsAllowed])
    }

    private static func json(_ s: String, _ options: JSONSerialization.WritingOptions) -> String? {
        guard let obj = parseJSON(s), let d = try? JSONSerialization.data(withJSONObject: obj, options: options) else { return nil }
        return String(data: d, encoding: .utf8)
    }

    private static func yaml(_ v: Any, indent: Int) -> String {
        let pad = String(repeating: "  ", count: indent)
        switch v {
        case let dict as [String: Any]:
            if dict.isEmpty { return "{}\n" }
            return dict.keys.sorted().map { key in
                let value = dict[key]!
                if isScalar(value) { return "\(pad)\(yamlKey(key)): \(scalar(value))\n" }
                return "\(pad)\(yamlKey(key)):\n" + yaml(value, indent: indent + 1)
            }.joined()
        case let arr as [Any]:
            if arr.isEmpty { return "\(pad)[]\n" }
            return arr.map { value in
                if isScalar(value) { return "\(pad)- \(scalar(value))\n" }
                let nested = yaml(value, indent: indent + 1)
                return "\(pad)-\n" + nested
            }.joined()
        default:
            return "\(pad)\(scalar(v))\n"
        }
    }

    private static func isScalar(_ v: Any) -> Bool { !(v is [String: Any]) && !(v is [Any]) }

    private static func yamlKey(_ k: String) -> String {
        k.allSatisfy { $0.isLetter || $0.isNumber || $0 == "_" || $0 == "-" } && !k.isEmpty ? k : "\"\(k)\""
    }

    private static func scalar(_ v: Any) -> String {
        switch v {
        case is NSNull: return "null"
        case let n as NSNumber:
            return CFGetTypeID(n) == CFBooleanGetTypeID() ? (n.boolValue ? "true" : "false") : "\(n)"
        case let s as String:
            let needsQuotes = s.isEmpty || s.contains(":") || s.contains("#") || s.hasPrefix(" ") || s.hasSuffix(" ")
                || ["true", "false", "null", "yes", "no"].contains(s.lowercased()) || Double(s) != nil
            return needsQuotes ? "\"\(s.replacingOccurrences(of: "\"", with: "\\\""))\"" : s
        default: return "\(v)"
        }
    }

    private static let sqlKeywords = ["select", "from", "where", "and", "or", "join", "left", "right", "inner", "outer",
                                      "on", "group", "by", "order", "having", "limit", "offset", "insert", "into", "values",
                                      "update", "set", "delete", "as", "in", "not", "null", "is", "like", "between",
                                      "distinct", "count", "sum", "avg", "min", "max", "case", "when", "then", "else", "end",
                                      "union", "all", "with", "desc", "asc", "returning"]
    private static let sqlBreaks: Set<String> = ["FROM", "WHERE", "JOIN", "LEFT", "RIGHT", "INNER", "GROUP", "ORDER",
                                                 "HAVING", "LIMIT", "UNION", "VALUES", "SET", "RETURNING"]

    /// Uppercases keywords and starts major clauses on new lines. Leaves string literals alone.
    static func formatSQL(_ s: String) -> String? {
        let lower = s.lowercased()
        guard lower.contains("select") || lower.contains("update") || lower.contains("insert") || lower.contains("delete") else { return nil }
        var out = ""
        var inString = false
        var word = ""
        func flush() {
            guard !word.isEmpty else { return }
            let up = word.uppercased()
            let isKeyword = sqlKeywords.contains(word.lowercased())
            if isKeyword, sqlBreaks.contains(up), !out.isEmpty {
                while out.hasSuffix(" ") { out.removeLast() }
                out += "\n"
            }
            out += isKeyword ? up : word
            word = ""
        }
        for ch in s.replacingOccurrences(of: "\n", with: " ") {
            if ch == "'" { flush(); inString.toggle(); out.append(ch); continue }
            if inString { out.append(ch); continue }
            if ch.isLetter || ch.isNumber || ch == "_" { word.append(ch) } else { flush(); if !(ch == " " && out.hasSuffix(" ")) { out.append(ch) } }
        }
        flush()
        // "LEFT\nJOIN" → "LEFT JOIN": keep compound clauses on one line.
        for (a, b) in [("LEFT", "JOIN"), ("RIGHT", "JOIN"), ("INNER", "JOIN"), ("GROUP", "BY"), ("ORDER", "BY")] {
            out = out.replacingOccurrences(of: "\(a)\n\(b)", with: "\(a) \(b)")
        }
        return out.trimmingCharacters(in: .whitespaces)
    }

    private static func lines(_ s: String) -> [String]? {
        let l = s.split(separator: "\n").map(String.init)
        return l.count > 1 ? l : nil
    }

    private static func words(_ s: String) -> [String] {
        s.split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init)
    }

    private static let trackingParams: Set<String> = ["fbclid", "gclid", "dclid", "msclkid", "mc_cid", "mc_eid", "igshid",
                                                      "yclid", "_hsenc", "_hsmi", "ref_src", "si", "spm", "trk", "vero_id"]

    static func stripTracking(_ s: String) -> String? {
        let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        guard var comps = URLComponents(string: t), comps.scheme?.hasPrefix("http") == true, let items = comps.queryItems else { return nil }
        let kept = items.filter { !$0.name.lowercased().hasPrefix("utm_") && !trackingParams.contains($0.name.lowercased()) }
        guard kept.count != items.count else { return nil }
        comps.queryItems = kept.isEmpty ? nil : kept
        return comps.string
    }

    private static func extract(_ s: String, _ type: NSTextCheckingResult.CheckingType, emails: Bool = false) -> String? {
        guard let detector = try? NSDataDetector(types: type.rawValue) else { return nil }
        let found = detector.matches(in: s, range: NSRange(s.startIndex..., in: s)).compactMap { $0.url }
            .filter { emails ? $0.scheme == "mailto" : $0.scheme != "mailto" }
            .map { emails ? $0.absoluteString.replacingOccurrences(of: "mailto:", with: "") : $0.absoluteString }
        var seen = Set<String>()
        let unique = found.filter { seen.insert($0).inserted }
        return unique.isEmpty ? nil : unique.joined(separator: "\n")
    }

    /// Epoch seconds/ms → "2026-10-29 19:37:09 IST"; an ISO or "yyyy-MM-dd HH:mm[:ss]" date → epoch seconds.
    static func epochOrDate(_ s: String) -> String? {
        let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        let display = DateFormatter()
        display.locale = Locale(identifier: "en_US_POSIX")
        display.timeZone = ist
        display.dateFormat = "yyyy-MM-dd HH:mm:ss 'IST'"
        if (9...13).contains(t.count), t.allSatisfy(\.isASCIIDigit), let v = Double(t) {
            let seconds = t.count >= 12 ? v / 1000 : v
            return display.string(from: Date(timeIntervalSince1970: seconds))
        }
        let iso = ISO8601DateFormatter()
        if let d = iso.date(from: t) { return String(Int(d.timeIntervalSince1970)) }
        let parse = DateFormatter()
        parse.locale = Locale(identifier: "en_US_POSIX")
        parse.timeZone = ist
        for f in ["yyyy-MM-dd HH:mm:ss", "yyyy-MM-dd HH:mm", "yyyy-MM-dd", "dd/MM/yyyy HH:mm", "dd/MM/yyyy"] {
            parse.dateFormat = f
            if let d = parse.date(from: t) { return String(Int(d.timeIntervalSince1970)) }
        }
        return nil
    }
}

private extension CharacterSet {
    static let urlQueryValueAllowed: CharacterSet = {
        var c = CharacterSet.urlQueryAllowed
        c.remove(charactersIn: "&=+?/#")
        return c
    }()
}

/// Placeholders in pinned snippets, filled in at paste time.
public enum Snippet {
    public static let placeholders = ["{date}", "{time}", "{datetime}", "{clipboard}", "{cursor}", "{uuid}"]

    public static func hasPlaceholders(_ s: String) -> Bool { placeholders.contains { s.contains($0) } }

    /// Returns the expanded text and, if `{cursor}` was present, how many characters follow it
    /// (the paster moves the caret left by that much).
    public static func expand(_ s: String, clipboard: String?, now: Date = Date()) -> (text: String, charsAfterCursor: Int?) {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = Transform.ist
        func fmt(_ p: String) -> String { f.dateFormat = p; return f.string(from: now) }
        var out = s
            .replacingOccurrences(of: "{datetime}", with: fmt("yyyy-MM-dd'T'HH:mm:ssxxx"))
            .replacingOccurrences(of: "{date}", with: fmt("yyyy-MM-dd"))
            .replacingOccurrences(of: "{time}", with: fmt("HH:mm"))
            .replacingOccurrences(of: "{clipboard}", with: clipboard ?? "")
        while let r = out.range(of: "{uuid}") { out.replaceSubrange(r, with: UUID().uuidString.lowercased()) }
        guard let cursor = out.range(of: "{cursor}") else { return (out, nil) }
        let after = out[cursor.upperBound...].replacingOccurrences(of: "{cursor}", with: "")
        out = String(out[..<cursor.lowerBound]) + after
        return (out, after.count)
    }
}
