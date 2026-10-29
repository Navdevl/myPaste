import Foundation
import GRDB

/// Persistence for clips, pinboards and tags. SQLite (via GRDB) holds metadata and the search index;
/// large payloads (images, RTF, HTML, link previews) live as files in `blobDir`.
/// Dates are stored as REAL seconds since 1970 so retention queries can compare numerically.
public final class ClipStore {
    public let dbQueue: DatabaseQueue
    public let blobDir: URL
    /// Called on the writing thread after any mutation.
    public var onChange: (() -> Void)?

    public init(directory: URL) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        blobDir = directory.appendingPathComponent("blobs", isDirectory: true)
        try FileManager.default.createDirectory(at: blobDir, withIntermediateDirectories: true)
        var config = Configuration()
        config.foreignKeysEnabled = true
        dbQueue = try DatabaseQueue(path: directory.appendingPathComponent("clips.sqlite").path, configuration: config)
        try Self.migrator.migrate(dbQueue)
    }

    // MARK: Schema

    private static var migrator: DatabaseMigrator {
        var m = DatabaseMigrator()
        // IF NOT EXISTS: databases created before the GRDB switch already have this schema.
        m.registerMigration("v1") { db in
            try db.execute(sql: """
            CREATE TABLE IF NOT EXISTS item (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                uuid TEXT NOT NULL UNIQUE,
                kind TEXT NOT NULL,
                text TEXT,
                title TEXT,
                sourceBundleID TEXT,
                sourceAppName TEXT,
                createdAt REAL NOT NULL,
                lastUsedAt REAL NOT NULL,
                byteSize INTEGER NOT NULL DEFAULT 0,
                imageWidth INTEGER NOT NULL DEFAULT 0,
                imageHeight INTEGER NOT NULL DEFAULT 0,
                isSensitive INTEGER NOT NULL DEFAULT 0,
                sensitiveReason TEXT,
                expiresAt REAL,
                contentHash TEXT NOT NULL,
                hasRTF INTEGER NOT NULL DEFAULT 0,
                hasHTML INTEGER NOT NULL DEFAULT 0,
                hasImage INTEGER NOT NULL DEFAULT 0,
                filePaths TEXT,
                ocrText TEXT,
                linkTitle TEXT,
                hasLinkImage INTEGER NOT NULL DEFAULT 0,
                linkFetched INTEGER NOT NULL DEFAULT 0
            );
            CREATE INDEX IF NOT EXISTS item_hash ON item(contentHash);
            CREATE INDEX IF NOT EXISTS item_lastUsed ON item(lastUsedAt);
            CREATE TABLE IF NOT EXISTS pinboard (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                name TEXT NOT NULL,
                colorHex TEXT NOT NULL,
                position INTEGER NOT NULL
            );
            CREATE TABLE IF NOT EXISTS pin (
                itemID INTEGER NOT NULL REFERENCES item(id) ON DELETE CASCADE,
                pinboardID INTEGER NOT NULL REFERENCES pinboard(id) ON DELETE CASCADE,
                addedAt REAL NOT NULL,
                PRIMARY KEY (itemID, pinboardID)
            );
            CREATE TABLE IF NOT EXISTS tag (
                itemID INTEGER NOT NULL REFERENCES item(id) ON DELETE CASCADE,
                name TEXT NOT NULL COLLATE NOCASE,
                PRIMARY KEY (itemID, name)
            );
            -- Trigram tokenizer: case-insensitive substring search for queries of 3+ chars.
            CREATE VIRTUAL TABLE IF NOT EXISTS item_fts USING fts5(body, tokenize='trigram');
            """)
        }
        // Favicon fallback for link cards; re-queue previews that LinkPresentation returned empty.
        m.registerMigration("v2") { db in
            try db.execute(sql: """
            ALTER TABLE item ADD COLUMN hasLinkIcon INTEGER NOT NULL DEFAULT 0;
            UPDATE item SET linkFetched = 0 WHERE kind = 'link' AND linkTitle IS NULL AND hasLinkImage = 0;
            """)
        }
        return m
    }

    // MARK: Reads

    public func allItems() throws -> [ClipItem] {
        try dbQueue.read { db in
            var items = try Row.fetchAll(db, sql: "SELECT * FROM item ORDER BY lastUsedAt DESC").map(Self.item(from:))
            var pins: [Int64: [Int64]] = [:]
            for r in try Row.fetchAll(db, sql: "SELECT itemID, pinboardID FROM pin ORDER BY addedAt") {
                pins[r["itemID"], default: []].append(r["pinboardID"])
            }
            var tags: [Int64: [String]] = [:]
            for r in try Row.fetchAll(db, sql: "SELECT itemID, name FROM tag ORDER BY name") {
                tags[r["itemID"], default: []].append(r["name"])
            }
            for i in items.indices {
                items[i].pinboardIDs = pins[items[i].id] ?? []
                items[i].tags = tags[items[i].id] ?? []
            }
            return items
        }
    }

    /// Single-row fetch; called per capture, so it must not load the whole history.
    public func item(id: Int64) throws -> ClipItem? {
        try dbQueue.read { db in
            guard let row = try Row.fetchOne(db, sql: "SELECT * FROM item WHERE id = ?", arguments: [id]) else { return nil }
            var item = Self.item(from: row)
            item.pinboardIDs = try Int64.fetchAll(db, sql: "SELECT pinboardID FROM pin WHERE itemID = ? ORDER BY addedAt", arguments: [id])
            item.tags = try String.fetchAll(db, sql: "SELECT name FROM tag WHERE itemID = ? ORDER BY name", arguments: [id])
            return item
        }
    }

    public func pinboards() throws -> [Pinboard] {
        try dbQueue.read { db in
            try Row.fetchAll(db, sql: "SELECT * FROM pinboard ORDER BY position, id").map {
                Pinboard(id: $0["id"], name: $0["name"], colorHex: $0["colorHex"], position: $0["position"])
            }
        }
    }

    public func allTags() throws -> [String] {
        try dbQueue.read { db in
            try String.fetchAll(db, sql: "SELECT DISTINCT name FROM tag ORDER BY name COLLATE NOCASE")
        }
    }

    /// IDs whose text, title, OCR text, link title, file names or tags contain every whitespace-separated term.
    public func search(_ query: String) throws -> Set<Int64> {
        let terms = query.split(whereSeparator: \.isWhitespace).map(String.init)
        guard !terms.isEmpty else { return [] }
        return try dbQueue.read { db in
            var result: Set<Int64>?
            for term in terms {
                let ids: Set<Int64>
                if term.count >= 3 {
                    let quoted = "\"" + term.replacingOccurrences(of: "\"", with: "\"\"") + "\""
                    ids = Set(try Int64.fetchAll(db, sql: "SELECT rowid FROM item_fts WHERE item_fts MATCH ?", arguments: [quoted]))
                } else {
                    let like = "%" + term.replacingOccurrences(of: "%", with: "\\%").replacingOccurrences(of: "_", with: "\\_") + "%"
                    ids = Set(try Int64.fetchAll(db, sql: "SELECT rowid FROM item_fts WHERE body LIKE ? ESCAPE '\\'", arguments: [like]))
                }
                result = result.map { $0.intersection(ids) } ?? ids
            }
            return result ?? []
        }
    }

    // MARK: Writes

    /// Inserts a capture, or bumps the existing item with identical content to the front.
    @discardableResult
    public func insert(_ c: NewCapture, sensitiveTTL: TimeInterval, now: Date = Date()) throws -> Int64 {
        let t = now.timeIntervalSince1970
        if let existing = try dbQueue.read({ db in
            try Int64.fetchOne(db, sql: "SELECT id FROM item WHERE contentHash = ? LIMIT 1", arguments: [c.contentHash])
        }) {
            try dbQueue.write { db in
                try db.execute(sql: """
                UPDATE item SET lastUsedAt = ?, sourceBundleID = COALESCE(?, sourceBundleID),
                                sourceAppName = COALESCE(?, sourceAppName) WHERE id = ?
                """, arguments: [t, c.sourceBundleID, c.sourceAppName, existing])
            }
            onChange?()
            return existing
        }
        let uuid = UUID().uuidString
        var size = Int64(c.text?.utf8.count ?? 0)
        if let rtf = c.rtf { try rtf.write(to: blobURL(uuid, "rtf")); size += Int64(rtf.count) }
        if let html = c.html { try html.write(to: blobURL(uuid, "html")); size += Int64(html.count) }
        if let png = c.imagePNG { try png.write(to: blobURL(uuid, "png")); size += Int64(png.count) }
        if c.kind == .file {
            size = c.filePaths.reduce(0) { acc, p in
                acc + ((try? FileManager.default.attributesOfItem(atPath: p)[.size] as? Int64) ?? 0)
            }
        }
        let sensitive = c.sensitiveReason != nil
        let id: Int64 = try dbQueue.write { db in
            try db.execute(sql: """
            INSERT INTO item (uuid, kind, text, sourceBundleID, sourceAppName, createdAt, lastUsedAt, byteSize,
                              imageWidth, imageHeight, isSensitive, sensitiveReason, expiresAt, contentHash,
                              hasRTF, hasHTML, hasImage, filePaths)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """, arguments: [uuid, c.kind.rawValue, c.text, c.sourceBundleID, c.sourceAppName, t, t, size,
                             c.imageWidth, c.imageHeight, sensitive, c.sensitiveReason,
                             sensitive ? t + sensitiveTTL : nil, c.contentHash,
                             c.rtf != nil, c.html != nil, c.imagePNG != nil,
                             c.filePaths.isEmpty ? nil : Self.encodePaths(c.filePaths)])
            let id = db.lastInsertedRowID
            try Self.reindex(db, id)
            return id
        }
        onChange?()
        return id
    }

    public func touch(_ id: Int64, now: Date = Date()) throws {
        try write { db in
            try db.execute(sql: "UPDATE item SET lastUsedAt = ? WHERE id = ?", arguments: [now.timeIntervalSince1970, id])
        }
    }

    public func rename(_ id: Int64, title: String?) throws {
        let t = title?.trimmingCharacters(in: .whitespacesAndNewlines)
        try write { db in
            try db.execute(sql: "UPDATE item SET title = ? WHERE id = ?", arguments: [t?.isEmpty == false ? t : nil, id])
            try Self.reindex(db, id)
        }
    }

    /// Replaces the text. Formatting no longer matches, so rich payloads are dropped.
    public func editText(_ id: Int64, text: String) throws {
        guard let uuid = try uuid(of: id) else { return }
        try? FileManager.default.removeItem(at: blobURL(uuid, "rtf"))
        try? FileManager.default.removeItem(at: blobURL(uuid, "html"))
        let kind = Classifier.kind(for: CaptureFacts(string: text))
        try write { db in
            try db.execute(sql: """
            UPDATE item SET text = ?, kind = ?, hasRTF = 0, hasHTML = 0, byteSize = ?, contentHash = ? WHERE id = ?
            """, arguments: [text, kind.rawValue, Int64(text.utf8.count), "edited:" + UUID().uuidString, id])
            try Self.reindex(db, id)
        }
    }

    public func setOCRText(_ id: Int64, _ text: String) throws {
        try write { db in
            try db.execute(sql: "UPDATE item SET ocrText = ? WHERE id = ?", arguments: [text, id])
            try Self.reindex(db, id)
        }
    }

    public func setLinkPreview(_ id: Int64, title: String?, imagePNG: Data?, iconPNG: Data? = nil) throws {
        guard let uuid = try uuid(of: id) else { return }
        if let png = imagePNG { try png.write(to: blobURL(uuid, "link.png")) }
        if let png = iconPNG { try png.write(to: blobURL(uuid, "icon.png")) }
        try write { db in
            try db.execute(sql: "UPDATE item SET linkTitle = ?, hasLinkImage = ?, hasLinkIcon = ?, linkFetched = 1 WHERE id = ?",
                           arguments: [title, imagePNG != nil, iconPNG != nil, id])
            try Self.reindex(db, id)
        }
    }

    public func delete(_ id: Int64) throws {
        guard let uuid = try uuid(of: id) else { return }
        try write { db in try Self.deleteRows(db, [id]) }
        removeBlobs(uuid)
    }

    public func clearHistory() throws {
        let rows = try dbQueue.read { db in
            try Row.fetchAll(db, sql: "SELECT id, uuid FROM item WHERE id NOT IN (SELECT itemID FROM pin)")
        }
        guard !rows.isEmpty else { return }
        try write { db in try Self.deleteRows(db, rows.map { $0["id"] }) }
        rows.forEach { removeBlobs($0["uuid"]) }
    }

    // MARK: Pinboards

    @discardableResult
    public func createPinboard(name: String, colorHex: String) throws -> Int64 {
        let id: Int64 = try dbQueue.write { db in
            let pos = try Int.fetchOne(db, sql: "SELECT COALESCE(MAX(position), -1) + 1 FROM pinboard") ?? 0
            try db.execute(sql: "INSERT INTO pinboard (name, colorHex, position) VALUES (?, ?, ?)", arguments: [name, colorHex, pos])
            return db.lastInsertedRowID
        }
        onChange?()
        return id
    }

    public func updatePinboard(_ id: Int64, name: String, colorHex: String) throws {
        try write { db in
            try db.execute(sql: "UPDATE pinboard SET name = ?, colorHex = ? WHERE id = ?", arguments: [name, colorHex, id])
        }
    }

    /// Items only on this board fall back into history; retention may prune them later.
    public func deletePinboard(_ id: Int64) throws {
        try write { db in try db.execute(sql: "DELETE FROM pinboard WHERE id = ?", arguments: [id]) }
    }

    public func pin(_ itemID: Int64, to boardID: Int64, now: Date = Date()) throws {
        try write { db in
            try db.execute(sql: "INSERT OR IGNORE INTO pin (itemID, pinboardID, addedAt) VALUES (?, ?, ?)",
                           arguments: [itemID, boardID, now.timeIntervalSince1970])
        }
    }

    public func unpin(_ itemID: Int64, from boardID: Int64) throws {
        try write { db in
            try db.execute(sql: "DELETE FROM pin WHERE itemID = ? AND pinboardID = ?", arguments: [itemID, boardID])
        }
    }

    // MARK: Tags

    public static func normalizeTag(_ raw: String) -> String? {
        let t = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "#"))
            .replacingOccurrences(of: " ", with: "-")
        return t.isEmpty ? nil : String(t.prefix(40))
    }

    public func setTags(_ itemID: Int64, _ tags: [String]) throws {
        let clean = Array(Set(tags.compactMap(Self.normalizeTag)))
        try write { db in
            try db.execute(sql: "DELETE FROM tag WHERE itemID = ?", arguments: [itemID])
            for t in clean {
                try db.execute(sql: "INSERT OR IGNORE INTO tag (itemID, name) VALUES (?, ?)", arguments: [itemID, t])
            }
            try Self.reindex(db, itemID)
        }
    }

    /// Re-runs sensitive detection over unflagged text items, e.g. after the detector learns new
    /// identifier types. Newly flagged items get the normal expiry from `now` (pinned items are kept).
    @discardableResult
    public func rescanSensitive(ttl: TimeInterval, now: Date = Date()) throws -> Int {
        let rows = try dbQueue.read { db in
            try Row.fetchAll(db, sql: """
            SELECT id, text FROM item WHERE isSensitive = 0 AND text IS NOT NULL
              AND kind IN ('text', 'richText', 'code', 'phone', 'email', 'link')
            """)
        }
        let hits: [(Int64, SensitiveDetector.Reason)] = rows.compactMap { r in
            guard let text: String = r["text"], let reason = SensitiveDetector.reason(for: text) else { return nil }
            return (r["id"], reason)
        }
        guard !hits.isEmpty else { return 0 }
        try write { db in
            for (id, reason) in hits {
                try db.execute(sql: """
                UPDATE item SET isSensitive = 1, sensitiveReason = ?, expiresAt = ?,
                                kind = CASE WHEN ? THEN 'text' ELSE kind END WHERE id = ?
                """, arguments: [reason.rawValue, now.timeIntervalSince1970 + ttl, reason.isIdentifier, id])
            }
        }
        return hits.count
    }

    // MARK: Retention

    /// Deletes expired sensitive items and unpinned items beyond the count or age limit.
    @discardableResult
    public func prune(_ policy: RetentionPolicy, now: Date = Date()) throws -> Int {
        let unpinned = "id NOT IN (SELECT itemID FROM pin)"
        let t = now.timeIntervalSince1970
        let cutoff = t - Double(policy.maxDays) * 86_400
        let rows = try dbQueue.read { db in
            try Row.fetchAll(db, sql: """
            SELECT id, uuid FROM item WHERE \(unpinned) AND (
                (expiresAt IS NOT NULL AND expiresAt <= ?)
                OR lastUsedAt < ?
                OR id NOT IN (SELECT id FROM item WHERE \(unpinned) ORDER BY lastUsedAt DESC LIMIT ?)
            )
            """, arguments: [t, cutoff, policy.maxItems])
        }
        guard !rows.isEmpty else { return 0 }
        try write { db in try Self.deleteRows(db, rows.map { $0["id"] }) }
        rows.forEach { removeBlobs($0["uuid"]) }
        return rows.count
    }

    // MARK: Blobs

    /// Deletes blob files whose item no longer exists (left behind by crashes, external edits, old builds).
    /// Files modified in the last minute are skipped so an in-flight capture isn't raced.
    @discardableResult
    public func sweepOrphanBlobs(now: Date = Date()) throws -> (files: Int, bytes: Int64) {
        let known = Set(try dbQueue.read { db in try String.fetchAll(db, sql: "SELECT uuid FROM item") })
        let fm = FileManager.default
        let urls = try fm.contentsOfDirectory(at: blobDir, includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey])
        var files = 0
        var bytes: Int64 = 0
        for url in urls {
            let uuid = String(url.lastPathComponent.prefix { $0 != "." })
            guard !known.contains(uuid) else { continue }
            let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey])
            if let mod = values?.contentModificationDate, now.timeIntervalSince(mod) < 60 { continue }
            if (try? fm.removeItem(at: url)) != nil {
                files += 1
                bytes += Int64(values?.fileSize ?? 0)
            }
        }
        return (files, bytes)
    }

    public func blobURL(_ uuid: String, _ ext: String) -> URL {
        blobDir.appendingPathComponent("\(uuid).\(ext)")
    }

    public func blob(_ item: ClipItem, _ ext: String) -> Data? {
        try? Data(contentsOf: blobURL(item.uuid, ext))
    }

    private func removeBlobs(_ uuid: String) {
        for ext in ["rtf", "html", "png", "link.png", "icon.png"] {
            try? FileManager.default.removeItem(at: blobURL(uuid, ext))
        }
    }

    // MARK: Helpers

    /// One write transaction followed by a single change notification.
    private func write(_ body: (Database) throws -> Void) throws {
        try dbQueue.write(body)
        onChange?()
    }

    private func uuid(of id: Int64) throws -> String? {
        try dbQueue.read { db in try String.fetchOne(db, sql: "SELECT uuid FROM item WHERE id = ?", arguments: [id]) }
    }

    private static func deleteRows(_ db: Database, _ ids: [Int64]) throws {
        for id in ids {
            try db.execute(sql: "DELETE FROM item WHERE id = ?", arguments: [id])
            try db.execute(sql: "DELETE FROM item_fts WHERE rowid = ?", arguments: [id])
        }
    }

    static func reindex(_ db: Database, _ id: Int64) throws {
        guard let r = try Row.fetchOne(db, sql: "SELECT text, title, ocrText, linkTitle, filePaths FROM item WHERE id = ?", arguments: [id]) else { return }
        let tags = try String.fetchAll(db, sql: "SELECT name FROM tag WHERE itemID = ?", arguments: [id])
        let paths = decodePaths(r["filePaths"]).map { ($0 as NSString).lastPathComponent }
        let fields: [String?] = [r["title"], r["text"], r["ocrText"], r["linkTitle"]]
        let body = (fields.compactMap { $0 } + paths + tags.map { "#" + $0 }).joined(separator: "\n")
        try db.execute(sql: "DELETE FROM item_fts WHERE rowid = ?", arguments: [id])
        try db.execute(sql: "INSERT INTO item_fts (rowid, body) VALUES (?, ?)", arguments: [id, body])
    }

    static func encodePaths(_ paths: [String]) -> String {
        (try? String(data: JSONEncoder().encode(paths), encoding: .utf8)) ?? "[]"
    }

    static func decodePaths(_ s: String?) -> [String] {
        guard let d = s?.data(using: .utf8) else { return [] }
        return (try? JSONDecoder().decode([String].self, from: d)) ?? []
    }

    static func item(from r: Row) -> ClipItem {
        func date(_ c: String) -> Date? { (r[c] as Double?).map(Date.init(timeIntervalSince1970:)) }
        return ClipItem(id: r["id"], uuid: r["uuid"],
                        kind: ContentKind(rawValue: r["kind"] ?? "") ?? .text,
                        text: r["text"], title: r["title"],
                        sourceBundleID: r["sourceBundleID"], sourceAppName: r["sourceAppName"],
                        createdAt: date("createdAt")!, lastUsedAt: date("lastUsedAt")!,
                        byteSize: r["byteSize"] ?? 0,
                        imageWidth: r["imageWidth"] ?? 0, imageHeight: r["imageHeight"] ?? 0,
                        isSensitive: r["isSensitive"] ?? false, sensitiveReason: r["sensitiveReason"],
                        expiresAt: date("expiresAt"), contentHash: r["contentHash"],
                        hasRTF: r["hasRTF"] ?? false, hasHTML: r["hasHTML"] ?? false, hasImage: r["hasImage"] ?? false,
                        filePaths: decodePaths(r["filePaths"]),
                        ocrText: r["ocrText"], linkTitle: r["linkTitle"],
                        hasLinkImage: r["hasLinkImage"] ?? false, hasLinkIcon: r["hasLinkIcon"] ?? false,
                        linkFetched: r["linkFetched"] ?? false)
    }
}
