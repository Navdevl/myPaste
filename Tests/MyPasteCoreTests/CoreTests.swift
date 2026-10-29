import Foundation
import Testing
@testable import MyPasteCore

private func kind(_ s: String, rtf: Bool = false) -> ContentKind {
    Classifier.kind(for: CaptureFacts(string: s, hasRTF: rtf))
}

private func reason(_ s: String) -> SensitiveDetector.Reason? { SensitiveDetector.reason(for: s) }

@Suite struct ClassifierTests {
    @Test func links() {
        #expect(kind("https://example.com/pricing") == .link)
        #expect(kind("visit https://x.com today") == .text)
    }

    @Test func colors() {
        #expect(kind("#ff8800") == .color)
        #expect(kind("#FFF") == .color)
        #expect(kind("rgb(12, 200, 3)") == .color)
        #expect(kind("rgba(12 200 3 / 0.5)") == .color)
        #expect(kind("#hashtag") == .text)
        let c = Classifier.rgba(from: "#ff0000")!
        #expect(c.r == 1 && c.g == 0 && c.b == 0)
        #expect(Classifier.rgba(from: "rgb(0,255,0)")!.g == 1)
    }

    @Test func contactDetails() {
        #expect(kind("someone@example.com") == .email)
        #expect(kind("+91 98765 43210") == .phone)
        #expect(kind("(415) 555-0132") == .phone)
        #expect(kind("12345678") != .phone)
    }

    @Test func code() {
        #expect(kind("func add(a: Int) -> Int {\n    return a + 1\n}") == .code)
        #expect(kind("SELECT id, name FROM users WHERE id = 1;") == .code)
        #expect(kind("def f(x):\n    return x * 2") == .code)
        #expect(kind("{\"a\":1,\"b\":[2]}") == .code)
        #expect(kind("[1, 2]") == .code)
        #expect(kind("Meeting notes:\nWe agreed to ship on Friday.\nAction items to follow.") == .text)
    }

    @Test func pasteboardShapes() {
        #expect(kind("hello world") == .text)
        #expect(kind("Bold heading", rtf: true) == .richText)
        #expect(Classifier.kind(for: CaptureFacts(string: nil, hasImage: true)) == .image)
        #expect(Classifier.kind(for: CaptureFacts(string: "a.txt", fileURLs: [URL(fileURLWithPath: "/tmp/a.txt")])) == .file)
    }
}

/// All values are well-known public test fixtures, not real secrets.
@Suite struct SensitiveDetectorTests {
    @Test func flagsSecrets() {
        #expect(reason("482913") == .otp)
        #expect(reason("482 913") == .otp)
        #expect(reason("4111 1111 1111 1111") == .card)
        #expect(reason("AKIAIOSFODNN7EXAMPLE") == .apiKey)
        #expect(reason("ghp_" + String(repeating: "a1B2", count: 9)) == .apiKey)
        #expect(reason("sk-test-" + String(repeating: "x", count: 24)) == .apiKey)
        #expect(reason("eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiJ0ZXN0In0.abc_DEF-123") == .jwt)
        #expect(reason("-----BEGIN RSA PRIVATE KEY-----\nMIIfake\n-----END RSA PRIVATE KEY-----") == .privateKey)
        #expect(reason("Tr0ub4dor&3x!") == .password)
    }

    @Test func leavesOrdinaryTextAlone() {
        #expect(reason("2024") == nil)
        #expect(reason("4111 1111 1111 1112") != .card)
        #expect(reason("hello world") == nil)
        #expect(reason("https://example.com/a?b=1") == nil)
        #expect(reason("my_variable_name") == nil)
        #expect(reason("/Users/me/Projects/foo") == nil)
        #expect(reason("someone@example.com") == nil)
        #expect(reason("Hello, World!") == nil)
    }
}

@Suite struct ClipStoreTests {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent("mypaste-test-\(UUID().uuidString)")
    let t0 = Date(timeIntervalSince1970: 1_800_000_000)

    private func text(_ store: ClipStore, _ s: String, hash: String, at offset: TimeInterval = 0, sensitive: String? = nil) throws -> Int64 {
        try store.insert(NewCapture(kind: .text, text: s, contentHash: hash, sensitiveReason: sensitive),
                         sensitiveTTL: 600, now: t0.addingTimeInterval(offset))
    }

    @Test func dedupeAndSearch() throws {
        let store = try ClipStore(directory: dir)
        var changes = 0
        store.onChange = { changes += 1 }
        let a = try text(store, "Quarterly treasury report draft", hash: "a")
        let b = try store.insert(NewCapture(kind: .link, text: "https://example.com", contentHash: "b"), sensitiveTTL: 600, now: t0.addingTimeInterval(1))
        let dup = try text(store, "Quarterly treasury report draft", hash: "a", at: 2)
        #expect(dup == a)
        let items = try store.allItems()
        #expect(items.count == 2)
        #expect(items.first?.id == a)
        #expect(changes == 3)

        #expect(try store.search("treasury") == [a])
        #expect(try store.search("SURY rep") == [a])
        #expect(try store.search("gl") == [b])
        #expect(try store.search("nothing-here").isEmpty)

        try store.setTags(a, ["#finance", "q3 ", "finance"])
        #expect(Set(try store.item(id: a)!.tags) == ["finance", "q3"])
        #expect(try store.search("#finance") == [a])
        try store.rename(b, title: "Example site")
        #expect(try store.search("example site") == [b])
        try store.setOCRText(a, "INVOICE 2231")
        #expect(try store.search("invoice") == [a])
    }

    @Test func pinboards() throws {
        let store = try ClipStore(directory: dir)
        let b = try text(store, "#00ff00", hash: "b")
        let board = try store.createPinboard(name: "Work", colorHex: "#3B82F6")
        try store.pin(b, to: board)
        #expect(try store.item(id: b)!.isPinned)
        #expect(try store.pinboards().map(\.name) == ["Work"])
        try store.deletePinboard(board)
        #expect(!(try store.item(id: b)!.isPinned))
    }

    @Test func sensitiveExpiry() throws {
        let store = try ClipStore(directory: dir)
        let s = try text(store, "482913", hash: "s", sensitive: "otp")
        #expect(try store.item(id: s)!.isSensitive)
        try store.prune(RetentionPolicy(maxItems: 1000, maxDays: 30), now: t0.addingTimeInterval(300))
        #expect(try store.item(id: s) != nil)
        try store.prune(RetentionPolicy(maxItems: 1000, maxDays: 30), now: t0.addingTimeInterval(700))
        #expect(try store.item(id: s) == nil)
    }

    @Test func retentionNeverTouchesPinned() throws {
        let store = try ClipStore(directory: dir)
        let pinned = try text(store, "keep me", hash: "p")
        try store.pin(pinned, to: try store.createPinboard(name: "Keep", colorHex: "#10B981"))
        let oldest = try text(store, "oldest", hash: "o", at: 1)
        for i in 0..<5 { _ = try text(store, "bulk \(i)", hash: "bulk\(i)", at: 10 + Double(i)) }

        try store.prune(RetentionPolicy(maxItems: 3, maxDays: 30), now: t0.addingTimeInterval(20))
        var items = try store.allItems()
        #expect(items.filter { !$0.isPinned }.count == 3)
        #expect(items.contains { $0.id == pinned })
        #expect(items.contains { $0.text == "bulk 4" } && !items.contains { $0.id == oldest })

        try store.prune(RetentionPolicy(maxItems: 1000, maxDays: 30), now: t0.addingTimeInterval(31 * 86_400))
        items = try store.allItems()
        #expect(items.map(\.id) == [pinned])
    }

    @Test func blobsAndEdits() throws {
        let store = try ClipStore(directory: dir)
        let img = try store.insert(NewCapture(kind: .image, text: nil, imagePNG: Data([1, 2, 3]), imageWidth: 1, imageHeight: 1, contentHash: "img"), sensitiveTTL: 600)
        let imgItem = try store.item(id: img)!
        #expect(store.blob(imgItem, "png") == Data([1, 2, 3]))
        try store.delete(img)
        #expect(store.blob(imgItem, "png") == nil)

        let t = try text(store, "plain", hash: "t")
        try store.editText(t, text: "#00ff00")
        #expect(try store.item(id: t)!.kind == .color)
    }

    @Test func rescanFlagsOldIdentifiers() throws {
        let store = try ClipStore(directory: dir)
        let pan = try store.insert(NewCapture(kind: .text, text: "ABCPE1234F", contentHash: "pan"), sensitiveTTL: 600, now: t0)
        let aadhaar = try store.insert(NewCapture(kind: .phone, text: "2345 6789 0124", contentHash: "aad"), sensitiveTTL: 600, now: t0)
        let plain = try text(store, "just words", hash: "w")
        #expect(try store.rescanSensitive(ttl: 600, now: t0) == 2)
        #expect(try store.item(id: pan)!.sensitiveReason == "pan")
        #expect(try store.item(id: aadhaar)!.kind == .text)
        #expect(!(try store.item(id: plain)!.isSensitive))
        #expect(try store.rescanSensitive(ttl: 600, now: t0) == 0)
    }

    @Test func sweepsOrphanBlobs() throws {
        let store = try ClipStore(directory: dir)
        let keep = try store.insert(NewCapture(kind: .image, text: nil, imagePNG: Data([1]), imageWidth: 1, imageHeight: 1, contentHash: "k"), sensitiveTTL: 600)
        let keepItem = try store.item(id: keep)!
        let orphan = store.blobURL(UUID().uuidString, "link.png")
        try Data([2]).write(to: orphan)
        let fresh = store.blobURL(UUID().uuidString, "png")
        try Data([3]).write(to: fresh)
        let later = Date().addingTimeInterval(120)
        // Backdate the orphan; the "fresh" file is still within the 60 s grace window relative to `now`.
        try FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(-300)], ofItemAtPath: orphan.path)
        let r = try store.sweepOrphanBlobs(now: Date())
        #expect(r.files == 1)
        #expect(!FileManager.default.fileExists(atPath: orphan.path))
        #expect(FileManager.default.fileExists(atPath: fresh.path))
        #expect(store.blob(keepItem, "png") == Data([1]))
        #expect(try store.sweepOrphanBlobs(now: later).files == 1) // fresh one is past the grace window now
    }

    @Test func reopenIsIdempotent() throws {
        _ = try text(try ClipStore(directory: dir), "persisted", hash: "x")
        #expect(try ClipStore(directory: dir).allItems().count == 1)
    }
}

@Suite struct SearchQueryTests {
    @Test func parsesFilters() {
        let q = SearchQuery.parse("/img @slack #work invoice 2231")
        #expect(q.kinds == [.image])
        #expect(q.apps == ["slack"])
        #expect(q.tags == ["work"])
        #expect(q.text == "invoice 2231")
    }

    @Test func aliasesAndPrefixes() {
        #expect(SearchQuery.kind(for: "im") == .image)
        #expect(SearchQuery.kind(for: "url") == .link)
        #expect(SearchQuery.kind(for: "colour") == .color)
        #expect(SearchQuery.parse("/secret").sensitiveOnly)
        #expect(SearchQuery.parse("/usr/local").text == "/usr/local")
        #expect(SearchQuery.parse("/").text == "/")
        #expect(SearchQuery.parse("   ").isEmpty)
    }

    @Test func matchesItems() {
        var item = ClipItem(id: 1, uuid: "u", kind: .link, text: "https://example.com", title: nil,
                            sourceBundleID: "com.tinyspeck.slackmacgap", sourceAppName: "Slack",
                            createdAt: Date(), lastUsedAt: Date(), byteSize: 0, imageWidth: 0, imageHeight: 0,
                            isSensitive: false, sensitiveReason: nil, expiresAt: nil, contentHash: "h",
                            hasRTF: false, hasHTML: false, hasImage: false, filePaths: [], ocrText: nil,
                            linkTitle: nil, hasLinkImage: false, hasLinkIcon: false, linkFetched: false)
        item.tags = ["Work"]
        #expect(SearchQuery.parse("/link @sla #wo").matches(item))
        #expect(SearchQuery.parse("@tinyspeck").matches(item))
        #expect(!SearchQuery.parse("/img").matches(item))
        #expect(!SearchQuery.parse("@chrome").matches(item))
        #expect(!SearchQuery.parse("/secret").matches(item))
    }
}

@Suite struct HTMLMetadataTests {
    let base = URL(string: "https://example.com/blog/post?id=1")!

    @Test func openGraphWins() {
        let html = """
        <html><head><title>Fallback &amp; title</title>
        <meta content="OG &quot;Title&quot;" property="og:title">
        <meta property='og:image' content='/img/card.png'>
        <link rel="icon" href="/favicon-32.png"><link rel="apple-touch-icon" href="https://cdn.example.com/touch.png">
        </head></html>
        """
        let m = HTMLMetadata.parse(html: html, base: base)
        #expect(m.title == "OG \"Title\"")
        #expect(m.imageURL?.absoluteString == "https://example.com/img/card.png")
        #expect(m.iconURL?.absoluteString == "https://cdn.example.com/touch.png")
    }

    @Test func fallsBackToTitleAndFavicon() {
        let m = HTMLMetadata.parse(html: "<TITLE>\n  Chapter for Us &#124; Comics\n</TITLE>", base: base)
        #expect(m.title == "Chapter for Us | Comics")
        #expect(m.imageURL == nil)
        #expect(m.iconURL?.absoluteString == "https://example.com/favicon.ico")
    }

    @Test func twitterCardAndUnquotedAttrs() {
        let m = HTMLMetadata.parse(html: "<meta name=twitter:title content=Hi><meta name=twitter:image content=https://x.com/a.jpg>", base: base)
        #expect(m.title == "Hi")
        #expect(m.imageURL?.absoluteString == "https://x.com/a.jpg")
    }
}

/// Synthetic values only: shapes and checksums are valid, the numbers are made up.
@Suite struct IndianIdentifierTests {
    @Test func detects() {
        #expect(reason("ABCPE1234F") == .pan)
        #expect(reason("abcpe1234f") == .pan)
        #expect(reason("2345 6789 0124") == .aadhaar)
        #expect(reason("234567890124") == .aadhaar)
        #expect(reason("HDFC0001234") == .ifsc)
        #expect(reason("someone@okhdfcbank") == .upi)
        #expect(reason("123456789012345") == .account)
    }

    @Test func avoidsLookalikes() {
        #expect(reason("234567890125") != .aadhaar)   // checksum fails, falls to account
        #expect(reason("9876543210") == nil)          // 10-digit mobile
        #expect(reason("1761736200") == nil)          // epoch seconds
        #expect(reason("1761736200123") == nil)       // epoch ms
        #expect(reason("someone@example.com") == nil) // email, not UPI
        #expect(reason("ABCDE12345") == nil)          // not PAN shape
    }

    @Test func masks() {
        typealias D = SensitiveDetector
        #expect(D.masked("ABCPE1234F", reason: .pan) == "XXXXX1234F")
        #expect(D.masked("2345 6789 0124", reason: .aadhaar) == "XXXX XXXX 0124")
        #expect(D.masked("4111 1111 1111 1111", reason: .card) == "XXXX-XXXX-XXXX-1111")
        #expect(D.masked("123456789012345", reason: .account) == "••••2345")
        #expect(D.masked("HDFC0001234", reason: .ifsc) == "HDFC0••••••")
        #expect(D.masked("someone@okhdfcbank", reason: .upi) == "s•••@okhdfcbank")
        #expect(D.masked("482913", reason: .otp) == nil)
    }
}

@Suite struct TransformTests {
    private func run(_ id: String, _ input: String) -> String? {
        Transform.all.first { $0.id == id }!.apply(input)
    }

    @Test func json() {
        #expect(run("json.minify", "{ \"a\" : [1, 2] }") == "{\"a\":[1,2]}")
        #expect(run("json.pretty", "{\"a\":1}")?.contains("\n") == true)
        #expect(run("json.yaml", "{\"name\":\"example\",\"tags\":[\"a\",\"b\"],\"n\":{\"x\":true}}") == "n:\n  x: true\nname: example\ntags:\n  - a\n  - b")
        #expect(run("json.pretty", "not json") == nil)
        #expect(run("str.escape", "say \"hi\"\n") == "say \\\"hi\\\"\\n")
        #expect(run("str.unescape", "\"line\\nnext\"") == "line\nnext")
    }

    @Test func sql() {
        #expect(Transform.formatSQL("select id, name from users u left join orders o on o.uid = u.id where name = 'from x' limit 100")
                == "SELECT id, name\nFROM users u\nLEFT JOIN orders o ON o.uid = u.id\nWHERE name = 'from x'\nLIMIT 100")
    }

    @Test func textCleanup() {
        #expect(run("text.join", "a\n  b\n\nc") == "a b c")
        #expect(run("text.unique", "b\na\nb") == "b\na")
        #expect(run("text.sort", "b\na\nc") == "a\nb\nc")
        #expect(run("case.camel", "hello big world") == "helloBigWorld")
        #expect(run("case.snake", "Hello Big World") == "hello_big_world")
        #expect(run("text.collapse", "a   b\t c") == "a b c")
    }

    @Test func urlsAndEncoding() {
        #expect(Transform.stripTracking("https://example.com/p?id=7&utm_source=x&fbclid=abc") == "https://example.com/p?id=7")
        #expect(Transform.stripTracking("https://example.com/p?id=7") == nil)
        #expect(run("b64.decode", run("b64.encode", "héllo")!) == "héllo")
        #expect(run("b64.decode", "hello world") == nil)
        #expect(run("url.decode", "a%20b+c") == "a b c")
        #expect(run("extract.urls", "see https://a.com and https://b.com/x, ok") == "https://a.com\nhttps://b.com/x")
        #expect(run("extract.emails", "mail a@x.com or b@y.org") == "a@x.com\nb@y.org")
    }

    @Test func infoAndTime() {
        #expect(run("info.count", "one two\nthree") == "3 words · 2 lines · 13 characters")
        #expect(run("hash.md5", "abc") == "900150983cd24fb0d6963f7d28e17f72")
        #expect(Transform.epochOrDate("1800000000") == "2027-01-15 13:30:00 IST")
        #expect(Transform.epochOrDate("2027-01-15 13:30:00") == "1800000000")
        #expect(Transform.epochOrDate("hello") == nil)
    }

    @Test func availableFiltersInapplicable() {
        let ids = Transform.available(for: "plain words here").map(\.0.id)
        #expect(!ids.contains("json.pretty"))
        #expect(ids.contains("case.upper"))
    }
}

@Suite struct SnippetTests {
    let now = Date(timeIntervalSince1970: 1_800_000_000) // 2027-01-15 13:30 IST

    @Test func expandsPlaceholders() {
        let r = Snippet.expand("Hi on {date} at {time}: {clipboard}", clipboard: "PR #42", now: now)
        #expect(r.text == "Hi on 2027-01-15 at 13:30: PR #42")
        #expect(r.charsAfterCursor == nil)
        #expect(Snippet.expand("{datetime}", clipboard: nil, now: now).text == "2027-01-15T13:30:00+05:30")
    }

    @Test func cursor() {
        let r = Snippet.expand("SELECT * FROM {cursor} LIMIT 100;", clipboard: nil, now: now)
        #expect(r.text == "SELECT * FROM  LIMIT 100;")
        #expect(r.charsAfterCursor == 11)
        #expect(Snippet.hasPlaceholders("x {uuid}") && !Snippet.hasPlaceholders("x {other}"))
    }
}

@Suite struct BackupTests {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("mypaste-backup-\(UUID().uuidString)")

    @Test func roundTripMergesAndSkipsSensitive() throws {
        let src = try ClipStore(directory: root.appendingPathComponent("src"))
        let board = try src.createPinboard(name: "Work", colorHex: "#3B82F6")
        let pinned = try src.insert(NewCapture(kind: .text, text: "pinned note", contentHash: "p"), sensitiveTTL: 600)
        try src.pin(pinned, to: board)
        try src.setTags(pinned, ["sql"])
        let img = try src.insert(NewCapture(kind: .image, text: nil, imagePNG: Data([9, 9]), imageWidth: 1, imageHeight: 1, contentHash: "img"), sensitiveTTL: 600)
        try src.pin(img, to: board)
        _ = try src.insert(NewCapture(kind: .text, text: "history only", contentHash: "h"), sensitiveTTL: 600)
        let secret = try src.insert(NewCapture(kind: .text, text: "482913", contentHash: "s", sensitiveReason: "otp"), sensitiveTTL: 600)
        try src.pin(secret, to: board)

        let pinsOnly = root.appendingPathComponent("pins")
        let s1 = try Backup.export(src, includeHistory: false, to: pinsOnly)
        #expect(s1 == Backup.Summary(items: 2, pinboards: 1, skippedSensitive: 1, skippedDuplicates: 0))

        let full = root.appendingPathComponent("full")
        #expect(try Backup.export(src, includeHistory: true, to: full).items == 3)

        let dst = try ClipStore(directory: root.appendingPathComponent("dst"))
        _ = try dst.insert(NewCapture(kind: .text, text: "pinned note", contentHash: "p"), sensitiveTTL: 600) // already present
        let r = try Backup.importBackup(from: full, into: dst)
        #expect(r.items == 2 && r.skippedDuplicates == 1)
        let items = try dst.allItems()
        #expect(items.count == 3)
        let note = items.first { $0.text == "pinned note" }!
        #expect(note.isPinned && note.tags == ["sql"])
        let image = items.first { $0.kind == .image }!
        #expect(dst.blob(image, "png") == Data([9, 9]))
        #expect(try dst.pinboards().map(\.name) == ["Work"])
        #expect(!items.contains { $0.isSensitive })

        // Importing again is a no-op.
        #expect(try Backup.importBackup(from: full, into: dst).items == 0)
        #expect(try dst.allItems().count == 3)
    }
}

@Suite struct BackupArchiveTests {
    @Test func zipRoundTrip() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("mypaste-zip-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let src = try ClipStore(directory: root.appendingPathComponent("src"))
        let board = try src.createPinboard(name: "Snippets", colorHex: "#10B981")
        let id = try src.insert(NewCapture(kind: .text, text: "SELECT 1", contentHash: "q"), sensitiveTTL: 600)
        try src.pin(id, to: board)
        let archive = root.appendingPathComponent("backup.mypaste")
        let out = try BackupArchive.export(store: src, includeHistory: false, to: archive)
        #expect(out.items == 1 && FileManager.default.fileExists(atPath: archive.path))
        let dst = try ClipStore(directory: root.appendingPathComponent("dst"))
        let inn = try BackupArchive.importArchive(archive, into: dst)
        #expect(inn.items == 1)
        #expect(try dst.allItems().first?.isPinned == true)
    }
}

@Suite struct SyntaxHighlighterTests {
    private func kinds(_ code: String) -> [(String, SyntaxHighlighter.Kind)] {
        let ns = code as NSString
        return SyntaxHighlighter.tokens(in: code).map { (ns.substring(with: $0.range), $0.kind) }
    }

    @Test func swiftish() {
        let t = kinds("let n = 42 // answer\nreturn \"let\"")
        #expect(t.contains { $0 == ("let", .keyword) })
        #expect(t.contains { $0 == ("42", .number) })
        #expect(t.contains { $0 == ("// answer", .comment) })
        #expect(t.contains { $0 == ("\"let\"", .string) })   // keyword inside a string stays a string
        #expect(!t.contains { $0.0 == "n" })
    }

    @Test func sqlAndJSON() {
        let sql = kinds("SELECT id FROM users -- note")
        #expect(sql.contains { $0 == ("SELECT", .keyword) } && sql.contains { $0 == ("FROM", .keyword) })
        #expect(sql.contains { $0 == ("-- note", .comment) })
        let json = kinds("{\"amount\": 100, \"ok\": true}")
        #expect(json.contains { $0 == ("\"amount\"", .key) })
        #expect(json.contains { $0 == ("true", .keyword) })
        #expect(json.contains { $0 == ("100", .number) })
    }
}
