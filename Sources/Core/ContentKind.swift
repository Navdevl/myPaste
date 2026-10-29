import Foundation

/// What a clipboard item is, as shown on its card and used by the filter chips.
public enum ContentKind: String, CaseIterable, Codable, Sendable {
    case text
    case richText
    case link
    case image
    case file
    case code
    case color
    case email
    case phone

    public var label: String {
        switch self {
        case .text: return "Text"
        case .richText: return "Rich Text"
        case .link: return "Link"
        case .image: return "Image"
        case .file: return "File"
        case .code: return "Code"
        case .color: return "Color"
        case .email: return "Email"
        case .phone: return "Phone"
        }
    }

    public var symbol: String {
        switch self {
        case .text: return "text.alignleft"
        case .richText: return "textformat"
        case .link: return "link"
        case .image: return "photo"
        case .file: return "doc"
        case .code: return "chevron.left.forwardslash.chevron.right"
        case .color: return "paintpalette"
        case .email: return "envelope"
        case .phone: return "phone"
        }
    }
}

/// Filter chip selection. `sensitive` is a flag rather than a kind, so it gets its own case.
public enum KindFilter: Hashable, Sendable {
    case all
    case kind(ContentKind)
    case sensitive
}
