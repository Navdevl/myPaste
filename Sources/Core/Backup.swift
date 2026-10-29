import Foundation
import GRDB

/// Folder-based export/import (the app zips/unzips it). Sensitive items are never exported.
/// Layout: manifest.json + blobs/<uuid>.<ext>.
public enum Backup {
    public static let formatVersion = 1

    public struct Manifest: Codable {
        public var version: Int
        public var exportedAt: Date
        public var pinboards: [Board]
        public var items: [Item]
    }

    public struct Board: Codable {
        public var name: String
        public var colorHex: String
    }

    public struct Item: Codable {
        public var uuid: String
        public var kind: String
        public var text: String?
        public var title: String?
        public var sourceBundleID: String?
        public var sourceAppName: String?
        public var createdAt: Double
        public var lastUsedAt: Double
        public var byteSize: Int64
        public var imageWidth: Int
        public var imageHeight: Int
        public var contentHash: String
        public var hasRTF: Bool
        public var hasHTML: Bool
        public var hasImage: Bool
        public var filePaths: [String]
        public var ocrText: String?
        public var linkTitle: String?
        public var hasLinkImage: Bool
        public var hasLinkIcon: Bool
        public var pinboards: [String]
        public var tags: [String]
    }

    public struct Summary: Equatable {
        public var items: Int
        public var pinboards: Int
        public var skippedSensitive: Int
        public var skippedDuplicates: Int
    }

    static let blobExts = ["rtf", "html", "png", "link.png", "icon.png"]

    /// Writes pinned items (and all non-sensitive history when `includeHistory`) into `folder`.
    @discardableResult
    public static func export(_ store: ClipStore, includeHistory: Bool, to folder: URL, now: Date = Date()) throws -> Summary {
        let fm = FileManager.default
        try fm.createDirectory(at: folder.appendingPathComponent("blobs"), withIntermediateDirectories: true)
        let boards = try store.pinboards()
        let boardName = Dictionary(uniqueKeysWithValues: boards.map { ($0.id, $0.name) })
        let all = try store.allItems()
        let chosen = all.filter { includeHistory || $0.isPinned }
        let exportable = chosen.filter { !$0.isSensitive }
        let items: [Item] = exportable.map { i in
            for ext in blobExts {
                let src = store.blobURL(i.uuid, ext)
                if fm.fileExists(atPath: src.path) {
                    try? fm.copyItem(at: src, to: folder.appendingPathComponent("blobs/\(i.uuid).\(ext)"))
                }
            }
            return Item(uuid: i.uuid, kind: i.kind.rawValue, text: i.text, title: i.title,
                        sourceBundleID: i.sourceBundleID, sourceAppName: i.sourceAppName,
                        createdAt: i.createdAt.timeIntervalSince1970, lastUsedAt: i.lastUsedAt.timeIntervalSince1970,
                        byteSize: i.byteSize, imageWidth: i.imageWidth, imageHeight: i.imageHeight,
                        contentHash: i.contentHash, hasRTF: i.hasRTF, hasHTML: i.hasHTML, hasImage: i.hasImage,
                        filePaths: i.filePaths, ocrText: i.ocrText, linkTitle: i.linkTitle,
                        hasLinkImage: i.hasLinkImage, hasLinkIcon: i.hasLinkIcon,
                        pinboards: i.pinboardIDs.compactMap { boardName[$0] }, tags: i.tags)
        }
        let manifest = Manifest(version: formatVersion, exportedAt: now,
                                pinboards: boards.map { Board(name: $0.name, colorHex: $0.colorHex) }, items: items)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(manifest).write(to: folder.appendingPathComponent("manifest.json"))
        return Summary(items: items.count, pinboards: boards.count,
                       skippedSensitive: chosen.count - exportable.count, skippedDuplicates: 0)
    }

    /// Merges a backup folder: pinboards by name, items by content hash (existing items just gain the
    /// backup's pins and tags). Imported items keep their original timestamps.
    @discardableResult
    public static func importBackup(from folder: URL, into store: ClipStore) throws -> Summary {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let manifest = try decoder.decode(Manifest.self, from: Data(contentsOf: folder.appendingPathComponent("manifest.json")))
        guard manifest.version <= formatVersion else {
            throw NSError(domain: "myPaste.backup", code: 1, userInfo: [NSLocalizedDescriptionKey: "Backup is from a newer myPaste (format \(manifest.version))"])
        }
        var boardIDs = Dictionary(uniqueKeysWithValues: try store.pinboards().map { ($0.name, $0.id) })
        for b in manifest.pinboards where boardIDs[b.name] == nil {
            boardIDs[b.name] = try store.createPinboard(name: b.name, colorHex: b.colorHex)
        }
        let fm = FileManager.default
        var imported = 0, duplicates = 0
        for item in manifest.items {
            let existing = try store.dbQueue.read { db in
                try Int64.fetchOne(db, sql: "SELECT id FROM item WHERE contentHash = ?", arguments: [item.contentHash])
            }
            let id: Int64
            if let existing {
                id = existing
                duplicates += 1
            } else {
                let taken = try store.dbQueue.read { db in try Bool.fetchOne(db, sql: "SELECT 1 FROM item WHERE uuid = ?", arguments: [item.uuid]) } ?? false
                let uuid = taken ? UUID().uuidString : item.uuid
                for ext in blobExts {
                    let src = folder.appendingPathComponent("blobs/\(item.uuid).\(ext)")
                    if fm.fileExists(atPath: src.path) { try? fm.copyItem(at: src, to: store.blobURL(uuid, ext)) }
                }
                id = try store.insertImported(item, uuid: uuid)
                imported += 1
            }
            for name in item.pinboards { if let b = boardIDs[name] { try store.pin(id, to: b) } }
            if !item.tags.isEmpty {
                let current = try store.item(id: id)?.tags ?? []
                try store.setTags(id, Array(Set(current + item.tags)))
            }
        }
        return Summary(items: imported, pinboards: manifest.pinboards.count, skippedSensitive: 0, skippedDuplicates: duplicates)
    }
}

extension ClipStore {
    func insertImported(_ i: Backup.Item, uuid: String) throws -> Int64 {
        let id: Int64 = try dbQueue.write { db in
            try db.execute(sql: """
            INSERT INTO item (uuid, kind, text, title, sourceBundleID, sourceAppName, createdAt, lastUsedAt, byteSize,
                              imageWidth, imageHeight, contentHash, hasRTF, hasHTML, hasImage, filePaths, ocrText,
                              linkTitle, hasLinkImage, hasLinkIcon, linkFetched)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 1)
            """, arguments: [uuid, i.kind, i.text, i.title, i.sourceBundleID, i.sourceAppName, i.createdAt, i.lastUsedAt,
                             i.byteSize, i.imageWidth, i.imageHeight, i.contentHash, i.hasRTF, i.hasHTML, i.hasImage,
                             i.filePaths.isEmpty ? nil : Self.encodePaths(i.filePaths), i.ocrText, i.linkTitle,
                             i.hasLinkImage, i.hasLinkIcon])
            let id = db.lastInsertedRowID
            try Self.reindex(db, id)
            return id
        }
        onChange?()
        return id
    }
}

/// Zips/unzips backup folders with ditto (ships with macOS, preserves names).
public enum BackupArchive {
    public static func export(store: ClipStore, includeHistory: Bool, to archive: URL) throws -> Backup.Summary {
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("mypaste-export-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: tmp) }
        let summary = try Backup.export(store, includeHistory: includeHistory, to: tmp)
        try? FileManager.default.removeItem(at: archive)
        try ditto(["-c", "-k", "--sequesterRsrc", tmp.path, archive.path])
        return summary
    }

    public static func importArchive(_ archive: URL, into store: ClipStore) throws -> Backup.Summary {
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("mypaste-import-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: tmp) }
        try ditto(["-x", "-k", archive.path, tmp.path])
        return try Backup.importBackup(from: tmp, into: store)
    }

    private static func ditto(_ args: [String]) throws {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        p.arguments = args
        try p.run()
        p.waitUntilExit()
        guard p.terminationStatus == 0 else {
            throw NSError(domain: "myPaste.backup", code: Int(p.terminationStatus), userInfo: [NSLocalizedDescriptionKey: "ditto failed (\(p.terminationStatus))"])
        }
    }
}
