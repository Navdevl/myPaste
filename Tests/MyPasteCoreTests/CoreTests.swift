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
