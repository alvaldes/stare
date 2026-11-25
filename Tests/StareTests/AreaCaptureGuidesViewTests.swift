import AppKit
import XCTest

@testable import Stare
import StareCore

/// The area drag's dotted guides at the view layer (S1): thin, dotted,
/// subdued rules from the selection's four edges out to the display's edges,
/// painted over the real `OverlayView` mid-drag and asserted in pixels — the
/// same real-view bitmap pattern the freeze tests established. The windows
/// these tests open are confined to the primary screen
/// (`PrimaryScreenTestWindow`), never the user's other monitors.
@MainActor
final class AreaCaptureGuidesViewTests: XCTestCase {
    private let size = CGSize(width: 900, height: 600)

    /// A solid frame whose pixels differ from everything else the view paints
    /// (green where the chrome is white-over-dark), so a rendered bitmap can
    /// distinguish the frozen content, the shroud and the chrome.
    private func makeSolidImage(width: Int, height: Int, red: CGFloat, green: CGFloat, blue: CGFloat) -> CGImage {
        let context = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8,
            bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(CGColor(srgbRed: red, green: green, blue: blue, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage()!
    }

    private func render(_ view: NSView) throws -> NSBitmapImageRep {
        let rep = try XCTUnwrap(NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: Int(view.bounds.width), pixelsHigh: Int(view.bounds.height),
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        view.cacheDisplay(in: view.bounds, to: rep)
        return rep
    }

    private func makeView(state: EditorState = EditorState()) -> OverlayView {
        let view = OverlayView(
            frame: CGRect(origin: .zero, size: size),
            state: state, onEscape: {})
        view.onAreaSelectionFrame = {}
        return view
    }

    private func mouseEvent(
        _ type: NSEvent.EventType, at viewPoint: CGPoint, window: NSWindow
    ) -> NSEvent {
        // The events speak window coordinates (bottom-left origin); the
        // flipped view converts them, so tests state points in view space.
        let windowPoint = CGPoint(x: viewPoint.x, y: size.height - viewPoint.y)
        return NSEvent.mouseEvent(
            with: type, location: windowPoint,
            modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: window.windowNumber, context: nil, eventNumber: 1,
            clickCount: 1, pressure: 1)!
    }

    private func hostWindow(_ view: NSView) throws -> NSWindow {
        try XCTSkipIf(NSScreen.screens.isEmpty, "no screen to host the probe")
        let window = NSWindow(
            contentRect: try XCTUnwrap(
                PrimaryScreenTestWindow.frame(for: size),
                "the primary screen cannot host the probe"),
            styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = view
        window.orderFrontRegardless()
        return window
    }

    /// Whether the bitmap carries a bright chrome dot within `radius` points
    /// of `point`: the guides' white dotted top stroke over the frozen scene
    /// and its shroud must clear everything the scene itself can paint there.
    private func hasChromeDot(_ rep: NSBitmapImageRep, near point: CGPoint, radius: CGFloat = 3) -> Bool {
        for x in Int(point.x - radius)...Int(point.x + radius) {
            for y in Int(point.y - radius)...Int(point.y + radius) {
                guard x >= 0, y >= 0, x < rep.pixelsWide, y < rep.pixelsHigh,
                    let color = rep.colorAt(x: x, y: y)
                else { continue }
                if min(color.redComponent, color.greenComponent, color.blueComponent) > 0.45 { return true }
            }
        }
        return false
    }

    // MARK: The guides are on screen

    /// Dragging from (100, 100) to (400, 300) frames that rect; its four
    /// edges must show dotted chrome out to the display's edges — sampled on
    /// two of the eight rules (the right edge's lower ray and the top edge's
    /// right ray, both well away from the loupe's frame).
    func testTheDraggedSelectionsEdgesCarryDottedGuidesOutToTheDisplayEdges() throws {
        let view = makeView()
        let window = try hostWindow(view)
        defer { window.orderOut(nil) }

        view.beginAreaSelection()
        view.landAreaFrame(makeSolidImage(width: 1800, height: 1200, red: 0.1, green: 0.9, blue: 0.2))
        view.mouseDown(with: mouseEvent(.leftMouseDown, at: CGPoint(x: 100, y: 100), window: window))
        view.mouseDragged(with: mouseEvent(.leftMouseDragged, at: CGPoint(x: 400, y: 300), window: window))

        let rep = try render(view)
        // The right edge (x = 400) runs below the selection to the display's
        // bottom edge (y = 600): a dot must sit on that line, inside the view.
        XCTAssertTrue(
            hasChromeDot(rep, near: CGPoint(x: 400, y: 450)),
            "the selection's right edge must carry a dotted rule running to the display's bottom edge")
        // The top edge (y = 100) runs right of the selection to the display's
        // right edge (x = 900): a dot must sit on that line too.
        XCTAssertTrue(
            hasChromeDot(rep, near: CGPoint(x: 650, y: 100)),
            "the selection's top edge must carry a dotted rule running to the display's right edge")
    }

    // MARK: The clipping holds in pixels too

    /// A selection flush against a display edge draws NO rule along that
    /// edge: the display's own edge already says where the capture ends, and
    /// a rule there could only imply a farther edge that does not exist.
    func testASelectionFlushWithTheDisplayEdgeCarriesNoRuleAlongIt() throws {
        let view = makeView()
        let window = try hostWindow(view)
        defer { window.orderOut(nil) }

        view.beginAreaSelection()
        view.landAreaFrame(makeSolidImage(width: 1800, height: 1200, red: 0.1, green: 0.9, blue: 0.2))
        view.mouseDown(with: mouseEvent(.leftMouseDown, at: CGPoint(x: 0, y: 200), window: window))
        view.mouseDragged(with: mouseEvent(.leftMouseDragged, at: CGPoint(x: 400, y: 300), window: window))

        let rep = try render(view)
        // Scan the display's left edge for chrome dots (outside the
        // selection's own y range, so the drag's border stroke cannot count):
        // nothing may paint there — no rule, no implied edge beyond the
        // display.
        var foundChrome = false
        for y in 5..<190 where foundChrome == false {
            foundChrome = hasChromeDot(rep, near: CGPoint(x: 1, y: CGFloat(y)), radius: 2)
        }
        for y in 310..<595 where foundChrome == false {
            foundChrome = hasChromeDot(rep, near: CGPoint(x: 1, y: CGFloat(y)), radius: 2)
        }
        XCTAssertFalse(foundChrome, "no rule may paint along the display's left edge")
    }

    // MARK: The preference turns exactly the guides off

    /// `showAreaGuides` off, through a real preferences model: the guides'
    /// dots vanish, while the loupe — the other piece of chrome — keeps
    /// painting, so turning one off removes EXACTLY that piece.
    func testTurningTheGuidesOffRemovesOnlyTheGuides() throws {
        let model = PreferencesModel(store: InMemoryPreferenceStore())
        model.capture.showAreaGuides = false
        let state = EditorState(preferences: model)
        let view = makeView(state: state)
        let window = try hostWindow(view)
        defer { window.orderOut(nil) }

        view.beginAreaSelection()
        view.landAreaFrame(makeSolidImage(width: 1800, height: 1200, red: 1, green: 0, blue: 1))
        view.mouseDown(with: mouseEvent(.leftMouseDown, at: CGPoint(x: 100, y: 100), window: window))
        view.mouseDragged(with: mouseEvent(.leftMouseDragged, at: CGPoint(x: 400, y: 300), window: window))

        let rep = try render(view)
        XCTAssertFalse(
            hasChromeDot(rep, near: CGPoint(x: 400, y: 450)),
            "with the preference off, no guide dot paints where one did")
        XCTAssertFalse(
            hasChromeDot(rep, near: CGPoint(x: 650, y: 100)),
            "with the preference off, no guide dot paints where one did")
        // The loupe is the other chrome and must survive: its ring's top edge
        // sits below-right of the last drag point (400, 300), frame
        // (424, 324, 120, 120).
        XCTAssertTrue(
            hasChromeDot(rep, near: CGPoint(x: 484, y: 324)),
            "turning the guides off must not take the loupe down with them")
    }

    /// Detached state (capture editor, selftest) keeps the shipped ON default
    /// in memory (S2): nobody has to discover the chrome to get it.
    func testADetachedStateKeepsTheShippedOnDefaults() {
        let state = EditorState()
        XCTAssertEqual(state.showAreaLoupe, true)
        XCTAssertEqual(state.showAreaGuides, true)
    }
}

/// The same in-memory store the settings render tests use, so the probe never
/// touches the user's real preferences.
private final class InMemoryPreferenceStore: PreferenceStore {
    private var values: [String: Any] = [:]
    func object(forKey key: String) -> Any? { values[key] }
    func set(_ value: Any?, forKey key: String) { values[key] = value }
}
