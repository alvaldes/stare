import AppKit
import XCTest

@testable import Stare
import StareCore

/// The area drag's dotted guides at the view layer (S4): the pointer's
/// crosshair — one vertical and one horizontal dotted rule through the
/// pointer, out to the display's edges — present from the moment area mode
/// arms (no click needed) and during the drag, where the origin's edges the
/// first version ruled must never paint again. Painted over the real
/// `OverlayView` and asserted in pixels — the same real-view bitmap pattern
/// the freeze tests established. The windows these tests open are confined
/// to the primary screen (`PrimaryScreenTestWindow`), never the user's other
/// monitors.
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

    /// A bare `mouseMoved` event (no click), the delivery the armed state's
    /// chrome lives on.
    private func mouseMoved(at viewPoint: CGPoint, window: NSWindow, on view: OverlayView) {
        view.mouseMoved(with: mouseEvent(.mouseMoved, at: viewPoint, window: window))
    }

    // MARK: The chrome exists with no click at all

    /// ⇧S arms the mode and the pointer's crosshair is on screen before any
    /// mouse-down (S4, the owner's complaint "debe salir desde que se presiona
    /// shift+S no al hacer click"): arming, a bare `mouseMoved` through the
    /// real delivery method, and the vertical rule through the pointer
    /// sampled mid-display and the horizontal rule sampled right of the
    /// loupe's frame — plus the loupe painting already, over its frozen
    /// frame at the pointer.
    func testArmedWithNoClickThePointerCrosshairAndLoupeAreOnScreen() throws {
        let view = makeView()
        let window = try hostWindow(view)
        defer { window.orderOut(nil) }

        view.beginAreaSelection()
        view.landAreaFrame(makeSolidImage(width: 1800, height: 1200, red: 0.1, green: 0.9, blue: 0.2))
        mouseMoved(at: CGPoint(x: 400, y: 200), window: window, on: view)

        let rep = try render(view)
        // The pointer's vertical rule runs at x = 400 through the full
        // display height: a dot must sit on it below the loupe's frame.
        XCTAssertTrue(
            hasChromeDot(rep, near: CGPoint(x: 400, y: 450)),
            "with area mode armed there is a vertical rule through the pointer, no click needed")
        // The pointer's horizontal rule runs at y = 200, right of the loupe's
        // frame (which hangs at (424, 224)).
        XCTAssertTrue(
            hasChromeDot(rep, near: CGPoint(x: 700, y: 200)),
            "with area mode armed there is a horizontal rule through the pointer, no click needed")
        // The loupe is the same pointer's chrome and paints from the same
        // moment: its ring's top edge at the frame the plan hangs below-right
        // of (400, 200) — (424, 224, 120, 120).
        XCTAssertTrue(
            hasChromeDot(rep, near: CGPoint(x: 484, y: 224)),
            "the loupe also paints while area mode is armed with no click")
    }

    // MARK: During a drag, exactly one rule per axis — the pointer's

    /// Dragging from (100, 100) to (400, 300): only the POINTER's rules may
    /// paint. The origin's rules at x = 100 and y = 100 — the reported defect
    /// — must be absent where they ran in the first version (x = 100 below
    /// the selection, y = 100 right of it), while the pointer's rules at
    /// x = 400 and y = 300 are on screen.
    func testDuringADragOnlyThePointerSRulesPaintNeverTheOriginS() throws {
        let view = makeView()
        let window = try hostWindow(view)
        defer { window.orderOut(nil) }

        view.beginAreaSelection()
        view.landAreaFrame(makeSolidImage(width: 1800, height: 1200, red: 0.1, green: 0.9, blue: 0.2))
        view.mouseDown(with: mouseEvent(.leftMouseDown, at: CGPoint(x: 100, y: 100), window: window))
        view.mouseDragged(with: mouseEvent(.leftMouseDragged, at: CGPoint(x: 400, y: 300), window: window))

        let rep = try render(view)
        // The pointer's vertical rule at x = 400 runs below the selection to
        // the display's bottom edge: a dot must sit on that line.
        XCTAssertTrue(
            hasChromeDot(rep, near: CGPoint(x: 400, y: 450)),
            "the pointer's vertical rule paints during the drag")
        // The pointer's horizontal rule at y = 300 runs right of the
        // selection (the loupe hangs at (424, 324), so x = 650 is clear).
        XCTAssertTrue(
            hasChromeDot(rep, near: CGPoint(x: 650, y: 300)),
            "the pointer's horizontal rule paints during the drag")
        // The ORIGIN's rules — the defect — must paint nothing: x = 100 below
        // the selection and y = 100 right of it (the loupe frame tops out at
        // x = 544, well short of 650).
        XCTAssertFalse(
            hasChromeDot(rep, near: CGPoint(x: 100, y: 450)),
            "the origin's vertical rule must not paint during the drag")
        XCTAssertFalse(
            hasChromeDot(rep, near: CGPoint(x: 650, y: 100)),
            "the origin's horizontal rule must not paint during the drag")
    }

    // MARK: The clipping holds in pixels too

    /// A pointer sitting exactly on a display edge draws no rule along that
    /// edge: the display's own edge already says where the screen ends, and a
    /// rule there could only imply a farther edge that does not exist. The
    /// perpendicular rule through the pointer keeps its place.
    func testAPointerOnTheDisplayEdgeCarriesNoRuleAlongIt() throws {
        let view = makeView()
        let window = try hostWindow(view)
        defer { window.orderOut(nil) }

        view.beginAreaSelection()
        view.landAreaFrame(makeSolidImage(width: 1800, height: 1200, red: 0.1, green: 0.9, blue: 0.2))
        mouseMoved(at: CGPoint(x: 0, y: 200), window: window, on: view)

        let rep = try render(view)
        // Scan the display's left edge for chrome dots, outside the
        // horizontal rule's own y range (its neighbourhood), so nothing may
        // paint there — no rule along the display's boundary.
        var foundChrome = false
        func ruleNeighbourhood(_ y: Int) -> Bool { y >= 195 && y < 206 }
        for y in 0..<200 where foundChrome == false && !ruleNeighbourhood(y) {
            foundChrome = hasChromeDot(rep, near: CGPoint(x: 1, y: CGFloat(y)), radius: 2)
        }
        for y in 210..<598 where foundChrome == false {
            foundChrome = hasChromeDot(rep, near: CGPoint(x: 1, y: CGFloat(y)), radius: 2)
        }
        XCTAssertFalse(foundChrome, "no rule may paint along the display's left edge")
        // The perpendicular rule stays: the horizontal rule through the
        // pointer reaches the display.
        XCTAssertTrue(
            hasChromeDot(rep, near: CGPoint(x: 80, y: 200)),
            "the horizontal rule through the pointer still paints past the edge point")
    }

    /// A pointer not on this display draws nothing (S4's clipping): the
    /// crosshair rules and the loupe go dark here — `mouseExited` is the
    /// delivery of the pointer leaving, the same tracking area that brings
    /// the moves in.
    func testAPointerLeavingTheDisplayDrawsNothing() throws {
        let view = makeView()
        let window = try hostWindow(view)
        defer { window.orderOut(nil) }

        view.beginAreaSelection()
        view.landAreaFrame(makeSolidImage(width: 1800, height: 1200, red: 0.1, green: 0.9, blue: 0.2))
        mouseMoved(at: CGPoint(x: 400, y: 300), window: window, on: view)
        let before = try render(view)
        XCTAssertTrue(
            hasChromeDot(before, near: CGPoint(x: 400, y: 450)),
            "the chrome paints while the pointer is on the display")

        // An `NSEvent` cannot be synthesized for the exit type itself, but
        // the handler reads nothing from the event — going armed is the
        // whole decision.
        view.mouseExited(with: mouseEvent(.mouseMoved, at: CGPoint(x: 950, y: 640), window: window))
        let rep = try render(view)
        XCTAssertFalse(
            hasChromeDot(rep, near: CGPoint(x: 400, y: 450)),
            "no vertical rule may paint for a pointer off the display")
        XCTAssertFalse(
            hasChromeDot(rep, near: CGPoint(x: 650, y: 300)),
            "no horizontal rule may paint for a pointer off the display")
        XCTAssertFalse(
            hasChromeDot(rep, near: CGPoint(x: 484, y: 324)),
            "the loupe too must stay absent for a pointer off the display")
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
        mouseMoved(at: CGPoint(x: 100, y: 100), window: window, on: view)
        view.mouseDown(with: mouseEvent(.leftMouseDown, at: CGPoint(x: 100, y: 100), window: window))
        view.mouseDragged(with: mouseEvent(.leftMouseDragged, at: CGPoint(x: 400, y: 300), window: window))

        let rep = try render(view)
        XCTAssertFalse(
            hasChromeDot(rep, near: CGPoint(x: 400, y: 450)),
            "with the preference off, no guide dot paints where one did")
        XCTAssertFalse(
            hasChromeDot(rep, near: CGPoint(x: 650, y: 300)),
            "with the preference off, no guide dot paints where one did")
        // The loupe is the other chrome and must survive: its ring's top edge
        // sits below-right of the last pointer point (400, 300), frame
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
