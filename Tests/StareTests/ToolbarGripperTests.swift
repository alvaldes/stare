import XCTest
import AppKit
import SwiftUI

@testable import Stare

/// S4: the bar ends with a visible `⠇⠇` grab handle placed directly after
/// the close ("Done") button, so the user has an obvious spot to drag the
/// toolbar from. The order is a single source of truth the view maps over,
/// so pinning the array pins what the bar draws.
@MainActor
final class ToolbarGripperTests: XCTestCase {

    func testGripperSitsDirectlyAfterTheCloseButton() {
        XCTAssertEqual(
            ToolbarView.trailingItems.suffix(2),
            [.close, .gripper],
            "the gripper must be the item right after the close button, and the last in the bar"
        )
    }

    // MARK: Gripper cursors (T2/S3)

    func testGripperHoversWithTheOpenHandAndDragsWithTheClosedHand() {
        // T2/S3: over the gripper the open hand shows; while the drag runs it
        // is the closed hand — the same pair the board's pan shows.
        let gripper = ToolbarGripperView()
        XCTAssertFalse(gripper.isDragging)
        XCTAssertEqual(gripper.hoverCursor, .openHand)

        gripper.beginDrag()
        XCTAssertTrue(gripper.isDragging)
        XCTAssertEqual(gripper.hoverCursor, .closedHand)

        gripper.endDrag()
        XCTAssertFalse(gripper.isDragging)
        XCTAssertEqual(gripper.hoverCursor, .openHand, "releasing the drag returns the open hand")
    }

    func testGripperAbandonsTheDragWhenItLeavesTheWindow() {
        // T2/S3: the removal path must not leave a drag (or a hand cursor)
        // behind — the view forgets the drag state, and whatever sits under
        // the bar owns the cursor next.
        let gripper = ToolbarGripperView()
        gripper.beginDrag()
        XCTAssertTrue(gripper.isDragging)

        gripper.abandonDrag()
        XCTAssertFalse(gripper.isDragging)
        XCTAssertEqual(gripper.hoverCursor, .openHand)
    }

    // MARK: Gripper colour (T5/S5)

    /// S5: the gripper's dots must read like the other tools' glyphs in both
    /// system appearances. The other items are SF Symbols styled with
    /// SwiftUI's `Color.secondary` inside the bar's material, so their core
    /// luminance is the reference the dots must meet; the dots used to be
    /// drawn by the AppKit view outside that treatment and washed out on the
    /// light bar. The test renders the real bar through the same offscreen
    /// path the fixtures use (a real window, then `cacheDisplay`) and
    /// compares the darkest (light) / brightest (dark) pixel of the dots
    /// against the pixel of the close button's glyph beside it.
    func testGripperDotsMatchTheGlyphColourInBothAppearances() throws {
        for (name, appearanceName) in [("light", NSAppearance.Name.aqua), ("dark", NSAppearance.Name.darkAqua)] {
            let rendered = try Self.renderBar(appearanceName: appearanceName)
            let luma = try Self.coreLuma(in: rendered)
            let dots = try Self.regionLuma(Self.gripperRegion(size: rendered.size, scale: luma.scale), pixels: luma)
            let glyph = try Self.regionLuma(Self.closeRegion(size: rendered.size, scale: luma.scale), pixels: luma)
            let dotValue = name == "light" ? dots.dark : dots.bright
            let glyphValue = name == "light" ? glyph.dark : glyph.bright
            XCTAssertTrue(
                abs(dotValue - glyphValue) <= 6,
                "\(name): the gripper dots (\(dotValue)) must read as dark/bright as the neighbouring glyph (\(glyphValue))"
            )
        }
    }

    // MARK: Bar cursor arbitration (T6/S6)

    /// S6: the bar owns the pointer over its whole area — the gripper's hand
    /// pair inside the gripper's frame, the arrow everywhere else on the bar.
    /// The single decision the overlay's cursor monitor applies, pinned here
    /// on the real view without a live pointer.
    func testBarCursorIsTheHandOverTheGripperAndTheArrowEverywhereElse() throws {
        let gripper = ToolbarGripperView()
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 200, height: 50))
        gripper.frame = NSRect(x: 100, y: 10, width: 16, height: 26)
        container.addSubview(gripper)
        let window = NSWindow(
            contentRect: container.bounds,
            styleMask: [.borderless], backing: .buffered, defer: false
        )
        window.contentView = container

        XCTAssertEqual(
            ToolbarGripperView.barCursor(at: CGPoint(x: 108, y: 23), in: window),
            .openHand,
            "over the gripper the bar shows the gripper's open hand"
        )
        XCTAssertEqual(
            ToolbarGripperView.barCursor(at: CGPoint(x: 50, y: 25), in: window),
            .arrow,
            "elsewhere on the bar the pointer is the arrow, never the tool's cursor"
        )

        gripper.beginDrag()
        XCTAssertEqual(
            ToolbarGripperView.barCursor(at: CGPoint(x: 108, y: 23), in: window),
            .closedHand,
            "while the gripper drags, its closed hand holds"
        )
        gripper.endDrag()
    }

    func testBarCursorArbitrationAnswersTheArrowWithoutAGripper() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 200, height: 50),
            styleMask: [.borderless], backing: .buffered, defer: false
        )
        window.contentView = NSView(frame: NSRect(x: 0, y: 0, width: 200, height: 50))
        XCTAssertNil(ToolbarGripperView.locate(in: window), "a bar without a gripper has nothing to arbitrate for")
        XCTAssertEqual(
            ToolbarGripperView.barCursor(at: CGPoint(x: 50, y: 25), in: window),
            .arrow,
            "without a gripper the bar still shows the arrow, not the tool cursor"
        )
    }
}

// MARK: - Bar render + pixel sampling (T5/S5)

extension ToolbarGripperTests {

    /// The real bar rendered through the fixture path: a hosting view pinned
    /// to its fitting size inside a real on-screen window of the fixed
    /// appearance, then `cacheDisplay` — the same offscreen render the
    /// Settings fixtures use, so the pixels measured here are the pixels the
    /// user sees.
    struct RenderedBar {
        let cgImage: CGImage
        let size: CGSize
    }

    /// The render redrawn into an sRGB RGBA8 buffer, so pixel reads do not
    /// depend on the bitmap rep's own colour space.
    struct PixelScan {
        let scale: CGFloat
        let width: Int
        let height: Int
        let data: [UInt8]

        func luma(x: Int, y: Int) -> (lum: Int, alpha: UInt8) {
            let i = (y * width + x) * 4
            let lum = (Int(data[i]) + Int(data[i + 1]) + Int(data[i + 2])) / 3
            return (lum, data[i + 3])
        }
    }

    /// The darkest and brightest opaque luma inside a pixel-space rect.
    struct RegionLuma {
        let dark: Int
        let bright: Int
    }

    @MainActor
    static func renderBar(appearanceName: NSAppearance.Name) throws -> RenderedBar {
        let state = EditorState()
        state.tool = .arrow
        let hosting = NSHostingView(
            rootView: ToolbarView(state: state, onUndo: {}, onRedo: {}, onClear: {}, onDone: {})
        )
        hosting.sizingOptions = [.intrinsicContentSize]
        hosting.appearance = NSAppearance(named: appearanceName)
        let size = hosting.fittingSize
        hosting.frame = CGRect(origin: .zero, size: size)
        hosting.layoutSubtreeIfNeeded()

        let window = NSWindow(
            contentRect: CGRect(origin: .zero, size: size),
            styleMask: [.borderless], backing: .buffered, defer: false
        )
        window.contentView = hosting
        window.appearance = NSAppearance(named: appearanceName)
        window.orderFrontRegardless()
        RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        let representation = try XCTUnwrap(hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds))
        hosting.cacheDisplay(in: hosting.bounds, to: representation)
        window.orderOut(nil)
        let image = try XCTUnwrap(representation.cgImage)
        return RenderedBar(cgImage: image, size: size)
    }

    static func coreLuma(in render: RenderedBar) throws -> PixelScan {
        let image = render.cgImage
        let width = image.width, height = image.height
        let context = try XCTUnwrap(
            CGContext(
                data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )
        )
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        let buffer = try XCTUnwrap(context.data)
        let pointer = buffer.bindMemory(to: UInt8.self, capacity: width * height * 4)
        let data = Array(UnsafeBufferPointer(start: pointer, count: width * height * 4))
        return PixelScan(scale: CGFloat(width) / render.size.width, width: width, height: height, data: data)
    }

    /// The gripper's rect in pixel space: the bar's last item, rightmost
    /// 16 pt inside the trailing 12 pt padding.
    static func gripperRegion(size: CGSize, scale: CGFloat) -> CGRect {
        region(x0: size.width - 28, x1: size.width - 12, size: size, scale: scale)
    }

    /// The close button's glyph rect in pixel space: the item before the
    /// gripper (4 pt spacing, 26 pt button frame).
    static func closeRegion(size: CGSize, scale: CGFloat) -> CGRect {
        region(x0: size.width - 58, x1: size.width - 32, size: size, scale: scale)
    }

    private static func region(x0: CGFloat, x1: CGFloat, size: CGSize, scale: CGFloat) -> CGRect {
        let band = size.height / 2
        return CGRect(
            x: x0 * scale, y: (band - 10) * scale,
            width: (x1 - x0) * scale, height: 20 * scale
        )
    }

    static func regionLuma(_ rect: CGRect, pixels: PixelScan) throws -> RegionLuma {
        let x0 = max(0, Int(rect.minX)), x1 = min(pixels.width - 1, Int(rect.maxX))
        let y0 = max(0, Int(rect.minY)), y1 = min(pixels.height - 1, Int(rect.maxY))
        precondition(y1 > y0 && x1 > x0, "empty sample region")
        var dark = Int.max, bright = Int.min
        for y in y0...y1 {
            for x in x0...x1 {
                let sample = pixels.luma(x: x, y: y)
                guard sample.alpha > 128 else { continue }
                dark = min(dark, sample.lum)
                bright = max(bright, sample.lum)
            }
        }
        return RegionLuma(dark: dark, bright: bright)
    }
}
