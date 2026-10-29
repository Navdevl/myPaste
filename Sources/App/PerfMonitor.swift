import Foundation

/// Opt-in (MYPASTE_PERF=1) jank detector: a background thread pings the main thread every 50 ms and
/// logs to stderr when the reply is more than 100 ms late, plus timings for reload/filter passes.
enum Perf {
    static let enabled = ProcessInfo.processInfo.environment["MYPASTE_PERF"] == "1"

    static func log(_ s: String) {
        guard enabled else { return }
        FileHandle.standardError.write(Data(String(format: "%.3f PERF %@\n", Date().timeIntervalSince1970, s).utf8))
    }

    @discardableResult
    static func measure<T>(_ label: String, _ body: () throws -> T) rethrows -> T {
        guard enabled else { return try body() }
        let t = CFAbsoluteTimeGetCurrent()
        defer { log(String(format: "%@ %.1fms", label, (CFAbsoluteTimeGetCurrent() - t) * 1000)) }
        return try body()
    }

    static func startHangDetector() {
        guard enabled else { return }
        Thread.detachNewThread {
            while true {
                let sent = CFAbsoluteTimeGetCurrent()
                let sem = DispatchSemaphore(value: 0)
                DispatchQueue.main.async { sem.signal() }
                sem.wait()
                let lag = (CFAbsoluteTimeGetCurrent() - sent) * 1000
                if lag > 100 { log(String(format: "HANG %.0fms", lag)) }
                Thread.sleep(forTimeInterval: 0.05)
            }
        }
    }
}
