import AppKit

/// Test seams for `make uitest`, active only when MYPASTE_UITEST=1. They replace things a test can't
/// drive or must not trigger: system file panels, launching the browser, first-run onboarding.
enum UITest {
    static let enabled = ProcessInfo.processInfo.environment["MYPASTE_UITEST"] == "1"
    static var saveURL: URL? { url("MYPASTE_UITEST_SAVE") }
    static var openURL: URL? { url("MYPASTE_UITEST_OPEN") }
    static var maccyStore: URL? { url("MYPASTE_UITEST_MACCY") }
    static var soundFile: URL? { url("MYPASTE_UITEST_SOUNDFILE") }

    private static func url(_ key: String) -> URL? {
        guard enabled, let path = ProcessInfo.processInfo.environment[key] else { return nil }
        return URL(fileURLWithPath: path)
    }

    /// Instead of opening a browser, tell the harness which URL would have opened.
    static func reportOpened(_ url: URL) {
        DistributedNotificationCenter.default().postNotificationName(
            .init("local.mypaste.uitest.opened"), object: url.absoluteString, userInfo: nil, deliverImmediately: true)
    }
}

/// Lets the harness (and later, deep links) pick the Settings pane.
final class SettingsRouter: ObservableObject {
    static let shared = SettingsRouter()
    @Published var pane: SettingsView.Pane = .general
}

/// Where myPaste keeps its settings. UI tests get a separate, freshly wiped domain so a test run
/// (which flips switches in Settings) never changes the user's real preferences.
enum AppDefaults {
    static let uiTestSuite = "local.mypaste.uitest"

    static let store: UserDefaults = {
        guard UITest.enabled, let suite = UserDefaults(suiteName: uiTestSuite) else { return .standard }
        suite.removePersistentDomain(forName: uiTestSuite)
        suite.set(true, forKey: "didOnboard")
        return suite
    }()
}
