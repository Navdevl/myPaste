import Darwin
import Foundation

/// Local error and crash log in ~/Library/Application Support/myPaste/logs. Nothing leaves the Mac.
/// Messages must never contain clipboard contents: log ids, kinds and error descriptions only.
enum AppLog {
    static var directory: URL { AppDelegate.dataDirectory.appendingPathComponent("logs", isDirectory: true) }
    static var logFile: URL { directory.appendingPathComponent("myPaste.log") }
    static var crashFile: URL { directory.appendingPathComponent("crash.log") }

    private static let queue = DispatchQueue(label: "mypaste.log")
    private static let maxBytes = 1_000_000
    /// Opened up front: a signal handler may only call async-signal-safe functions, so no Foundation there.
    private static var crashFD: Int32 = -1

    static func start() {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        crashFD = open(crashFile.path, O_WRONLY | O_CREAT | O_APPEND, 0o644)
        NSSetUncaughtExceptionHandler { exception in
            AppLog.writeCrash("Uncaught exception: \(exception.name.rawValue): \(exception.reason ?? "")\n"
                              + exception.callStackSymbols.joined(separator: "\n"))
        }
        for sig in [SIGSEGV, SIGBUS, SIGILL, SIGTRAP, SIGABRT, SIGFPE] {
            signal(sig) { s in
                AppLog.signalCrash(s)
                signal(s, SIG_DFL)
                raise(s)
            }
        }
        info("Launched \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?")")
    }

    static func info(_ message: String) { append("INFO", message) }

    static func error(_ message: String, _ error: Error? = nil) {
        append("ERROR", error.map { "\(message): \($0)" } ?? message)
    }

    private static func append(_ level: String, _ message: String) {
        let line = "\(ISO8601DateFormatter.ist.string(from: Date())) \(level) \(message)\n"
        queue.async {
            rotateIfNeeded()
            if let h = try? FileHandle(forWritingTo: logFile) {
                h.seekToEndOfFile()
                h.write(Data(line.utf8))
                try? h.close()
            } else {
                try? Data(line.utf8).write(to: logFile)
            }
        }
    }

    private static func rotateIfNeeded() {
        guard let size = (try? FileManager.default.attributesOfItem(atPath: logFile.path))?[.size] as? Int, size > maxBytes else { return }
        let old = directory.appendingPathComponent("myPaste.1.log")
        try? FileManager.default.removeItem(at: old)
        try? FileManager.default.moveItem(at: logFile, to: old)
    }

    private static func writeCrash(_ text: String) {
        guard crashFD >= 0 else { return }
        let entry = "\n=== \(Date()) ===\n\(text)\n"
        _ = entry.withCString { write(crashFD, $0, strlen($0)) }
    }

    /// Async-signal-safe path: fixed strings and backtrace_symbols_fd only.
    private static func signalCrash(_ sig: Int32) {
        guard crashFD >= 0 else { return }
        let header = "\n=== crash: fatal signal ===\n"
        _ = header.withCString { write(crashFD, $0, strlen($0)) }
        var frames = [UnsafeMutableRawPointer?](repeating: nil, count: 64)
        let n = backtrace(&frames, 64)
        backtrace_symbols_fd(&frames, n, crashFD)
    }

    /// macOS's own crash reports for this app, newest first.
    static var systemCrashReports: [URL] {
        let dir = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs/DiagnosticReports")
        let files = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
        return files.filter { $0.lastPathComponent.hasPrefix("myPaste") }
            .sorted { ($0.modDate ?? .distantPast) > ($1.modDate ?? .distantPast) }
    }
}

private extension URL {
    var modDate: Date? { (try? resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate }
}

extension ISO8601DateFormatter {
    static let ist: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.timeZone = TimeZone(identifier: "Asia/Kolkata")
        return f
    }()
}
