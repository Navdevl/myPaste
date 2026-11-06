import AppKit
import MyPasteCore
import Combine
import KeyboardShortcuts

/// Global shortcuts; KeyboardShortcuts persists user changes in UserDefaults.
extension KeyboardShortcuts.Name {
    /// UI test runs use their own key so they never read (or depend on) the shortcut you recorded.
    static let openPanel = Self(UITest.enabled ? "openPanelUITest" : "openPanel", default: .init(.c, modifiers: [.command, .shift]))
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
    // Appearance & motion
    @Published var glideSelection: Bool { didSet { d.set(glideSelection, forKey: "glideSelection") } }
    @Published var haptics: Bool { didSet { d.set(haptics, forKey: "haptics") } }
    /// Off by default: opening is instant. On: the first cards spring in one after another (~0.5 s).
    @Published var entranceAnimation: Bool { didSet { d.set(entranceAnimation, forKey: "entranceAnimation") } }
    @Published var doubleCtrlInPanel: Bool { didSet { d.set(doubleCtrlInPanel, forKey: "doubleCtrlInPanel") } }
    @Published var doubleCtrlGlobal: Bool { didSet { d.set(doubleCtrlGlobal, forKey: "doubleCtrlGlobal") } }
    @Published var hotkeyCyclesTabs: Bool { didSet { d.set(hotkeyCyclesTabs, forKey: "hotkeyCyclesTabs") } }
    /// On: typing a search looks through History and every pinboard, whichever tab is open.
    @Published var searchEverywhere: Bool { didSet { d.set(searchEverywhere, forKey: "searchEverywhere") } }
    @Published var soundsEnabled: Bool { didSet { d.set(soundsEnabled, forKey: "soundsEnabled") } }
    @Published var soundVolume: Double { didSet { d.set(soundVolume, forKey: "soundVolume") } }
    @Published var soundCopy: Bool { didSet { d.set(soundCopy, forKey: "soundCopy") } }
    @Published var soundPaste: Bool { didSet { d.set(soundPaste, forKey: "soundPaste") } }
    @Published var soundDelete: Bool { didSet { d.set(soundDelete, forKey: "soundDelete") } }
    @Published var soundCopyChoice: String { didSet { d.set(soundCopyChoice, forKey: "soundCopyChoice") } }
    @Published var soundPasteChoice: String { didSet { d.set(soundPasteChoice, forKey: "soundPasteChoice") } }
    @Published var soundDeleteChoice: String { didSet { d.set(soundDeleteChoice, forKey: "soundDeleteChoice") } }

    var retention: RetentionPolicy { RetentionPolicy(maxItems: maxItems, maxDays: maxDays) }
    var sensitiveTTL: TimeInterval { TimeInterval(sensitiveMinutes * 60) }

    private init() {
        d.register(defaults: [
            "maxItems": 1000, "maxDays": 30, "sensitiveMinutes": 10,
            "excludedBundleIDs": Self.defaultExcluded,
            "linkPreviews": true, "ocr": true, "directPaste": true, "capturePaused": false,
            "smartActions": true,
            "glideSelection": true, "haptics": true, "entranceAnimation": false,
            "doubleCtrlInPanel": true, "doubleCtrlGlobal": true, "hotkeyCyclesTabs": true, "searchEverywhere": true,
            // UI test runs stay silent; everyone else gets sounds at 40%.
            "soundsEnabled": !UITest.enabled, "soundVolume": 0.4, "soundCopy": true, "soundPaste": true, "soundDelete": true,
            "soundCopyChoice": "paper-snap", "soundPasteChoice": "soft-thud", "soundDeleteChoice": "whoosh",
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
        glideSelection = d.bool(forKey: "glideSelection")
        haptics = d.bool(forKey: "haptics")
        entranceAnimation = d.bool(forKey: "entranceAnimation")
        doubleCtrlInPanel = d.bool(forKey: "doubleCtrlInPanel")
        doubleCtrlGlobal = d.bool(forKey: "doubleCtrlGlobal")
        hotkeyCyclesTabs = d.bool(forKey: "hotkeyCyclesTabs")
        searchEverywhere = d.bool(forKey: "searchEverywhere")
        soundsEnabled = d.bool(forKey: "soundsEnabled")
        soundVolume = d.double(forKey: "soundVolume")
        soundCopy = d.bool(forKey: "soundCopy")
        soundPaste = d.bool(forKey: "soundPaste")
        soundDelete = d.bool(forKey: "soundDelete")
        soundCopyChoice = d.string(forKey: "soundCopyChoice") ?? "paper-snap"
        soundPasteChoice = d.string(forKey: "soundPasteChoice") ?? "soft-thud"
        soundDeleteChoice = d.string(forKey: "soundDeleteChoice") ?? "whoosh"
    }
}
