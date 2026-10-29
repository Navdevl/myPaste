import Foundation

/// Heuristics for clipboard text that looks like a secret. False positives only cost a blur and
/// an early expiry, so this leans towards flagging.
public enum SensitiveDetector {
    public enum Reason: String, Sendable {
        case otp, apiKey, card, jwt, privateKey, password
        // Indian identifiers (KYC / banking): always masked in previews, not just blurred.
        case pan, aadhaar, ifsc, upi, account

        /// Reasons whose previews show a masked value (last 4 visible) rather than the raw text.
        public var isMasked: Bool {
            switch self {
            case .pan, .aadhaar, .ifsc, .upi, .account, .card: return true
            default: return false
            }
        }

        /// Indian KYC/banking identifiers: their shape (digits, @) says nothing about the content type.
        public var isIdentifier: Bool {
            switch self {
            case .pan, .aadhaar, .ifsc, .upi, .account: return true
            default: return false
            }
        }

        public var label: String {
            switch self {
            case .otp: return "One-time code"
            case .apiKey: return "API key"
            case .card: return "Card number"
            case .jwt: return "JWT"
            case .privateKey: return "Private key"
            case .password: return "Password-like"
            case .pan: return "PAN"
            case .aadhaar: return "Aadhaar"
            case .ifsc: return "IFSC"
            case .upi: return "UPI ID"
            case .account: return "Account number"
            }
        }
    }

    private static let panRegex = try! NSRegularExpression(pattern: #"^[A-Z]{3}[ABCFGHJLPT][A-Z][0-9]{4}[A-Z]$"#, options: [.caseInsensitive])
    private static let ifscRegex = try! NSRegularExpression(pattern: #"^[A-Z]{4}0[A-Z0-9]{6}$"#, options: [.caseInsensitive])
    /// handle@psp, with no dot in the PSP part (that would make it an email).
    private static let upiRegex = try! NSRegularExpression(pattern: #"^[a-zA-Z0-9.\-_]{2,64}@[a-zA-Z]{2,32}$"#)

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
        if matches(panRegex, s) { return .pan }
        if isAadhaar(s) { return .aadhaar }
        if matches(ifscRegex, s) { return .ifsc }
        if matches(upiRegex, s) { return .upi }
        if isOTP(s) { return .otp }
        if isCardNumber(s) { return .card }
        if isAccountNumber(s) { return .account }
        if looksLikeGenericSecret(s) { return .apiKey }
        if looksLikePassword(s) { return .password }
        return nil
    }

    private static func matches(_ r: NSRegularExpression, _ s: String) -> Bool {
        r.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)) != nil
    }

    /// 12 digits (optionally 4-4-4), first digit 2–9, valid Verhoeff checksum.
    public static func isAadhaar(_ s: String) -> Bool {
        let digits = s.filter { $0 != " " && $0 != "-" }
        guard digits.count == 12, digits.allSatisfy(\.isASCIIDigit), let first = digits.first, first >= "2" else { return false }
        return verhoeff(digits)
    }

    static func verhoeff(_ digits: String) -> Bool {
        let d: [[Int]] = [
            [0, 1, 2, 3, 4, 5, 6, 7, 8, 9], [1, 2, 3, 4, 0, 6, 7, 8, 9, 5], [2, 3, 4, 0, 1, 7, 8, 9, 5, 6],
            [3, 4, 0, 1, 2, 8, 9, 5, 6, 7], [4, 0, 1, 2, 3, 9, 5, 6, 7, 8], [5, 9, 8, 7, 6, 0, 4, 3, 2, 1],
            [6, 5, 9, 8, 7, 1, 0, 4, 3, 2], [7, 6, 5, 9, 8, 2, 1, 0, 4, 3], [8, 7, 6, 5, 9, 3, 2, 1, 0, 4],
            [9, 8, 7, 6, 5, 4, 3, 2, 1, 0],
        ]
        let p: [[Int]] = [
            [0, 1, 2, 3, 4, 5, 6, 7, 8, 9], [1, 5, 7, 6, 2, 8, 3, 0, 9, 4], [5, 8, 0, 3, 7, 9, 6, 1, 4, 2],
            [8, 9, 1, 6, 0, 4, 3, 5, 2, 7], [9, 4, 5, 3, 1, 2, 6, 8, 7, 0], [4, 2, 8, 6, 5, 7, 3, 9, 0, 1],
            [2, 7, 9, 3, 8, 0, 6, 4, 1, 5], [7, 0, 4, 6, 9, 1, 3, 2, 5, 8],
        ]
        var c = 0
        for (i, ch) in digits.reversed().enumerated() {
            guard let n = ch.wholeNumberValue else { return false }
            c = d[c][p[i % 8][n]]
        }
        return c == 0
    }

    /// 9–18 bare digits. Excludes 10-digit Indian mobiles (6–9 prefix) and epoch timestamps (s / ms).
    public static func isAccountNumber(_ s: String) -> Bool {
        guard (9...18).contains(s.count), s.allSatisfy(\.isASCIIDigit) else { return false }
        if s.count == 10, let f = s.first, "6789".contains(f) { return false }
        if s.count == 10 || s.count == 13, let v = Double(s) {
            let seconds = s.count == 13 ? v / 1000 : v
            if (978_307_200...4_102_444_800).contains(seconds) { return false } // 2001–2100
        }
        return true
    }

    /// Preview-safe rendering for masked reasons; nil means show the text as-is (blur still applies).
    public static func masked(_ text: String, reason: Reason) -> String? {
        let s = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let digits = s.filter(\.isASCIIDigit)
        switch reason {
        case .pan: return "XXXXX" + s.dropFirst(5).prefix(4) + s.suffix(1)
        case .aadhaar: return "XXXX XXXX " + digits.suffix(4)
        case .card: return "XXXX-XXXX-XXXX-" + digits.suffix(4)
        case .account: return "••••" + digits.suffix(4)
        case .ifsc: return s.prefix(5) + "••••••"
        case .upi:
            guard let at = s.firstIndex(of: "@") else { return "•••" }
            return String(s[..<at].prefix(1)) + "•••" + s[at...]
        default: return nil
        }
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
