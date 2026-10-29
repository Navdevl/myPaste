import AppKit
import MyPasteCore
import Combine
import KeyboardShortcuts

/// Global shortcuts; KeyboardShortcuts persists user changes in UserDefaults.
extension KeyboardShortcuts.Name {
    static let openPanel = Self("openPanel", default: .init(.v, modifiers: [.command, .shift]))
    static let pasteStack = Self("pasteStack", default: .init(.c, modifiers: [.command, .shift]))
}

/// User settings, persisted in UserDefaults.
final class Preferences: ObservableObject {
    static let shared = Preferences()
    private let d = UserDefaults.standard

    /// Password managers and keychain tools: never record what they put on the clipboard.
    static let defaultExcluded = [
        "com.1password.1password", "com.agilebits.onepassword7", "com.agilebits.onepassword-osx",
        "com.bitwarden.desktop", "com.apple.Passwords", "com.apple.keychainaccess",
        "com.lastpass.LastPass", "com.dashlane.dashlanephonefinal", "org.keepassxc.keepassxc",
    ]

    @Published var maxItems: Int { didSet { d.set(maxItems, forKey: "maxItems") } }
    @Published var maxDays: Int { didSet { d.set(maxDays, forKey: "maxDays") } }
    @Published var sensitiveMinutes: Int { didSet { d.set(sensitiveMinutes, forKey: "sensitiveMinutes") } }
    @Published var excludedBundleIDs: [String] { didSet { d.set(excludedBundleIDs, forKey: "excludedBundleIDs") } }
    @Published var linkPreviews: Bool { didSet { d.set(linkPreviews, forKey: "linkPreviews") } }
    @Published var ocr: Bool { didSet { d.set(ocr, forKey: "ocr") } }
    @Published var directPaste: Bool { didSet { d.set(directPaste, forKey: "directPaste") } }
    @Published var capturePaused: Bool { didSet { d.set(capturePaused, forKey: "capturePaused") } }
    @Published var smartActions: Bool { didSet { d.set(smartActions, forKey: "smartActions") } }
    @Published var jiraBaseURL: String { didSet { d.set(jiraBaseURL, forKey: "jiraBaseURL") } }

    var retention: RetentionPolicy { RetentionPolicy(maxItems: maxItems, maxDays: maxDays) }
    var sensitiveTTL: TimeInterval { TimeInterval(sensitiveMinutes * 60) }

    private init() {
        d.register(defaults: [
            "maxItems": 1000, "maxDays": 30, "sensitiveMinutes": 10,
            "excludedBundleIDs": Self.defaultExcluded,
            "linkPreviews": true, "ocr": true, "directPaste": true, "capturePaused": false,
            "smartActions": true, "jiraBaseURL": "https://example.atlassian.net",
        ])
        maxItems = d.integer(forKey: "maxItems")
        maxDays = d.integer(forKey: "maxDays")
        sensitiveMinutes = d.integer(forKey: "sensitiveMinutes")
        excludedBundleIDs = d.stringArray(forKey: "excludedBundleIDs") ?? Self.defaultExcluded
        linkPreviews = d.bool(forKey: "linkPreviews")
        ocr = d.bool(forKey: "ocr")
        directPaste = d.bool(forKey: "directPaste")
        capturePaused = d.bool(forKey: "capturePaused")
        smartActions = d.bool(forKey: "smartActions")
        jiraBaseURL = d.string(forKey: "jiraBaseURL") ?? ""
    }
}
