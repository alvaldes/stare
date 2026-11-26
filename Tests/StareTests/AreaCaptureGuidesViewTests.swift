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
    /// of `point`: the guides' grey (S5) dotted top stroke — with its dark
    /// under-stroke — over the frozen scene and its shroud must clear
    /// everything the scene itself can paint there. Threshold re-derived
    /// under S5: the grey dot's brightest row reads ≈ 0.48–0.51 in the min
    /// channel (L5's white peaked at 0.655), while the dark scene and its
    /// α 0.18/0.32 shroud band read ≤ 0.16, so 0.40 separates them.
    private func hasChromeDot(_ rep: NSBitmapImageRep, near point: CGPoint, radius: CGFloat = 3) -> Bool {
        for x in Int(point.x - radius)...Int(point.x + radius) {
            for y in Int(point.y - radius)...Int(point.y + radius) {
                guard x >= 0, y >= 0, x < rep.pixelsWide, y < rep.pixelsHigh,
                    let color = rep.colorAt(x: x, y: y)
                else { continue }
                if min(color.redComponent, color.greenComponent, color.blueComponent) > 0.4 { return true }
            }
        }
        return false
    }

    /// A bare `mouseMoved` event (no click), the delivery the armed state's
    /// chrome lives on.
    private func mouseMoved(at viewPoint: CGPoint, window: NSWindow, on view: OverlayView) {
        view.mouseMoved(with: mouseEvent(.mouseMoved, at: viewPoint, window: window))
    }

    /// The min colour channel at one bitmap pixel, 0 outside the bitmap, so
    /// run detection needs no guards.
    private func minChannel(_ rep: NSBitmapImageRep, at x: Int, y: Int) -> CGFloat {
        guard x >= 0, y >= 0, x < rep.pixelsWide, y < rep.pixelsHigh,
            let color = rep.colorAt(x: x, y: y)
        else { return 0 }
        return min(color.redComponent, color.greenComponent, color.blueComponent)
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

    // MARK: The armed cursor is always the crosshair (S5)

    /// "el cursor siempre debe ser la cruz": the canvas's single answered-
    /// cursor decision answers the system crosshair while area mode is
    /// armed, for EVERY tool — the system-crosshair drafting tools and the
    /// drawn glyphs alike. Outside area mode that same decision answers each
    /// tool's own cursor again, exactly as before, so nothing outside area
    /// mode changed.
    func testWhileArmedEveryToolAnswersTheCrosshairOutsideItEachToolSOwnCursorAnswers() {
        for tool in Tool.allCases {
            let state = EditorState()
            state.tool = tool
            let view = OverlayView(
                frame: CGRect(origin: .zero, size: size), state: state, onEscape: {})
            XCTAssertTrue(
                view.answeredCursor() === OverlayView.cursor(for: tool.cursor),
                "\(tool.rawValue), not armed, must answer its own cursor, as before")
            view.beginAreaSelection()
            XCTAssertTrue(
                view.answeredCursor() === NSCursor.crosshair,
                "\(tool.rawValue) armed must answer the crosshair, never an own cursor")
        }
    }

    /// Leaving area mode restores the tool's own cursor through the same
    /// single answered-cursor path — both ways out: Esc cancels the armed
    /// mode, and a finished drag disarms. (A drawn glyph tool, the pen, is
    /// the sharpest witness: its cursor is a glyph, not a system crosshair.)
    func testLeavingAreaModeRestoresTheToolCursorThroughEscAndThroughADrag() throws {
        let state = EditorState()
        state.tool = .pen
        let view = makeView(state: state)
        let window = try hostWindow(view)
        defer { window.orderOut(nil) }

        view.beginAreaSelection()
        XCTAssertTrue(
            view.answeredCursor() === NSCursor.crosshair, "armed → the crosshair answers")

        view.keyDown(with: NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
            windowNumber: window.windowNumber, context: nil, characters: "",
            charactersIgnoringModifiers: "", isARepeat: false, keyCode: 53)!)
        XCTAssertTrue(
            view.answeredCursor() === OverlayView.cursor(for: .penDot),
            "Esc disarms: the pen's own cursor answers again, same path")

        view.beginAreaSelection()
        XCTAssertTrue(
            view.answeredCursor() === NSCursor.crosshair, "armed again → crosshair")
        view.mouseDown(with: mouseEvent(.leftMouseDown, at: CGPoint(x: 100, y: 100), window: window))
        view.mouseDragged(with: mouseEvent(.leftMouseDragged, at: CGPoint(x: 300, y: 200), window: window))
        XCTAssertTrue(
            view.answeredCursor() === NSCursor.crosshair, "still armed mid-drag")
        view.mouseUp(with: mouseEvent(.leftMouseUp, at: CGPoint(x: 300, y: 200), window: window))
        XCTAssertTrue(
            view.answeredCursor() === OverlayView.cursor(for: .penDot),
            "the drag's disarm answers the pen's own cursor again, same path")
    }

    // MARK: S5 — airier, smaller dots, measured off the screen

    /// "agrega mas espacio entre los puntos y bajale un poco el tamanno":
    /// the RENDERED run pattern along the pointer's vertical rule — not the
    /// constants — must read dots of the new pitch (`dotLength + gapLength`
    /// = 6.75, L5's was 4), each a tiny run (a round-capped dot), with the
    /// air between them dominating the stroke.
    func testTheRenderedRuleMeasuresTheAirierSmallerDotPattern() throws {
        let view = makeView()
        let window = try hostWindow(view)
        defer { window.orderOut(nil) }

        view.beginAreaSelection()
        view.landAreaFrame(makeSolidImage(width: 1800, height: 1200, red: 0.1, green: 0.9, blue: 0.2))
        mouseMoved(at: CGPoint(x: 400, y: 200), window: window, on: view)
        let rep = try render(view)

        // Contiguous runs above the chrome threshold along the rule's own
        // column — clear of the horizontal rule at y = 200, the loupe's
        // frame (which hangs right of x ≥ 424 for the pointer at (400, 200))
        // and the display's bottom edge.
        var runs: [(start: Int, end: Int, peak: CGFloat)] = []
        for y in 430..<596 {
            let value = minChannel(rep, at: 400, y: y)
            let bright = value > 0.4
            if bright {
                if let last = runs.last, last.end == y - 1 {
                    runs[runs.count - 1] = (last.start, y, max(last.peak, value))
                } else {
                    runs.append((y, y, value))
                }
            }
        }
        XCTAssertGreaterThanOrEqual(runs.count, 18, "a sizeable sample of dots along the rule")
        for run in runs {
            XCTAssertLessThanOrEqual(
                run.end - run.start + 1, 3, "each run is a dot (a few pixels), never a dash line")
            // S5: the grey dot's sampled peak — the legibility floor and the
            // grey ceiling together. (L5's near-white chrome read 0.655 over
            // this same scene; the grey 0.75/α 0.9 top stroke reads 0.48–0.51.)
            XCTAssertGreaterThan(run.peak, 0.42, "the grey dot is still visible over the dark scene")
            XCTAssertLessThanOrEqual(
                run.peak, 0.55, "S5 grey — L5's near-white chrome read 0.655 over this same scene")
        }
        for i in 1..<runs.count {
            let centreA = CGFloat(runs[i - 1].start + runs[i - 1].end - 1) / 2
            let centreB = CGFloat(runs[i].start + runs[i].end - 1) / 2
            XCTAssertEqual(
                centreB - centreA, 6.75, accuracy: 1.25,
                "S5: the dots sit at the new pitch \(AreaCaptureGuides.dotLength + AreaCaptureGuides.gapLength) = 6.75, not L5's 4")
        }
        // And most of the rule is air: less than half the scanned span is
        // dot (L5's dense pattern came near half).
        let brightRows = runs.reduce(0) { $0 + $1.end - $1.start + 1 }
        XCTAssertLessThan(
            CGFloat(brightRows) / 166.0, 0.5, "S5: the air between dots dominates the rule now")
    }

    // MARK: S5 — greyer lines, still reading over both scenes

    /// "un color mas gris no tan blanco": over a LIGHT frozen scene the
    /// sampled dot reads grey — well under the near-white chrome L5 pinned
    /// (min ≈ 0.73 of his white stroke over the same white scene) — and the
    /// dark under-stroke keeps it visible. Visibility over a DARK scene is
    /// the `hasChromeDot` assertions above, which stay green with the grey.
    /// "un color mas gris no tan blanco": over a LIGHT frozen scene the dot
    /// DIPS below the bare band (α 0.18 shroud over the white scene reads
    /// 0.82 in the min channel) — the sampled dips read grey ≈ 0.69–0.73,
    /// where the near-white top stroke L5 pinned would read a couple of
    /// tenths brighter. The measured old-vs-new discriminator lives in the
    /// dark-scene test above (0.655 → ≤ 0.55); this one pins the light-side
    /// read: grey, still sampled-visible (its grey dips to ≈ 0.69, over a
    /// quarter darker than the band), at the same 6.75 pitch.
    func testTheGuideDotsReadGreyOverALightSceneAndStayVisibleOverADarkOne() throws {
        let view = makeView()
        let window = try hostWindow(view)
        defer { window.orderOut(nil) }

        view.beginAreaSelection()
        view.landAreaFrame(makeSolidImage(width: 1800, height: 1200, red: 1, green: 1, blue: 1))
        mouseMoved(at: CGPoint(x: 400, y: 200), window: window, on: view)
        let rep = try render(view)

        // Contiguous runs BELOW the grey-header threshold along the rule's
        // own column — a dot reads darker than the bare white band.
        var dips: [(start: Int, end: Int, deep: CGFloat, bright: CGFloat)] = []
        for y in 430..<596 {
            let value = minChannel(rep, at: 400, y: y)
            let dipped = value < 0.79
            if dipped {
                if let last = dips.last, last.end == y - 1 {
                    dips[dips.count - 1] = (last.start, y, min(last.deep, value), max(last.bright, value))
                } else {
                    dips.append((y, y, value, value))
                }
            }
        }
        XCTAssertGreaterThanOrEqual(dips.count, 18, "a sizeable sample of dots along the rule")
        for dip in dips {
            XCTAssertLessThanOrEqual(dip.end - dip.start + 1, 4, "each dip is a dot, not a stripe")
            XCTAssertGreaterThan(
                dip.deep, 0.58, "S5: still visible over the light scene — the grey dot dips below the 0.82 band"
                    + " (measured dips read 0.62–0.73)")
            XCTAssertLessThanOrEqual(
                dip.bright, 0.78, "S5: grey — dips stay well under the near-white chrome (the bare band reads 0.82)")
        }
        for i in 1..<dips.count {
            let centreA = CGFloat(dips[i - 1].start + dips[i - 1].end - 1) / 2
            let centreB = CGFloat(dips[i].start + dips[i].end - 1) / 2
            XCTAssertEqual(
                centreB - centreA, 6.75, accuracy: 1.25,
                "S5: the darker-than-band dots sit at the new pitch 6.75")
        }
    }
}

/// The same in-memory store the settings render tests use, so the probe never
/// touches the user's real preferences.
private final class InMemoryPreferenceStore: PreferenceStore {
    private var values: [String: Any] = [:]
    func object(forKey key: String) -> Any? { values[key] }
    func set(_ value: Any?, forKey key: String) { values[key] = value }
}
