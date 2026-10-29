import Foundation

/// Language-agnostic highlighter for Quick Look: comments, strings, numbers, keywords and JSON keys.
/// Regex-based and deliberately forgiving: good enough for snippets, not a parser.
public enum SyntaxHighlighter {
    public enum Kind: Equatable { case comment, string, number, keyword, key }

    public struct Token: Equatable {
        public let range: NSRange
        public let kind: Kind
    }

    private static let keywords: Set<String> = [
        // Swift / JS / TS / Go / Rust / Java / C
        "func", "let", "var", "const", "if", "else", "for", "while", "return", "import", "class", "struct", "enum",
        "protocol", "extension", "guard", "switch", "case", "default", "break", "continue", "in", "true", "false",
        "nil", "null", "undefined", "new", "this", "self", "super", "public", "private", "static", "async", "await",
        "throw", "throws", "try", "catch", "function", "export", "interface", "type", "package", "fn", "impl",
        "pub", "mut", "match", "use", "void", "int", "string", "bool",
        // Python / Ruby
        "def", "end", "elif", "lambda", "None", "True", "False", "and", "or", "not", "is", "pass", "yield", "with",
        "module", "require", "do", "unless", "begin", "rescue",
        // SQL (matched case-insensitively)
        "select", "from", "where", "join", "left", "right", "inner", "outer", "on", "group", "by", "order", "having",
        "limit", "offset", "insert", "into", "values", "update", "set", "delete", "as", "distinct", "union", "create",
        "table", "alter", "drop", "index", "primary", "key", "references", "between", "like", "returning", "begin",
        "commit", "rollback",
    ]

    private static let sources: [(Kind, String)] = [
        (.comment, #"/\*[\s\S]*?\*/|//[^\n]*|(?m)^\s*#(?!\{)[^\n]*|--[^\n]*"#),
        (.key, #""(?:[^"\\\n]|\\.)*"(?=\s*:)"#),
        (.string, #""(?:[^"\\\n]|\\.)*"|'(?:[^'\\\n]|\\.)*'|`[^`]*`"#),
        (.number, #"\b(?:0x[0-9a-fA-F]+|\d+(?:\.\d+)?(?:[eE][+-]?\d+)?)\b"#),
        (.keyword, #"\b[A-Za-z_][A-Za-z_]*\b"#),
    ]
    private static let patterns: [(Kind, NSRegularExpression)] = sources.map { ($0.0, try! NSRegularExpression(pattern: $0.1)) }

    /// Non-overlapping tokens; earlier categories (comments, then strings) win over later ones.
    public static func tokens(in code: String, limit: Int = 200_000) -> [Token] {
        let ns = code as NSString
        let full = NSRange(location: 0, length: min(ns.length, limit))
        var taken = IndexSet()
        var out: [Token] = []
        for (kind, regex) in patterns {
            for m in regex.matches(in: code, range: full) {
                let r = m.range
                guard r.length > 0, !taken.intersects(integersIn: r.location..<(r.location + r.length)) else { continue }
                if kind == .keyword {
                    let word = ns.substring(with: r)
                    guard keywords.contains(word) || keywords.contains(word.lowercased()) && word == word.uppercased() else { continue }
                }
                taken.insert(integersIn: r.location..<(r.location + r.length))
                out.append(Token(range: r, kind: kind))
            }
        }
        return out.sorted { $0.range.location < $1.range.location }
    }
}
