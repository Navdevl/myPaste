import Foundation

/// Pasteboard facts the classifier needs, without touching AppKit.
public struct CaptureFacts {
    public var string: String?
    public var hasRTF: Bool
    public var hasHTML: Bool
    public var hasImage: Bool
    public var fileURLs: [URL]
    public var hasURLType: Bool

    public init(string: String?, hasRTF: Bool = false, hasHTML: Bool = false,
                hasImage: Bool = false, fileURLs: [URL] = [], hasURLType: Bool = false) {
        self.string = string
        self.hasRTF = hasRTF
        self.hasHTML = hasHTML
        self.hasImage = hasImage
        self.fileURLs = fileURLs
        self.hasURLType = hasURLType
    }
}

public enum Classifier {
    /// Priority: files > image > single URL > color > email > phone > code > rich text > text.
    public static func kind(for facts: CaptureFacts) -> ContentKind {
        if !facts.fileURLs.isEmpty { return .file }
        let text = facts.string?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if facts.hasImage && text.isEmpty { return .image }
        if text.isEmpty { return facts.hasImage ? .image : .text }
        if isLink(text) { return .link }
        if isColor(text) { return .color }
        if isEmail(text) { return .email }
        if isPhone(text) { return .phone }
        if isCode(text) { return .code }
        if facts.hasRTF || facts.hasHTML { return .richText }
        return .text
    }

    public static func isLink(_ s: String) -> Bool {
        guard !s.contains(where: { $0.isWhitespace }), s.count < 4096 else { return false }
        guard let url = URL(string: s), let scheme = url.scheme?.lowercased() else { return false }
        return ["http", "https", "ftp", "mailto"].contains(scheme) && (url.host != nil || scheme == "mailto")
    }

    private static let colorPatterns: [NSRegularExpression] = [
        #"^#(?:[0-9a-fA-F]{3}|[0-9a-fA-F]{4}|[0-9a-fA-F]{6}|[0-9a-fA-F]{8})$"#,
        #"^rgba?\(\s*\d{1,3}%?\s*[, ]\s*\d{1,3}%?\s*[, ]\s*\d{1,3}%?\s*(?:[,/]\s*(?:0|1|0?\.\d+|\d{1,3}%)\s*)?\)$"#,
        #"^hsla?\(\s*\d{1,3}(?:deg)?\s*[, ]\s*\d{1,3}%\s*[, ]\s*\d{1,3}%\s*(?:[,/]\s*(?:0|1|0?\.\d+|\d{1,3}%)\s*)?\)$"#,
    ].map { try! NSRegularExpression(pattern: $0, options: [.caseInsensitive]) }

    public static func isColor(_ s: String) -> Bool {
        colorPatterns.contains { $0.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)) != nil }
    }

    /// Parses #RGB, #RGBA, #RRGGBB, #RRGGBBAA and rgb()/rgba() into 0...1 components.
    public static func rgba(from s: String) -> (r: Double, g: Double, b: Double, a: Double)? {
        let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.hasPrefix("#") {
            var hex = String(t.dropFirst())
            if hex.count == 3 || hex.count == 4 { hex = hex.map { "\($0)\($0)" }.joined() }
            guard hex.count == 6 || hex.count == 8, let v = UInt64(hex, radix: 16) else { return nil }
            if hex.count == 6 {
                return (Double((v >> 16) & 0xff) / 255, Double((v >> 8) & 0xff) / 255, Double(v & 0xff) / 255, 1)
            }
            return (Double((v >> 24) & 0xff) / 255, Double((v >> 16) & 0xff) / 255,
                    Double((v >> 8) & 0xff) / 255, Double(v & 0xff) / 255)
        }
        if t.lowercased().hasPrefix("rgb") {
            let nums = t.components(separatedBy: CharacterSet(charactersIn: "0123456789.").inverted)
                .compactMap(Double.init)
            guard nums.count >= 3 else { return nil }
            return (min(nums[0], 255) / 255, min(nums[1], 255) / 255, min(nums[2], 255) / 255,
                    nums.count > 3 ? min(nums[3], 1) : 1)
        }
        return nil
    }

    private static let emailRegex = try! NSRegularExpression(
        pattern: #"^[A-Z0-9._%+\-]+@[A-Z0-9.\-]+\.[A-Z]{2,}$"#, options: [.caseInsensitive])

    public static func isEmail(_ s: String) -> Bool {
        emailRegex.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)) != nil
    }

    private static let phoneRegex = try! NSRegularExpression(pattern: #"^\+?[0-9()\-.\s]{7,20}$"#)

    /// Needs a separator or a leading +, so bare digit runs stay text (or OTPs).
    public static func isPhone(_ s: String) -> Bool {
        guard phoneRegex.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)) != nil else { return false }
        let digits = s.filter(\.isNumber).count
        guard (7...15).contains(digits) else { return false }
        return s.hasPrefix("+") || s.contains(where: { " -().".contains($0) })
    }

    private static let codeKeywords = [
        "func ", "def ", "class ", "import ", "return ", "const ", "let ", "var ", "function ",
        "public ", "private ", "struct ", "#include", "SELECT ", "FROM ", "WHERE ", "=> ", "->",
        "end\n", "elif ", "lambda", "async ", "await ", "require(", "module ", "package ",
    ]

    /// Scores structural signals; one-line prose with a semicolon shouldn't qualify.
    public static func isCode(_ s: String) -> Bool {
        // JSON objects/arrays are code even on one line.
        if let f = s.first, f == "{" || f == "[", s.count > 2,
           (try? JSONSerialization.jsonObject(with: Data(s.utf8))) != nil { return true }
        var score = 0
        let lines = s.split(separator: "\n", omittingEmptySubsequences: false)
        if lines.count > 1 { score += 1 }
        let indented = lines.filter { $0.hasPrefix("  ") || $0.hasPrefix("\t") }.count
        if indented >= 1 && lines.count > 1 { score += 1 }
        let endings = lines.filter {
            let t = $0.trimmingCharacters(in: .whitespaces)
            return t.hasSuffix(";") || t.hasSuffix("{") || t.hasSuffix("}") || t.hasSuffix(":") || t.hasSuffix(")")
        }.count
        if endings >= max(1, lines.count / 3) { score += 1 }
        if codeKeywords.contains(where: { s.contains($0) }) { score += 1 }
        let symbols = s.filter { "{}[]();=<>$&|".contains($0) }.count
        if Double(symbols) / Double(max(s.count, 1)) > 0.04 { score += 1 }
        if s.contains("()") || s.contains("::") || s.contains("!=") || s.contains("==") { score += 1 }
        return lines.count > 1 ? score >= 4 : score >= 3 && s.count > 12
    }
}
