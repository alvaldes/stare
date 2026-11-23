import CoreGraphics
import Foundation
import XCTest

import StareCore

/// T6b/S13 step 2: the redaction style rides the session in and out. The
/// default is today's blur everywhere an existing caller path compiles, and a
/// mark that drew pixelated survives the persisted round trip — so a saved
/// drawing restores exactly the redaction it was drawn with (the step-1 Risk
/// item that a pixelate mark must not decay to blur on restore).
final class RedactionStorageTests: XCTestCase {
    private let markRect = CGRect(x: 20, y: 20, width: 60, height: 60)

    // MARK: - Fixtures

    /// White with thin black vertical stripes (2 px every 12 px), the
    /// letter-stroke-thin fixture the dispatch tests pin against.
    private func stripedBase() -> CGImage {
        let context = CGContext(
            data: nil, width: 120, height: 120, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        context.setFillColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 120, height: 120))
        context.setFillColor(CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 1))
        context.fill(CGRect(x: 30, y: 0, width: 2, height: 120))
        context.fill(CGRect(x: 54, y: 0, width: 2, height: 120))
        context.fill(CGRect(x: 78, y: 0, width: 2, height: 120))
        return context.makeImage()!
    }

    private func bytes(_ image: CGImage) -> [UInt8] {
        var data = [UInt8](repeating: 0, count: image.width * image.height * 4)
        let context = CGContext(
            data: &data,
            width: image.width,
            height: image.height,
            bitsPerComponent: 8,
            bytesPerRow: image.width * 4,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        return data
    }

    private func blurredMark() -> Stroke {
        Stroke(tool: .blur, ink: .blue, points: [markRect.origin, CGPoint(x: markRect.maxX, y: markRect.maxY)])
    }

    // MARK: - begin keeps today's default and passes the choice through

    /// Every existing caller of `begin` compiles unchanged and gets exactly
    /// what it always got: a mark that redacts with the audited blur.
    func testBeginDefaultsToTodaysBlur() {
        var session = DrawingSession()
        let stroke = session.begin(at: markRect.origin, tool: .blur, ink: .blue)

        XCTAssertEqual(stroke.redactionStyle, .blur)
    }

    func testBeginCarriesTheStyleIntoTheCommittedMark() {
        var session = DrawingSession()
        let beginAt = Date()
        let committed = session.begin(
            at: markRect.origin, tool: .blur, ink: .blue, now: beginAt,
            redactionStyle: .randomizedPixelate)
        XCTAssertEqual(committed.redactionStyle, .randomizedPixelate)
        session.extend(to: CGPoint(x: markRect.maxX, y: markRect.maxY))
        session.commit()

        XCTAssertEqual(session.strokes.first?.redactionStyle, .randomizedPixelate)
        XCTAssertEqual(session.strokes.first?.tool, .blur)
    }

    // MARK: - A pixelate mark survives the restore round trip (Risk 1)

    /// The whole persisted round trip: draw pixelated, store its form, decode
    /// it back, restore the mark — the restored mark is still pixelate and
    /// renders byte-identically to the mark that was saved.
    func testAPixelateMarkSurvivesRestoreAndRendersExactly() throws {
        var drawn = blurredMark()
        drawn.redactionStyle = .randomizedPixelate

        let stored = drawn.persisted
        let data = try JSONEncoder().encode([stored])
        let decoded = try JSONDecoder().decode([PersistedStroke].self, from: data)
        let restored = try XCTUnwrap(decoded.first.flatMap { Stroke(persisted: $0) })

        XCTAssertEqual(restored.redactionStyle, .randomizedPixelate)
        XCTAssertEqual(restored, drawn)
        XCTAssertEqual(
            bytes(MarkCompositor.composite(marks: [restored], over: stripedBase(), scale: 1)!),
            bytes(MarkCompositor.composite(marks: [drawn], over: stripedBase(), scale: 1)!),
            "the restored pixelate mark must render exactly as it was saved")
    }

    /// A document written before the field existed restores as blur, exactly
    /// the way every mark drawn before it rendered.
    func testALegacyPersistedStrokeWithoutTheStyleRestoresAsBlur() throws {
        let legacyJSON = """
        {
            "id": "DC1EF1AB-19C2-4C9B-B2FB-760345A02AA6",
            "tool": "blur",
            "ink": "red",
            "points": [[1, 1], [9, 9]],
            "stepNumber": null,
            "text": null,
            "textSize": null,
            "createdAt": null,
            "badgeSize": null,
            "rotation": 0
        }
        """
        let stored = try JSONDecoder().decode(PersistedStroke.self, from: Data(legacyJSON.utf8))
        let restored = try XCTUnwrap(Stroke(persisted: stored))

        XCTAssertEqual(restored.redactionStyle, .blur)
    }

    /// A foreign raw value must not fail the document or change the mark: it
    /// restores as the default blur, like the blob's own fields do.
    func testAnUnknownStyleRawValueRestoresAsBlur() throws {
        let foreignJSON = """
        {
            "id": "DC1EF1AB-19C2-4C9B-B2FB-760345A02AA6",
            "tool": "blur",
            "ink": "red",
            "points": [[1, 1], [9, 9]],
            "stepNumber": null,
            "text": null,
            "textSize": null,
            "createdAt": null,
            "badgeSize": null,
            "rotation": 0,
            "redactionStyle": "mosaic"
        }
        """
        let foreignStored = try JSONDecoder().decode(PersistedStroke.self, from: Data(foreignJSON.utf8))
        let restored = try XCTUnwrap(Stroke(persisted: foreignStored))
        XCTAssertEqual(restored.redactionStyle, .blur)
    }
}
