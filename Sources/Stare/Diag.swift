import Foundation

/// Development diagnostics. `log show` no longer surfaces this app's `NSLog`
/// output reliably on macOS 26, so the same lines also go to a file that the
/// agent and the user can read directly.
enum Diag {
    static let path = "/tmp/stare.log"
    private static let queue = DispatchQueue(label: "dev.alvaldes.stare.diagnostics")

    static func reset() {
        queue.sync {
            try? "".write(toFile: path, atomically: true, encoding: .utf8)
        }
    }

    static func log(_ message: String) {
        NSLog("Stare: %@", message)
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
