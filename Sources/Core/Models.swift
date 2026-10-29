import Foundation

public struct ClipItem: Identifiable, Hashable {
    public var id: Int64
    public var uuid: String
    public var kind: ContentKind
    public var text: String?
    public var title: String?
    public var sourceBundleID: String?
    public var sourceAppName: String?
    public var createdAt: Date
    public var lastUsedAt: Date
    public var byteSize: Int64
    public var imageWidth: Int
    public var imageHeight: Int
    public var isSensitive: Bool
    public var sensitiveReason: String?
    public var expiresAt: Date?
    public var contentHash: String
    public var hasRTF: Bool
    public var hasHTML: Bool
    public var hasImage: Bool
    public var filePaths: [String]
    public var ocrText: String?
    public var linkTitle: String?
    public var hasLinkImage: Bool
    public var hasLinkIcon: Bool
    public var linkFetched: Bool
    public var pinboardIDs: [Int64] = []
    public var tags: [String] = []

    public var isPinned: Bool { !pinboardIDs.isEmpty }
    public var charCount: Int { text?.count ?? 0 }

    /// Title shown on the card: custom name, link title, or nil (preview speaks for itself).
    public var displayTitle: String? { title ?? (kind == .link ? linkTitle : nil) }
}

public struct Pinboard: Identifiable, Hashable {
    public var id: Int64
    public var name: String
    public var colorHex: String
    public var position: Int
}

/// Everything captured from one pasteboard change, ready to persist.
public struct NewCapture {
    public var kind: ContentKind
    public var text: String?
    public var rtf: Data?
    public var html: Data?
    public var imagePNG: Data?
    public var imageWidth: Int
    public var imageHeight: Int
    public var filePaths: [String]
    public var sourceBundleID: String?
    public var sourceAppName: String?
    public var contentHash: String
    public var sensitiveReason: String?

    public init(kind: ContentKind, text: String?, rtf: Data? = nil, html: Data? = nil, imagePNG: Data? = nil,
                imageWidth: Int = 0, imageHeight: Int = 0, filePaths: [String] = [],
                sourceBundleID: String? = nil, sourceAppName: String? = nil,
                contentHash: String, sensitiveReason: String? = nil) {
        self.kind = kind
        self.text = text
        self.rtf = rtf
        self.html = html
        self.imagePNG = imagePNG
        self.imageWidth = imageWidth
        self.imageHeight = imageHeight
        self.filePaths = filePaths
        self.sourceBundleID = sourceBundleID
        self.sourceAppName = sourceAppName
        self.contentHash = contentHash
        self.sensitiveReason = sensitiveReason
    }
}

public struct RetentionPolicy {
    public var maxItems: Int
    public var maxDays: Int
    public init(maxItems: Int, maxDays: Int) {
        self.maxItems = maxItems
        self.maxDays = maxDays
    }
}
