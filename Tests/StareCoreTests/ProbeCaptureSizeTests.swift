import CoreGraphics
import XCTest
@testable import StareCore

/// The Screen Recording probe is a real capture at a reduced size, so its
/// configuration has to stay a configuration ScreenCaptureKit accepts. A
/// downscale that collapses a display into a couple of pixels makes the probe
/// fail for a display that captures fine, which the permission UI then reports
/// as "granted, restart needed".
final class ProbeCaptureSizeTests: XCTestCase {
    /// A 1920 × 1080 display keeps a real capture: the short side stays at the
    /// probe's floor and the wider side keeps the display's aspect ratio.
    func testFullHDDisplayKeepsTheProbeShortSide() {
        let downscale = ProbeCaptureSize.downscale(pixelWidth: 1920, pixelHeight: 1080)

        let width = Int((1920 / downscale).rounded())
        let height = Int((1080 / downscale).rounded())

        XCTAssertEqual(height, ProbeCaptureSize.shortSide, "the short side is the probe's floor")
        XCTAssertGreaterThanOrEqual(
            min(width, height), ProbeCaptureSize.shortSide,
            "a probe smaller than the floor is a configuration ScreenCaptureKit rejects"
        )
        XCTAssertEqual(
            Double(width) / Double(height), 1920.0 / 1080.0, accuracy: 0.02,
            "the probe must keep the display's aspect ratio"
        )
    }

    /// A display already smaller than the floor is captured at its own size:
    /// the probe never upscales.
    func testSmallDisplayIsNotUpscaled() {
        XCTAssertEqual(ProbeCaptureSize.downscale(pixelWidth: 96, pixelHeight: 64), 1)
    }

    /// The floor is the reason the probe exists at all: a full-size frame is
    /// too expensive to take on every refresh, so the factor is never 1 for a
    /// normal display.
    func testFullHDDisplayIsDownscaled() {
        XCTAssertGreaterThan(ProbeCaptureSize.downscale(pixelWidth: 1920, pixelHeight: 1080), 8)
        XCTAssertLessThan(ProbeCaptureSize.downscale(pixelWidth: 1920, pixelHeight: 1080), 32)
    }

    /// Whatever the display, the probe never asks for a degenerate size.
    func testDegenerateDisplaySizesStayAboveOnePixel() {
        for (width, height) in [(1, 1), (0, 0), (4, 2), (6016, 3384)] {
            let downscale = ProbeCaptureSize.downscale(pixelWidth: width, pixelHeight: height)
            XCTAssertGreaterThanOrEqual(downscale, 1)
            let pixels = Int((Double(max(1, min(width, height))) / downscale).rounded())
            XCTAssertGreaterThanOrEqual(pixels, min(ProbeCaptureSize.shortSide, max(1, min(width, height))))
        }
    }
}
