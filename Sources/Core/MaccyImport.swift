import CryptoKit
import Foundation
import GRDB
import ImageIO

/// Imports pinned items from Maccy 2.x (SwiftData/Core Data store) onto a myPaste pinboard.
/// Maccy has no categories: pins are a flat list, so they all land on one board.
public enum MaccyImport {
    public static var defaultStoreURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Containers/org.p0deje.Maccy/Data/Library/Application Support/Maccy/Storage.sqlite")
    }

    public struct Summary: Equatable {
        public var imported: Int
        public var alreadyHere: Int
        public var sensitive: Int
    }

    struct PinnedItem {
        var firstCopied: Date
        var lastCopied: Date
        var app: String?
        var contents: [String: Data]
    }

    /// Reads Maccy's pins. Works on a temporary copy of the store (+ WAL/SHM) so Maccy's files are
    /// never opened for writing, even by SQLite's WAL recovery.
    static func readPins(from storeURL: URL) throws -> [PinnedItem] {
        let fm = FileManager.default
        guard fm.fileExists(atPath: storeURL.path) else {
            throw NSError(domain: "myPaste.maccy", code: 1, userInfo: [NSLocalizedDescriptionKey: "Maccy's history wasn't found at \(storeURL.path)"])
        }
        let tmp = fm.temporaryDirectory.appendingPathComponent("maccy-import-\(UUID().uuidString)")
        try fm.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: tmp) }
        for suffix in ["", "-wal", "-shm"] {
            let src = URL(fileURLWithPath: storeURL.path + suffix)
            if fm.fileExists(atPath: src.path) {
                try fm.copyItem(at: src, to: tmp.appendingPathComponent("Storage.sqlite" + suffix))
            }
        }
        let db = try DatabaseQueue(path: tmp.appendingPathComponent("Storage.sqlite").path)
        return try db.read { db in
            let items = try Row.fetchAll(db, sql: """
            SELECT Z_PK, ZFIRSTCOPIEDAT, ZLASTCOPIEDAT, ZAPPLICATION FROM ZHISTORYITEM
            WHERE ZPIN IS NOT NULL ORDER BY ZPIN
            """)
            return try items.map { r in
                var contents: [String: Data] = [:]
                for c in try Row.fetchAll(db, sql: "SELECT ZTYPE, ZVALUE FROM ZHISTORYITEMCONTENT WHERE ZITEM = ?", arguments: [r["Z_PK"] as Int64]) {
                    if let type: String = c["ZTYPE"], let value: Data = c["ZVALUE"] { contents[type] = value }
                }
                // Core Data timestamps are seconds since 2001-01-01.
                let first = Date(timeIntervalSinceReferenceDate: r["ZFIRSTCOPIEDAT"] ?? 0)
                return PinnedItem(firstCopied: first, lastCopied: Date(timeIntervalSinceReferenceDate: r["ZLASTCOPIEDAT"] ?? first.timeIntervalSinceReferenceDate),
                                  app: r["ZAPPLICATION"], contents: contents)
            }
        }
    }

    /// Imports Maccy's pins onto `boardName` (created if needed). Items already in myPaste (same content)
    /// are just pinned to the board. `appName` resolves bundle ids to display names.
    @discardableResult
    public static func importPins(from storeURL: URL = defaultStoreURL, into store: ClipStore, boardName: String = "Maccy",
                                  boardColor: String = "#F59E0B", sensitiveTTL: TimeInterval,
                                  appName: (String) -> String? = { _ in nil }) throws -> Summary {
        let pins = try readPins(from: storeURL)
        let board = try store.pinboards().first { $0.name == boardName }?.id
            ?? store.createPinboard(name: boardName, colorHex: boardColor)
        var summary = Summary(imported: 0, alreadyHere: 0, sensitive: 0)
        for pin in pins {
            guard let capture = capture(for: pin, appName: appName) else { continue }
            let existing = try store.dbQueue.read { db in
                try Int64.fetchOne(db, sql: "SELECT id FROM item WHERE contentHash = ?", arguments: [capture.contentHash])
            }
            let id: Int64
            if let existing {
                id = existing
                summary.alreadyHere += 1
            } else {
                id = try store.insert(capture, sensitiveTTL: sensitiveTTL)
                try store.dbQueue.write { db in
                    try db.execute(sql: "UPDATE item SET createdAt = ?, lastUsedAt = ? WHERE id = ?",
                                   arguments: [pin.firstCopied.timeIntervalSince1970, pin.lastCopied.timeIntervalSince1970, id])
                }
                summary.imported += 1
                if capture.sensitiveReason != nil { summary.sensitive += 1 }
            }
            try store.pin(id, to: board)
        }
        return summary
    }

    /// Same classification and hashing as a live capture, so re-copies and re-imports dedupe.
    static func capture(for pin: PinnedItem, appName: (String) -> String?) -> NewCapture? {
        let c = pin.contents
        let text = (c["public.utf8-plain-text"] ?? c["NSStringPboardType"]).flatMap { String(data: $0, encoding: .utf8) }
            ?? c["public.utf16-external-plain-text"].flatMap { String(data: $0, encoding: .utf16) }
        let fileURLs = (c["public.file-url"]).flatMap { String(data: $0, encoding: .utf8) }.flatMap(URL.init(string:)).map { [$0] } ?? []
        let png = c["public.png"] ?? c["public.tiff"]
        let rtf = c["public.rtf"]
        let html = c["public.html"]
        let facts = CaptureFacts(string: text, hasRTF: rtf != nil, hasHTML: html != nil, hasImage: png != nil,
                                 fileURLs: fileURLs, hasURLType: c["public.url"] != nil)
        var kind = Classifier.kind(for: facts)
        if kind == .text, (text ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, png == nil { return nil }
        let hashSource: Data
        switch kind {
        case .file: hashSource = Data(fileURLs.map(\.path).joined(separator: "\n").utf8)
        case .image: hashSource = png ?? Data()
        default: hashSource = Data((text ?? "").utf8)
        }
        let hash = kind.rawValue + ":" + SHA256.hash(data: hashSource).map { String(format: "%02x", $0) }.joined()
        // Same order as PasteboardMonitor: hash first, then file identifiers (Aadhaar looks like a phone) as text.
        let reason = text.flatMap(SensitiveDetector.reason(for:))
        if reason?.isIdentifier == true { kind = .text }
        let keepsRich = kind == .richText || kind == .code
        var size = (width: 0, height: 0)
        if kind == .image, let png, let src = CGImageSourceCreateWithData(png as CFData, nil),
           let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any] {
            size = (props[kCGImagePropertyPixelWidth] as? Int ?? 0, props[kCGImagePropertyPixelHeight] as? Int ?? 0)
        }
        return NewCapture(kind: kind,
                          text: kind == .image ? nil : (kind == .file ? fileURLs.map(\.lastPathComponent).joined(separator: "\n") : text),
                          rtf: keepsRich ? rtf : nil, html: keepsRich && rtf == nil ? html : nil,
                          imagePNG: kind == .image ? png : nil, imageWidth: size.width, imageHeight: size.height,
                          filePaths: fileURLs.map(\.path),
                          sourceBundleID: pin.app, sourceAppName: pin.app.flatMap(appName),
                          contentHash: hash, sensitiveReason: reason?.rawValue)
    }
}
