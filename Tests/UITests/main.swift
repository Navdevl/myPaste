import AppKit
import ApplicationServices
import MyPasteCore

// UI tests for myPaste, driven through the Accessibility API and synthetic key events.
// Runs the real app bundle against a throwaway data folder; `make uitest` quits and relaunches the
// installed copy around it. The terminal running this needs Accessibility permission (it already
// does if `make uitest` can type into apps).
//
// Usage: myPasteUITests <path/to/myPaste.app> [<path/to/FakeMaccy.app>]

setvbuf(stdout, nil, _IONBF, 0)
let args = CommandLine.arguments
guard args.count >= 2 else { print("usage: myPasteUITests <myPaste.app> [FakeMaccy.app]"); exit(2) }
let appBundle = URL(fileURLWithPath: args[1])
let fakeMaccy = args.count > 2 ? URL(fileURLWithPath: args[2]) : nil
let work = FileManager.default.temporaryDirectory.appendingPathComponent("mypaste-uitest-\(UUID().uuidString)")
let dataDir = work.appendingPathComponent("data")
let exportURL = work.appendingPathComponent("export.mypaste")
let maccyStore = work.appendingPathComponent("maccy/Storage.sqlite")

/// A tiny store with Maccy 2.x's schema (two pins, one unpinned) built with the sqlite3 CLI.
func makeFakeMaccyStore() throws {
    try FileManager.default.createDirectory(at: maccyStore.deletingLastPathComponent(), withIntermediateDirectories: true)
    let sql = """
    CREATE TABLE ZHISTORYITEM (Z_PK INTEGER PRIMARY KEY, Z_ENT INTEGER, Z_OPT INTEGER, ZNUMBEROFCOPIES INTEGER, ZFIRSTCOPIEDAT TIMESTAMP, ZLASTCOPIEDAT TIMESTAMP, ZAPPLICATION VARCHAR, ZPIN VARCHAR, ZTITLE VARCHAR);
    CREATE TABLE ZHISTORYITEMCONTENT (Z_PK INTEGER PRIMARY KEY, Z_ENT INTEGER, Z_OPT INTEGER, ZITEM INTEGER, ZTYPE VARCHAR, ZVALUE BLOB);
    INSERT INTO ZHISTORYITEM VALUES (1,1,1,1,799926848,799926848,'com.apple.Notes','b','a');
    INSERT INTO ZHISTORYITEM VALUES (2,1,1,1,799926848,799926848,'com.apple.Notes','o','b');
    INSERT INTO ZHISTORYITEM VALUES (3,1,1,1,799926848,799926848,'com.apple.Notes',NULL,'c');
    INSERT INTO ZHISTORYITEMCONTENT VALUES (1,2,1,1,'public.utf8-plain-text',CAST('[uitest] maccy pin one' AS BLOB));
    INSERT INTO ZHISTORYITEMCONTENT VALUES (2,2,1,2,'public.utf8-plain-text',CAST('[uitest] maccy pin two' AS BLOB));
    INSERT INTO ZHISTORYITEMCONTENT VALUES (3,2,1,3,'public.utf8-plain-text',CAST('[uitest] maccy unpinned' AS BLOB));
    """
    let p = Process()
    p.executableURL = URL(fileURLWithPath: "/usr/bin/sqlite3")
    p.arguments = [maccyStore.path, sql]
    try p.run(); p.waitUntilExit()
}

// MARK: Tiny test framework

var failures: [String] = []
var passed = 0

func check(_ ok: Bool, _ what: String, line: Int = #line) {
    if ok { passed += 1 } else { failures.append("line \(line): \(what)"); print("    ✘ \(what)") }
}

func test(_ name: String, _ body: () async throws -> Void) async {
    print("▸ \(name)")
    let before = failures.count
    do { try await body() } catch { failures.append("\(name): threw \(error)"); print("    ✘ threw \(error)") }
    if failures.count == before { print("    ✔") }
}

func sleep(_ s: Double) async { try? await Task.sleep(nanoseconds: UInt64(s * 1_000_000_000)) }

/// Polls until `cond` holds or `timeout` passes.
@discardableResult
func waitFor(_ timeout: Double = 5, _ cond: () -> Bool) async -> Bool {
    let end = Date().addingTimeInterval(timeout)
    while Date() < end { if cond() { return true }; await sleep(0.1) }
    return cond()
}

// MARK: Accessibility helpers

struct AX {
    let element: AXUIElement

    func attr<T>(_ name: String) -> T? {
        var v: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &v) == .success else { return nil }
        return v as? T
    }

    var identifier: String? { attr(kAXIdentifierAttribute) }
    var role: String? { attr(kAXRoleAttribute) }
    var value: String? { attr(kAXValueAttribute) }
    var title: String? { attr(kAXTitleAttribute) }
    var description: String? { attr(kAXDescriptionAttribute) }
    var children: [AX] { ((attr(kAXChildrenAttribute) as [AXUIElement]?) ?? []).map(AX.init) }
    var windows: [AX] { ((attr(kAXWindowsAttribute) as [AXUIElement]?) ?? []).map(AX.init) }

    func press() -> Bool { AXUIElementPerformAction(element, kAXPressAction as CFString) == .success }

    /// Depth-first search; bounded so a huge tree can't hang the run.
    func find(_ id: String, depth: Int = 0, budget: inout Int) -> AX? {
        budget -= 1
        guard budget > 0, depth < 40 else { return nil }
        if identifier == id { return self }
        for c in children { if let hit = c.find(id, depth: depth + 1, budget: &budget) { return hit } }
        return nil
    }

    func findAll(_ id: String, depth: Int = 0, into out: inout [AX], budget: inout Int) {
        budget -= 1
        guard budget > 0, depth < 40 else { return }
        if identifier == id { out.append(self) }
        for c in children { c.findAll(id, depth: depth + 1, into: &out, budget: &budget) }
    }
}

var appPID: pid_t = 0
var app: AX { AX(element: AXUIElementCreateApplication(appPID)) }

func element(_ id: String, timeout: Double = 5) async -> AX? {
    var hit: AX?
    await waitFor(timeout) {
        for w in app.windows {
            var budget = 6000
            if let e = w.find(id, budget: &budget) { hit = e; return true }
        }
        return false
    }
    return hit
}

func elements(_ id: String) -> [AX] {
    var out: [AX] = []
    for w in app.windows { var budget = 6000; w.findAll(id, into: &out, budget: &budget) }
    return out
}

/// Debug aid: identifiers and roles currently exposed by the app's windows.
func dumpIDs() {
    for w in app.windows {
        var stack = [(w, 0)]
        var n = 0
        while let (e, d) = stack.popLast(), n < 4000 {
            n += 1
            if let id = e.identifier, !id.isEmpty, !id.hasPrefix("_NS") { print("      [\(e.role ?? "?")] \(id) \(text(of: e).prefix(40))") }
            if d < 40 { stack.append(contentsOf: e.children.map { ($0, d + 1) }) }
        }
    }
}

/// Visible text of an element: SwiftUI exposes Text as AXStaticText with the string in value or description.
func text(of e: AX) -> String { e.value ?? e.title ?? e.description ?? "" }

// MARK: Input helpers

let src = CGEventSource(stateID: .hidSystemState)

func key(_ code: CGKeyCode, _ flags: CGEventFlags = []) async {
    let down = CGEvent(keyboardEventSource: src, virtualKey: code, keyDown: true)
    let up = CGEvent(keyboardEventSource: src, virtualKey: code, keyDown: false)
    down?.flags = flags
    up?.flags = flags
    down?.post(tap: .cghidEventTap)
    up?.post(tap: .cghidEventTap)
    await sleep(0.15)
}

/// Holds ⌘ or ⇧ for `seconds`, runs `body`, then releases. Uses System Events: synthetic CGEvents from a
/// .hidSystemState source get their modifier flags overwritten by the real (unpressed) keyboard state.
@MainActor
func hold(_ modifier: String, for seconds: Double, while body: () async -> Void) async {
    func se(_ cmd: String) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        p.arguments = ["-e", "tell application \"System Events\" to \(cmd)"]
        try? p.run(); p.waitUntilExit()
    }
    se("key down \(modifier)")
    await sleep(seconds)
    await body()
    se("key up \(modifier)")
    await sleep(0.3)
}

enum K {
    static let ret: CGKeyCode = 36, esc: CGKeyCode = 53, space: CGKeyCode = 49, right: CGKeyCode = 124
    static let delete: CGKeyCode = 51, two: CGKeyCode = 19, j: CGKeyCode = 38, k: CGKeyCode = 40, z: CGKeyCode = 6, o: CGKeyCode = 31
}

func post(_ name: String, _ object: String? = nil) {
    DistributedNotificationCenter.default().postNotificationName(.init(name), object: object, userInfo: nil, deliverImmediately: true)
}

@MainActor
func copy(_ s: String) async {
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(s, forType: .string)
    await sleep(0.7) // app polls every 0.35 s
}

@MainActor
func openPanel() async -> Bool {
    post("local.mypaste.toggle")
    return await element("strip", timeout: 3) != nil
}

@MainActor
func closePanel() async {
    await key(K.esc)
    await key(K.esc)
    await sleep(0.3)
}

// MARK: Paste target: our own window with a text view

let nsApp = NSApplication.shared
nsApp.setActivationPolicy(.regular)
let window = NSWindow(contentRect: NSRect(x: 200, y: 300, width: 520, height: 260), styleMask: [.titled], backing: .buffered, defer: false)
window.title = "myPaste UI test target"
// ⌘V reaches a text view through the Edit menu's key equivalent; without a main menu it goes nowhere.
let mainMenu = NSMenu()
let editItem = NSMenuItem()
editItem.submenu = NSMenu(title: "Edit")
editItem.submenu?.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
editItem.submenu?.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
mainMenu.addItem(NSMenuItem())
mainMenu.addItem(editItem)
nsApp.mainMenu = mainMenu
let textView = NSTextView(frame: window.contentLayoutRect)
textView.isRichText = false
window.contentView = textView

@MainActor
func focusTarget() async {
    textView.string = ""
    nsApp.activate(ignoringOtherApps: true)
    window.makeKeyAndOrderFront(nil)
    window.makeFirstResponder(textView)
    await sleep(0.4)
}

var openedURLs: [String] = []
DistributedNotificationCenter.default().addObserver(forName: .init("local.mypaste.uitest.opened"), object: nil, queue: .main) { n in
    if let s = n.object as? String { openedURLs.append(s) }
}

// MARK: Tests

/// Everything runs on the main actor: the paste target is an NSTextView, and touching it from a background
/// task deadlocked against AppKit layout.
@MainActor
func runAll() async {
    guard AXIsProcessTrusted() else {
        print("✘ This terminal needs Accessibility permission (System Settings → Privacy & Security → Accessibility).")
        exit(2)
    }
    try? FileManager.default.createDirectory(at: dataDir, withIntermediateDirectories: true)
    try? makeFakeMaccyStore()
    let savedClipboard = NSPasteboard.general.string(forType: .string)

    let config = NSWorkspace.OpenConfiguration()
    config.environment = ["MYPASTE_UITEST": "1", "MYPASTE_DATA_DIR": dataDir.path,
                          "MYPASTE_UITEST_SAVE": exportURL.path, "MYPASTE_UITEST_OPEN": exportURL.path,
                          "MYPASTE_UITEST_MACCY": maccyStore.path,
                          "MYPASTE_UITEST_SOUNDFILE": appBundle.appendingPathComponent("Contents/Resources/Sounds/chime.wav").path]
    config.arguments = [] // the app uses a wiped "local.mypaste.uitest" defaults domain in test mode
    config.createsNewApplicationInstance = true
    config.activates = false
    guard let launched = try? await NSWorkspace.shared.openApplication(at: appBundle, configuration: config) else {
        print("✘ could not launch \(appBundle.path)"); exit(2)
    }
    appPID = launched.processIdentifier
    await sleep(2.5)
    let store = try! ClipStore(directory: dataDir)
    func items() -> [ClipItem] { (try? store.allItems()) ?? [] }

    await test("captures a copy into history") {
        await copy("[uitest] hello capture")
        check(await waitFor { items().contains { $0.text == "[uitest] hello capture" } }, "copied text appears in the store")
    }

    await test("panel opens and ⌘2 pastes the second item into the frontmost app") {
        await copy("[uitest] first")
        await copy("[uitest] second")
        await focusTarget()
        check(await openPanel(), "strip is visible")
        await key(K.two, .maskCommand)
        check(await waitFor { textView.string == "[uitest] first" }, "⌘2 pasted the older item (got \"\(textView.string)\")")
    }

    await test("⌘K pretty-prints JSON and ↩ pastes the result") {
        await copy("{\"merchant\":\"demo\",\"amount\":100}")
        await focusTarget()
        check(await openPanel(), "strip is visible")
        await key(K.k, .maskCommand)
        await sleep(0.6)
        await key(K.ret)
        check(await waitFor { textView.string.contains("\"merchant\" : \"demo\"") && textView.string.contains("\n") },
              "pretty JSON pasted (got \"\(textView.string.prefix(60))\")")
    }

    await test("smart chip: ⌘J opens the Jira key") {
        openedURLs.removeAll()
        await copy("[uitest] please look at ABC-1234 today")
        check(await openPanel(), "strip is visible")
        await key(K.j, .maskCommand)
        check(await waitFor { openedURLs.contains("https://example.atlassian.net/browse/ABC-1234") }, "Jira URL opened (got \(openedURLs))")
    }

    await test("smart chip button is pressable via accessibility") {
        openedURLs.removeAll()
        await copy("https://github.com/swiftlang/swift/pull/123")
        check(await openPanel(), "strip is visible")
        guard let chip = elements("card.chip").first else { check(false, "chip found"); return }
        check(chip.press(), "chip pressed")
        check(await waitFor { openedURLs.contains("https://github.com/swiftlang/swift/pull/123") }, "PR URL opened (got \(openedURLs))")
    }

    await test("⌘O opens a link card") {
        openedURLs.removeAll()
        await copy("https://example.com/pricing")
        check(await openPanel(), "strip is visible")
        await key(K.o, .maskCommand)
        check(await waitFor { openedURLs.contains("https://example.com/pricing") }, "link opened (got \(openedURLs))")
    }

    await test("hold ⌘ shows the shortcut bar, release hides it") {
        check(await openPanel(), "strip is visible")
        await hold("command", for: 0.9) {
            let bar = await element("shortcut.bar", timeout: 1.5)
            check(bar != nil, "shortcut bar visible while ⌘ held")
            if bar == nil { dumpIDs() }
        }
        check(elements("shortcut.bar").isEmpty, "shortcut bar gone after release")
        await closePanel()
    }

    await test("⌘⇧⌫ deletes and ⌘Z restores within the undo window") {
        await copy("[uitest] delete me")
        check(await openPanel(), "strip is visible")
        await key(K.delete, [.maskCommand, .maskShift])
        let toast = await element("toast", timeout: 2)
        check(toast != nil, "undo toast shown")
        if toast == nil { dumpIDs() }
        await key(K.z, .maskCommand)
        await closePanel()
        await sleep(11) // past the 10 s undo window: a restored item must survive the commit
        check(items().contains { $0.text == "[uitest] delete me" }, "restored item still on disk")
    }

    await test("Quick Look Reveal shows a masked identifier in full") {
        await copy("ABCPE1234F") // synthetic PAN shape
        check(await openPanel(), "strip is visible")
        await key(K.space)
        guard let masked = await element("ql.masked", timeout: 3) else { check(false, "masked value shown"); return }
        check(text(of: masked).contains("XXXXX1234F"), "masked preview (got \"\(text(of: masked))\")")
        guard let reveal = await element("ql.reveal") else { check(false, "Reveal button found"); return }
        check(reveal.press(), "Reveal pressed")
        guard let full = await element("ql.text", timeout: 3) else { check(false, "revealed text shown"); return }
        check(text(of: full) == "ABCPE1234F", "full value after reveal (got \"\(text(of: full))\")")
        await key(K.space)
        await closePanel()
    }

    /// The tab whose accessibility value is "active".
    func activeTab() -> String? {
        for id in ["tab.History"] + ((try? store.pinboards()) ?? []).map({ "tab.\($0.name)" }) {
            if elements(id).contains(where: { $0.value == "active" }) { return String(id.dropFirst(4)) }
        }
        return nil
    }

    func systemEvents(_ commands: [String]) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        p.arguments = commands.flatMap { ["-e", "tell application \"System Events\" to \($0)"] }
        try? p.run(); p.waitUntilExit()
    }

    /// Two quick ⌃ taps in one osascript run (separate runs are too slow for the 0.35 s window).
    func doubleControl() async {
        systemEvents(["key down control", "key up control", "key down control", "key up control"])
        await sleep(0.6)
    }

    await test("boards: ⌘P creates one; ⇧⌘V again and ⌃Tab cycle tabs; hold ⌥ shows numbers") {
        await copy("[uitest] board cycling")
        check(await openPanel(), "strip is visible")
        await key(35, .maskCommand) // ⌘P → pins to a new "Pinned" board
        check(await waitFor { (try? store.pinboards().map(\.name))?.contains("Pinned") == true }, "⌘P created the Pinned board")
        check(await waitFor(2) { activeTab() == "History" }, "starts on History (got \(activeTab() ?? "nil"))")
        await key(9, [.maskCommand, .maskShift]) // ⇧⌘V while open → next tab
        check(await waitFor(2) { activeTab() == "Pinned" }, "⇧⌘V moved to Pinned (got \(activeTab() ?? "nil"))")
        await key(48, .maskControl) // ⌃Tab → wraps to History
        check(await waitFor(2) { activeTab() == "History" }, "⌃Tab wrapped to History (got \(activeTab() ?? "nil"))")
        await key(48, [.maskControl, .maskShift])
        check(await waitFor(2) { activeTab() == "Pinned" }, "⌃⇧Tab went back to Pinned (got \(activeTab() ?? "nil"))")
        systemEvents(["key down option"])
        await sleep(0.9)
        let labels = elements("tab.History").map { [text(of: $0), $0.title ?? "", $0.description ?? ""].joined(separator: " ") }
        check(labels.contains { $0.contains("⌥0") }, "⌥ held shows tab numbers (History label: \(labels))")
        systemEvents(["key up option"])
        await sleep(0.4)
        check(!elements("tab.History").contains { text(of: $0).contains("⌥") || ($0.description ?? "").contains("⌥") }, "numbers hidden after ⌥ released")
        await closePanel()
    }

    await test("double-⌃ in the strip opens the pin picker; 1 pins to the first board") {
        await copy("[uitest] quick pin in strip")
        check(await openPanel(), "strip is visible")
        await key(29, .maskAlternate) // ⌥0 → History (the strip remembers the last tab)
        check(await waitFor(2) { activeTab() == "History" }, "⌥0 jumped to History")
        await doubleControl()
        check(await element("pinpicker", timeout: 2) != nil, "pin picker shown")
        await sleep(0.3)
        await key(18) // "1"
        let pinned = await waitFor {
            items().first { $0.text == "[uitest] quick pin in strip" }?.isPinned == true
        }
        check(pinned, "item pinned to board 1")
        await closePanel()
    }

    await test("double-⌃ anywhere opens the global picker; typing a new name creates and pins") {
        await copy("[uitest] quick pin global")
        await focusTarget()
        await doubleControl()
        guard await element("pinpicker", timeout: 3) != nil else { check(false, "global pin picker shown"); return }
        systemEvents(["keystroke \"UITest Global\""])
        await key(K.ret)
        let ok = await waitFor {
            guard let board = (try? store.pinboards())?.first(where: { $0.name == "UITest Global" }) else { return false }
            return items().first { $0.text == "[uitest] quick pin global" }?.pinboardIDs.contains(board.id) == true
        }
        check(ok, "new board created and latest item pinned to it")
        check(await waitFor(2) { elements("pinpicker").isEmpty }, "picker closed")
    }

    await test("Settings → Backup: Export and Import buttons") {
        let id = try store.insert(NewCapture(kind: .text, text: "[uitest] pinned for backup", contentHash: "uitest:backup"), sensitiveTTL: 600)
        try store.pin(id, to: try store.createPinboard(name: "UITest Board", colorHex: "#10B981"))
        post("local.mypaste.uitest.settings", "backup")
        guard let export = await element("backup.export", timeout: 5) else { check(false, "Export button found"); return }
        check(export.press(), "Export pressed")
        check(await waitFor(5) { FileManager.default.fileExists(atPath: exportURL.path) }, "archive written")
        check(await element("backup.status", timeout: 3).map { text(of: $0).contains("Exported") } ?? false, "export status shown")

        let fresh = try ClipStore(directory: work.appendingPathComponent("verify"))
        let summary = try BackupArchive.importArchive(exportURL, into: fresh)
        let boards = try fresh.pinboards().map(\.name)
        let names = try fresh.allItems().compactMap(\.text)
        check(summary.items >= 1 && boards.contains("UITest Board") && names.contains("[uitest] pinned for backup"),
              "archive contains the pinned item and its board")

        guard let importButton = await element("backup.import") else { check(false, "Import button found"); return }
        check(importButton.press(), "Import pressed")
        check(await waitFor(5) { elements("backup.status").contains { text(of: $0).contains("already here") } }, "import reports duplicates")
    }

    await test("Settings → Backup: Import Pins from Maccy") {
        post("local.mypaste.uitest.settings", "backup")
        guard let button = await element("backup.maccy", timeout: 5) else { check(false, "Maccy import button shown"); return }
        check(button.press(), "Import pressed")
        let ok = await waitFor(5) {
            guard let board = (try? store.pinboards())?.first(where: { $0.name == "Maccy" }) else { return false }
            let pinned = items().filter { $0.pinboardIDs.contains(board.id) }.compactMap(\.text)
            return Set(pinned) == ["[uitest] maccy pin one", "[uitest] maccy pin two"]
        }
        check(ok, "both pins on a Maccy board, unpinned item skipped")
        check(await waitFor(3) { elements("backup.status").contains { text(of: $0).contains("Imported 2 pins") } }, "status reports 2 imported")
        _ = (await element("backup.maccy"))?.press()
        check(await waitFor(3) { elements("backup.status").contains { text(of: $0).contains("2 already here") } }, "re-run imports nothing new")
    }

    await test("Settings → Appearance: sound pack, Play buttons and a custom file") {
        let bundled = (try? FileManager.default.contentsOfDirectory(atPath: appBundle.appendingPathComponent("Contents/Resources/Sounds").path)) ?? []
        check(bundled.filter { $0.hasSuffix(".wav") }.count == 15, "15 sounds bundled (got \(bundled.count))")
        post("local.mypaste.uitest.settings", "appearance")
        guard let toggle = await element("appearance.sounds", timeout: 5) else { check(false, "sounds switch found"); return }
        check(toggle.press(), "sounds switched on")
        for effect in ["copy", "paste", "delete"] {
            guard let play = await element("appearance.sound.\(effect).play", timeout: 3) else { check(false, "\(effect) Play button"); continue }
            check(play.press(), "\(effect) Play pressed")
            await sleep(0.3)
        }
        guard let choose = await element("appearance.sound.copy.choose") else { check(false, "copy Choose… button"); return }
        check(choose.press(), "Choose… pressed")
        let custom = dataDir.appendingPathComponent("sounds/custom-copy.wav")
        check(await waitFor(3) { FileManager.default.fileExists(atPath: custom.path) }, "custom file copied into the data folder")
        check(await waitFor(3) { elements("appearance.sound.copy.menu").contains { text(of: $0).contains("chime.wav") } },
              "copy menu now shows the custom file (got \(elements("appearance.sound.copy.menu").map { text(of: $0) }))")
        await copy("[uitest] sound on copy") // plays the chosen sound through the real capture path
        await sleep(0.5)
        let log = (try? String(contentsOf: dataDir.appendingPathComponent("logs/myPaste.log"), encoding: .utf8)) ?? ""
        check(!log.contains("Can't play sound") && !log.contains("Custom sound rejected"), "no playback errors in the log")
        check(!launched.isTerminated, "app still running after playing sounds")
    }

    await test("Settings → Shortcuts: conflict Quit button quits the clashing app") {
        guard let fake = fakeMaccy else { print("    (skipped: no FakeMaccy.app given)"); return }
        let real = NSRunningApplication.runningApplications(withBundleIdentifier: "org.p0deje.Maccy")
        guard real.isEmpty else { print("    (skipped: real Maccy is running; not quitting it)"); return }
        let cfg = NSWorkspace.OpenConfiguration()
        cfg.activates = false
        cfg.createsNewApplicationInstance = true
        let fakeApp = try await NSWorkspace.shared.openApplication(at: fake, configuration: cfg)
        await sleep(1)
        // Paste Stack is off by default: ⇧⌘C must do nothing and can't clash with anything.
        await focusTarget()
        await key(8, [.maskCommand, .maskShift])
        await sleep(0.6)
        check(app.windows.allSatisfy { $0.identifier != "pastestack.hud" }, "⇧⌘C ignored while Paste Stack is off")
        post("local.mypaste.uitest.settings", "shortcuts")
        guard let toggle = await element("shortcuts.pasteStack", timeout: 5) else { check(false, "Paste Stack switch found"); fakeApp.terminate(); return }
        check(elements("conflict.quit").isEmpty, "no conflict reported while Paste Stack is off")
        check(toggle.press(), "Paste Stack switched on")
        post("local.mypaste.uitest.settings", "shortcuts") // pane re-reads the running apps on appear
        guard let quit = await element("conflict.quit", timeout: 5) else { check(false, "conflict shown with Quit button"); fakeApp.terminate(); return }
        check(quit.press(), "Quit pressed")
        check(await waitFor(5) { fakeApp.isTerminated }, "clashing app terminated")
    }

    // Teardown
    launched.terminate()
    await sleep(0.5)
    if let savedClipboard { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(savedClipboard, forType: .string) }
    if failures.isEmpty { try? FileManager.default.removeItem(at: work) } else { print("Kept \(work.path) for inspection (logs in data/logs)") }

    print("\n\(passed) checks passed, \(failures.count) failed")
    failures.forEach { print("  ✘ \($0)") }
    exit(failures.isEmpty ? 0 : 1)
}

Task { @MainActor in await runAll() }
nsApp.run()
