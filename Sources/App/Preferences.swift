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
    private let d = AppDefaults.store

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
    // Appearance & motion (all on by default; all off = the 1.1 behaviour)
    @Published var glideSelection: Bool { didSet { d.set(glideSelection, forKey: "glideSelection") } }
    @Published var sweepSelection: Bool { didSet { d.set(sweepSelection, forKey: "sweepSelection") } }
    @Published var parallax: Bool { didSet { d.set(parallax, forKey: "parallax") } }
    @Published var haptics: Bool { didSet { d.set(haptics, forKey: "haptics") } }
    @Published var doubleCtrlInPanel: Bool { didSet { d.set(doubleCtrlInPanel, forKey: "doubleCtrlInPanel") } }
    @Published var doubleCtrlGlobal: Bool { didSet { d.set(doubleCtrlGlobal, forKey: "doubleCtrlGlobal") } }
    @Published var hotkeyCyclesTabs: Bool { didSet { d.set(hotkeyCyclesTabs, forKey: "hotkeyCyclesTabs") } }
    /// Off by default: ⇧⌘C stays free for other apps until you opt in.
    @Published var pasteStackEnabled: Bool { didSet { d.set(pasteStackEnabled, forKey: "pasteStackEnabled") } }
    @Published var soundsEnabled: Bool { didSet { d.set(soundsEnabled, forKey: "soundsEnabled") } }
    @Published var soundVolume: Double { didSet { d.set(soundVolume, forKey: "soundVolume") } }
    @Published var soundCopy: Bool { didSet { d.set(soundCopy, forKey: "soundCopy") } }
    @Published var soundPaste: Bool { didSet { d.set(soundPaste, forKey: "soundPaste") } }
    @Published var soundDelete: Bool { didSet { d.set(soundDelete, forKey: "soundDelete") } }

    var retention: RetentionPolicy { RetentionPolicy(maxItems: maxItems, maxDays: maxDays) }
    var sensitiveTTL: TimeInterval { TimeInterval(sensitiveMinutes * 60) }

    private init() {
        d.register(defaults: [
            "maxItems": 1000, "maxDays": 30, "sensitiveMinutes": 10,
            "excludedBundleIDs": Self.defaultExcluded,
            "linkPreviews": true, "ocr": true, "directPaste": true, "capturePaused": false,
            "smartActions": true, "jiraBaseURL": "https://example.atlassian.net",
            "glideSelection": true, "sweepSelection": true, "parallax": true, "haptics": true,
            "doubleCtrlInPanel": true, "doubleCtrlGlobal": true, "hotkeyCyclesTabs": true, "pasteStackEnabled": false,
            // UI test runs stay silent; everyone else gets sounds at 40%.
            "soundsEnabled": !UITest.enabled, "soundVolume": 0.4, "soundCopy": true, "soundPaste": true, "soundDelete": true,
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
        glideSelection = d.bool(forKey: "glideSelection")
        sweepSelection = d.bool(forKey: "sweepSelection")
        parallax = d.bool(forKey: "parallax")
        haptics = d.bool(forKey: "haptics")
        doubleCtrlInPanel = d.bool(forKey: "doubleCtrlInPanel")
        doubleCtrlGlobal = d.bool(forKey: "doubleCtrlGlobal")
        hotkeyCyclesTabs = d.bool(forKey: "hotkeyCyclesTabs")
        pasteStackEnabled = d.bool(forKey: "pasteStackEnabled")
        soundsEnabled = d.bool(forKey: "soundsEnabled")
        soundVolume = d.double(forKey: "soundVolume")
        soundCopy = d.bool(forKey: "soundCopy")
        soundPaste = d.bool(forKey: "soundPaste")
        soundDelete = d.bool(forKey: "soundDelete")
    }
}
