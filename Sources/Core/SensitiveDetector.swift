import Foundation

/// Heuristics for clipboard text that looks like a secret. False positives only cost a blur and
/// an early expiry, so this leans towards flagging.
public enum SensitiveDetector {
    public enum Reason: String, Sendable {
        case otp, apiKey, card, jwt, privateKey, password
    }

    private static let keyPatterns: [NSRegularExpression] = [
        #"^sk-[A-Za-z0-9_\-]{16,}$"#,                    // OpenAI / Anthropic / Stripe secret
        #"^(?:sk|rk|pk)_(?:live|test)_[A-Za-z0-9]{16,}$"#, // Stripe
        #"^gh[pousr]_[A-Za-z0-9]{30,}$"#,                 // GitHub
        #"^github_pat_[A-Za-z0-9_]{40,}$"#,
        #"^(?:AKIA|ASIA)[0-9A-Z]{16}$"#,                  // AWS access key id
        #"^xox[abposr]-[A-Za-z0-9\-]{10,}$"#,             // Slack
        #"^AIza[0-9A-Za-z_\-]{35}$"#,                     // Google API key
        #"^glpat-[A-Za-z0-9_\-]{20,}$"#,                  // GitLab
    ].map { try! NSRegularExpression(pattern: $0) }

    private static let jwtRegex = try! NSRegularExpression(
        pattern: #"^eyJ[A-Za-z0-9_\-]+\.eyJ[A-Za-z0-9_\-]+\.[A-Za-z0-9_\-]*$"#)

    public static func reason(for text: String) -> Reason? {
        let s = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !s.isEmpty, s.count <= 8192 else { return nil }
        if s.contains("-----BEGIN") && s.contains("PRIVATE KEY") { return .privateKey }
        guard !s.contains("\n") else { return nil }
        let range = NSRange(s.startIndex..., in: s)
        if jwtRegex.firstMatch(in: s, range: range) != nil { return .jwt }
        if keyPatterns.contains(where: { $0.firstMatch(in: s, range: range) != nil }) { return .apiKey }
        if isOTP(s) { return .otp }
        if isCardNumber(s) { return .card }
        if looksLikeGenericSecret(s) { return .apiKey }
        if looksLikePassword(s) { return .password }
        return nil
    }

    /// 4–8 bare digits, optionally split in the middle ("123 456" / "123-456").
    public static func isOTP(_ s: String) -> Bool {
        let compact = s.replacingOccurrences(of: " ", with: "").replacingOccurrences(of: "-", with: "")
        guard (4...8).contains(compact.count), compact.allSatisfy(\.isASCIIDigit) else { return false }
        // Years like 2024 are common copies; don't flag 19xx/20xx four-digit numbers.
        if compact.count == 4, let n = Int(compact), (1900...2099).contains(n) { return false }
        return compact.count == s.count || s.filter { $0 == " " || $0 == "-" }.count == 1
    }

    public static func isCardNumber(_ s: String) -> Bool {
        let digits = s.filter { $0 != " " && $0 != "-" }
        guard (13...19).contains(digits.count), digits.allSatisfy(\.isASCIIDigit) else { return false }
        return luhn(digits)
    }

    public static func luhn(_ digits: String) -> Bool {
        var sum = 0
        for (i, ch) in digits.reversed().enumerated() {
            guard var d = ch.wholeNumberValue else { return false }
            if i % 2 == 1 { d *= 2; if d > 9 { d -= 9 } }
            sum += d
        }
        return sum % 10 == 0
    }

    /// Long, unbroken, high-entropy tokens (hex secrets, base64 keys).
    static func looksLikeGenericSecret(_ s: String) -> Bool {
        guard s.count >= 24, s.count <= 256, !s.contains(" "), !s.contains("/"), !s.contains(".") else { return false }
        guard s.allSatisfy({ $0.isLetter || $0.isNumber || "_-+=".contains($0) }) else { return false }
        let hasDigit = s.contains(where: \.isNumber)
        let hasUpper = s.contains(where: \.isUppercase)
        let hasLower = s.contains(where: \.isLowercase)
        guard hasDigit && (hasUpper || hasLower) else { return false }
        return entropy(s) >= 3.5
    }

    /// 8–64 chars, no spaces, at least three of lower/upper/digit/symbol. Not a URL, path or email.
    static func looksLikePassword(_ s: String) -> Bool {
        guard (8...64).contains(s.count), !s.contains(" ") else { return false }
        if s.contains("://") || s.hasPrefix("/") || s.hasPrefix("~") || s.contains("@") && s.contains(".") { return false }
        if s.contains("_") && s.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "_" }) { return false } // snake_case ident
        let classes = [
            s.contains(where: \.isLowercase),
            s.contains(where: \.isUppercase),
            s.contains(where: \.isNumber),
            s.contains(where: { !$0.isLetter && !$0.isNumber }),
        ].filter { $0 }.count
        return classes >= 3 && s.contains(where: { !$0.isLetter && !$0.isNumber }) && entropy(s) >= 2.8
    }

    static func entropy(_ s: String) -> Double {
        var counts: [Character: Int] = [:]
        for c in s { counts[c, default: 0] += 1 }
        let n = Double(s.count)
        return counts.values.reduce(0) { acc, c in
            let p = Double(c) / n
            return acc - p * log2(p)
        }
    }
}

extension Character {
    var isASCIIDigit: Bool { ("0"..."9").contains(self) }
}
