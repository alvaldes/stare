import AppKit
import XCTest

@testable import StareCore

/// The PRESERVE pin for file-name templates (T10/S17): with the prefix "Stare"
/// and no template, a folder save must produce exactly the name it produced
/// before templates existed. This class deliberately carries nothing but the
/// pin and only compiles-against-and-after pieces, so it passed on the
/// untouched branch (`1461de1`) before `fileNameTemplate` existed and must
/// keep passing after it does.
final class CaptureFileNamePreservePinTests: XCTestCase {
    /// Gregorian UTC calendar and a fixed instant, so the name is pinned
    /// exactly and nothing is injected from the environment.
    private let calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }()

    func testFolderSaveWithPrefixStareAndNoTemplateProducesTodaysNameExactly() throws {
        // Through the real folder writer — the public interface — the
        // untemplated name is today's exact shape.
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("stare-preserve-pin-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let preference = CapturePreference(
            format: .png,
            destination: .folder(path: folder.path),
            fileNamePrefix: "Stare"
        )
        let instant = calendar.date(
            from: DateComponents(year: 2026, month: 11, day: 21, hour: 14, minute: 5, second: 33)
        )!
        let url = try XCTUnwrap(
            CaptureFile.write(CGImage.solidImage(width: 4, height: 4)!, preference: preference, date: instant, calendar: calendar)
        )
        XCTAssertEqual(url.lastPathComponent, "Stare-2026-11-21-at-14-05-33.png")
    }
}

private extension CGImage {
    /// A small solid image, enough for the encoders.
    static func solidImage(width: Int, height: Int) -> CGImage? {
        let context = CGContext(
            data: nil, width: width, height: height,
            bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )
        context?.setFillColor(CGColor(red: 0.2, green: 0.4, blue: 0.6, alpha: 1))
        context?.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return context?.makeImage()
    }
}
