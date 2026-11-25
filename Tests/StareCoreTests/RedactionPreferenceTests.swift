import CoreGraphics
import Foundation
import XCTest

import StareCore

/// B2: what a mark gets when nothing was reinterpreted. The shipped
/// preference default is the randomized pixelate, so a mark minted from a
/// fresh preference carries the pixelate into its `Stroke` and renders
/// through the one dispatch (`MarkRenderer.redactionPatch`, reached here the
/// way every painting path reaches it, through `MarkCompositor`). The
/// stroke-level and session-level decode fallbacks stay `.blur`, so a drawing
/// saved before B2 repaints exactly what it painted — those pins live in
/// `RedactionStorageTests` and `RedactionDispatchTests`.
final class RedactionPreferenceTests: XCTestCase {
    private let markRect = CGRect(x: 20, y: 20, width: 60, height: 60)

    /// White with thin black vertical stripes, the fixture the dispatch pins
    /// against: letter-stroke thin, so a pixelate patch and its blur twin over
    /// the same mark read unambiguously differently.
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

    /// A fresh preference document is the pixelate, and a mark minted from it
    /// — the way every surface that mints a mark stamps its state's choice on
    /// `DrawingSession.begin` — carries the pixelate into its committed
    /// `Stroke`, which then renders through the one dispatch as a pixelate
    /// patch, never as the blur twin of the same geometry.
    func testAMarkMintedFromAFreshPreferenceCarriesThePixelateAndRendersThroughTheOneDispatch() {
        let fresh = AppPreferences.standard
        XCTAssertEqual(fresh.redactionStyle, .randomizedPixelate, "a fresh install gets the shipped pixelate")

        var session = DrawingSession()
        session.begin(at: markRect.origin, tool: .blur, ink: .blue, redactionStyle: fresh.redactionStyle)
        session.extend(to: CGPoint(x: markRect.maxX, y: markRect.maxY))
        session.commit()
        let minted = session.strokes.first

        XCTAssertEqual(minted?.redactionStyle, .randomizedPixelate, "the minted mark carries the preference's choice")
        XCTAssertEqual(minted?.tool, .blur, "same tool, same geometry: only the shipped redaction changed")

        var blurTwin = minted!
        blurTwin.redactionStyle = .blur
        let pixelated = MarkCompositor.composite(marks: [minted!], over: stripedBase(), scale: 1)!
        let blurred = MarkCompositor.composite(marks: [blurTwin], over: stripedBase(), scale: 1)!
        XCTAssertNotEqual(
            bytes(pixelated), bytes(blurred),
            "the minted mark must render through the pixelate branch of the one dispatch, never the blur twin")
    }
}
