import Foundation

/// Development diagnostics. Off unless `STARE_DIAG=1` is in the environment:
/// shipping builds must not write a trace file into /tmp.
enum Diag {
    static let path = "/tmp/stare.log"
    private static let enabled = ProcessInfo.processInfo.environment["STARE_DIAG"] == "1"
    private static let queue = DispatchQueue(label: "dev.alvaldes.stare.diagnostics")

    static func reset() {
        guard enabled else { return }
        queue.sync { try? "".write(toFile: path, atomically: true, encoding: .utf8) }
    }

    static func log(_ message: String) {
        guard enabled else { return }
        let line = "\(String(format: "%.3f", Date().timeIntervalSince1970)) \(message)\n"
        queue.async {
            guard let data = line.data(using: .utf8) else { return }
            if let handle = FileHandle(forWritingAtPath: path) {
                handle.seekToEndOfFile()
                handle.write(data)
                try? handle.close()
            } else {
                try? data.write(to: URL(fileURLWithPath: path))
            }
        }
    }
}
