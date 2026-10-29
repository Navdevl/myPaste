import Foundation

/// Context-aware suggestions shown as a chip on the card and as "Suggested" in ⌘K.
public struct SmartChip: Equatable {
    public enum Action: Equatable {
        /// Open in the browser (Jira issue, GitHub PR).
        case open(URL)
        /// Produce text the user can paste or save (decoded JWT, converted timestamp).
        case text(String)
    }

    public let symbol: String
    /// Short label for the card chip.
    public let label: String
    /// Menu title in ⌘K.
    public let title: String
    public let action: Action
}

public enum SmartDetector {
    /// Uppercase-dash-number words that are not issue keys.
    private static let notJiraPrefixes: Set<String> = [
        "UTF", "SHA", "ISO", "RFC", "COVID", "MD", "AES", "RSA", "HTTP", "TLS", "SSL", "CVE", "PCI", "IPV", "MP", "H", "X",
        "GPT", "ES", "ECMA", "WCAG", "AWS", "GCP", "EC", "T", "V", "IP", "PORT", "Q", "FY", "COVID", "PEP", "BIP", "EIP",
    ]
    private static let jiraRegex = try! NSRegularExpression(pattern: #"(?<![A-Za-z0-9-])([A-Z][A-Z0-9]{1,9})-(\d{1,6})(?![A-Za-z0-9-])"#)
    private static let uuidRegex = try! NSRegularExpression(pattern: #"^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-([1-8])[0-9a-fA-F]{3}-[89abAB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}$"#)
    private static let githubRegex = try! NSRegularExpression(pattern: #"https?://github\.com/([\w.-]+)/([\w.-]+)/(pull|issues)/(\d+)"#)
    private static let jwtRegex = try! NSRegularExpression(pattern: #"^eyJ[A-Za-z0-9_\-]+\.eyJ[A-Za-z0-9_\-]+\.[A-Za-z0-9_\-]*$"#)

    public static func chips(for raw: String, jiraBase: URL?, now: Date = Date()) -> [SmartChip] {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, text.count < 100_000 else { return [] }
        var out: [SmartChip] = []
        let whole = NSRange(text.startIndex..., in: text)

        if jwtRegex.firstMatch(in: text, range: whole) != nil, let jwt = decodeJWT(text) {
            out.append(SmartChip(symbol: "key.horizontal", label: jwt.statusLabel(now: now), title: "Decode JWT", action: .text(jwt.pretty)))
        }

        if let m = uuidRegex.firstMatch(in: text, range: whole), let v = Range(m.range(at: 1), in: text) {
            out.append(SmartChip(symbol: "number", label: "UUID v\(text[v])", title: "UUID without dashes",
                                 action: .text(text.replacingOccurrences(of: "-", with: "").lowercased())))
        }

        if let converted = Transform.epochOrDate(text), text.allSatisfy(\.isASCIIDigit) {
            out.append(SmartChip(symbol: "clock", label: shortIST(text) ?? converted, title: "Timestamp → \(converted)", action: .text(converted)))
        }

        for m in githubRegex.matches(in: text, range: whole).prefix(3) {
            guard let r = Range(m.range, in: text), let url = URL(string: String(text[r])),
                  let owner = Range(m.range(at: 1), in: text), let repo = Range(m.range(at: 2), in: text),
                  let kind = Range(m.range(at: 3), in: text), let n = Range(m.range(at: 4), in: text) else { continue }
            let ref = "\(text[owner])/\(text[repo])#\(text[n])"
            out.append(SmartChip(symbol: text[kind] == "pull" ? "arrow.triangle.pull" : "smallcircle.filled.circle",
                                 label: ref, title: "Open \(text[kind] == "pull" ? "PR" : "issue") \(ref)", action: .open(url)))
        }

        if let base = jiraBase {
            var seen = Set<String>()
            for key in jiraKeys(in: text) where seen.insert(key).inserted && seen.count <= 3 {
                out.append(SmartChip(symbol: "ticket", label: key, title: "Open \(key) in Jira",
                                     action: .open(base.appendingPathComponent("browse").appendingPathComponent(key))))
            }
        }

        let t = text.first
        if t == "{" || t == "[", !text.contains("\n"), let pretty = Transform.all.first(where: { $0.id == "json.pretty" })?.apply(text) {
            out.append(SmartChip(symbol: "curlybraces", label: "Pretty JSON", title: "Pretty-print JSON", action: .text(pretty)))
        }
        if Classifier.isCode(text), text.lowercased().contains("select") || text.lowercased().contains("update "),
           let sql = Transform.formatSQL(text), sql != text {
            out.append(SmartChip(symbol: "tablecells", label: "Format SQL", title: "Format SQL", action: .text(sql)))
        }
        if Classifier.isColor(text), let rgba = Classifier.rgba(from: text) {
            let converted = text.hasPrefix("#")
                ? "rgb(\(Int(rgba.r * 255)), \(Int(rgba.g * 255)), \(Int(rgba.b * 255)))"
                : String(format: "#%02X%02X%02X", Int(rgba.r * 255), Int(rgba.g * 255), Int(rgba.b * 255))
            out.append(SmartChip(symbol: "paintpalette", label: converted, title: "Convert to \(converted)", action: .text(converted)))
        }
        return out
    }

    public static func jiraKeys(in text: String) -> [String] {
        jiraRegex.matches(in: text, range: NSRange(text.startIndex..., in: text)).compactMap { m in
            guard let p = Range(m.range(at: 1), in: text), let r = Range(m.range, in: text) else { return nil }
            let prefix = String(text[p])
            guard !notJiraPrefixes.contains(prefix), prefix.contains(where: \.isLetter) else { return nil }
            return String(text[r])
        }
    }

    private static func shortIST(_ digits: String) -> String? {
        guard let v = Double(digits) else { return nil }
        let date = Date(timeIntervalSince1970: digits.count >= 12 ? v / 1000 : v)
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_IN")
        f.timeZone = Transform.ist
        f.dateFormat = "d MMM yyyy, HH:mm 'IST'"
        return f.string(from: date)
    }

    // MARK: JWT

    public struct JWT {
        public let header: [String: Any]
        public let payload: [String: Any]

        public var expires: Date? { (payload["exp"] as? NSNumber).map { Date(timeIntervalSince1970: $0.doubleValue) } }
        public var issued: Date? { (payload["iat"] as? NSNumber).map { Date(timeIntervalSince1970: $0.doubleValue) } }

        public func statusLabel(now: Date) -> String {
            guard let exp = expires else { return "JWT" }
            let f = RelativeDateTimeFormatter()
            f.unitsStyle = .short
            let rel = f.localizedString(for: exp, relativeTo: now)
            return exp < now ? "JWT · expired \(rel)" : "JWT · expires \(rel)"
        }

        /// Header and claims as JSON, with exp/iat/nbf annotated in IST. Signature is not verified.
        public var pretty: String {
            func json(_ o: [String: Any]) -> String {
                (try? JSONSerialization.data(withJSONObject: o, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]))
                    .flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
            }
            var notes: [String] = []
            for claim in ["iat", "nbf", "exp"] {
                if let n = payload[claim] as? NSNumber, let s = Transform.epochOrDate(String(n.int64Value)) { notes.append("\(claim): \(s)") }
            }
            return "// header\n\(json(header))\n\n// payload\n\(json(payload))"
                + (notes.isEmpty ? "" : "\n\n// " + notes.joined(separator: "\n// "))
                + "\n\n// signature not verified"
        }
    }

    public static func decodeJWT(_ token: String) -> JWT? {
        let parts = token.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count >= 2, let h = base64URLJSON(parts[0]), let p = base64URLJSON(parts[1]) else { return nil }
        return JWT(header: h, payload: p)
    }

    private static func base64URLJSON(_ s: Substring) -> [String: Any]? {
        var b = s.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        while b.count % 4 != 0 { b += "=" }
        guard let d = Data(base64Encoded: b) else { return nil }
        return (try? JSONSerialization.jsonObject(with: d)) as? [String: Any]
    }
}
