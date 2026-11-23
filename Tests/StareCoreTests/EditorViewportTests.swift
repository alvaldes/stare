import CoreGraphics
import XCTest
@testable import StareCore

/// S16/T9: the capture editor's viewport — zoom and pan over the capture.
/// The viewport is a pure value in StareCore so every rule is pinneable
/// without a window, the same discipline `BoardTransform` set for the board:
/// the canvas (`CaptureEditorCanvas`) is only a view over it.
///
/// The state is two numbers. `zoom` scales the capture's fitted display about
/// a view point (the app's anchoring rule: what is under the pointer stays
/// under the pointer), and `pan` shifts the scaled result in view points.
/// The clamp keeps the image on screen in every state:
///
/// - An axis the image covers (it is at least as long as the viewport) can
///   slide freely but can never open a gap with the viewport edge — once the
///   image is bigger than the window, one of its edges always stays in it.
/// - An axis the image does not cover keeps the image fully inside the
///   viewport, so panning can never push even a corner out of sight.
///
/// At the fit (zoom 1) both rules reduce to the fitted placement itself: the
/// identity viewport is a fixed point of every transition, which is what ⌘0
/// returns to.
final class EditorViewportTests: XCTestCase {

    private let canvas = CGRect(x: 0, y: 0, width: 300, height: 200)
    /// A capture fitted wide: the x axis covers the canvas, the y axis is
    /// letterboxed (the fitted rect is taller than the image? no — shorter:
    /// the image's fitted display is 300×100 inside 300×200).
    private let wideFit = CGRect(x: 0, y: 50, width: 300, height: 100)
    /// A capture fitted tall: y covers, x is letterboxed (200×200 in 300×200).
    private let tallFit = CGRect(x: 50, y: 0, width: 200, height: 200)

    // MARK: - Identity

    func testTheIdentityViewportPlacesTheFitExactly() {
        XCTAssertEqual(
            EditorViewport.identity.displayRect(fit: tallFit, canvas: canvas),
            tallFit,
            "at the fit the viewport must leave the fitted placement exactly as it is")
        XCTAssertEqual(
            EditorViewport.identity.displayRect(fit: wideFit, canvas: canvas),
            wideFit)
        let point = CGPoint(x: 150, y: 100)
        XCTAssertEqual(
            EditorViewport.identity.viewPoint(fromFit: point, fit: tallFit, canvas: canvas),
            point,
            "the identity viewport is the identity mapping on points too")
    }

    func testTheIdentityViewportIsAFixedPointOfZoomPanAndClamp() {
        let viewports: [EditorViewport] = [
            EditorViewport.identity,
            // ⌘− at the fit is below the minimum: the viewport does not move
            // and the fit stays exact (no float drift from inverting a step).
            EditorViewport.identity.zoomed(byStep: 1 / EditorViewport.zoomStep, anchoredAt: CGPoint(x: 150, y: 100), fit: wideFit, canvas: canvas),
        ]
        for viewport in viewports {
            XCTAssertEqual(
                viewport.displayRect(fit: wideFit, canvas: canvas),
                wideFit,
                "a zoom in and back out must return the fit exactly")
            XCTAssertEqual(
                viewport.panned(by: .zero, fit: wideFit, canvas: canvas),
                EditorViewport.identity,
                "a zero pan changes nothing")
            XCTAssertEqual(
                viewport.clamped(fit: wideFit, canvas: canvas),
                EditorViewport.identity,
                "clamping the fit must return the fit itself")
        }
    }

    // MARK: - Anchored zoom

    /// S16's own test: the fit point under the anchor stays under the anchor.
    /// Several zooms, both anchors and directions, always on interior states
    /// the clamp does not touch.
    func testZoomAboutAPointKeepsTheFitPointUnderItFixed() {
        let states: [(EditorViewport, CGRect, CGPoint)] = [
            (EditorViewport.identity.zoomed(to: 1.25, anchoredAt: CGPoint(x: 150, y: 100), fit: wideFit, canvas: canvas), wideFit, CGPoint(x: 150, y: 100)),
            (EditorViewport.identity.zoomed(to: 3, anchoredAt: CGPoint(x: 150, y: 100), fit: wideFit, canvas: canvas), wideFit, CGPoint(x: 150, y: 100)),
            (EditorViewport.identity.zoomed(to: 8, anchoredAt: CGPoint(x: 20, y: 60), fit: wideFit, canvas: canvas), wideFit, CGPoint(x: 20, y: 60)),
            (EditorViewport.identity.zoomed(to: 8, anchoredAt: CGPoint(x: 150, y: 100), fit: tallFit, canvas: canvas), tallFit, CGPoint(x: 150, y: 100)),
            // Zooming out from a zoomed state about the same anchor.
            (EditorViewport.identity.zoomed(to: 4, anchoredAt: CGPoint(x: 150, y: 100), fit: wideFit, canvas: canvas)
                .zoomed(to: 2, anchoredAt: CGPoint(x: 150, y: 100), fit: wideFit, canvas: canvas), wideFit, CGPoint(x: 150, y: 100)),
        ]
        for (viewport, fit, anchor) in states {
            XCTAssertEqual(
                viewport.fitPoint(fromView: anchor, fit: fit, canvas: canvas),
                EditorViewport.identity.fitPoint(fromView: anchor, fit: fit, canvas: canvas),
                "the fit point under the anchor \(anchor) must not move")
            XCTAssertEqual(
                viewport.viewPoint(
                    fromFit: EditorViewport.identity.fitPoint(fromView: anchor, fit: fit, canvas: canvas),
                    fit: fit, canvas: canvas),
                anchor,
                "and the anchor must still show that fit point after the zoom")
        }
    }

    func testZoomClampsIntoItsRange() {
        let zoomed = EditorViewport.identity.zoomed(to: 100, anchoredAt: CGPoint(x: 150, y: 100), fit: wideFit, canvas: canvas)
        XCTAssertEqual(zoomed.zoom, EditorViewport.maxZoom, "a wild zoom-in target clamps to the maximum")
        XCTAssertEqual(zoomed.zoom, 8)

        XCTAssertEqual(
            EditorViewport.identity.zoomed(to: 0.5, anchoredAt: CGPoint(x: 150, y: 100), fit: wideFit, canvas: canvas),
            EditorViewport.identity,
            "below the minimum zoom the viewport does not change: the fit already shows the whole capture")

        let out = EditorViewport.identity
            .zoomed(to: EditorViewport.maxZoom, anchoredAt: CGPoint(x: 150, y: 100), fit: wideFit, canvas: canvas)
            .zoomed(to: 20, anchoredAt: CGPoint(x: 150, y: 100), fit: wideFit, canvas: canvas)
        XCTAssertEqual(out.zoom, EditorViewport.maxZoom, "zooming out past the ceiling stays at the ceiling")
    }

    // MARK: - The clamp keeps the image in sight

    func testAnAxisTheImageCoversCanPanButNeverOpensAGap() {
        // wideFit covers both axes at zoom 4: any pan keeps one edge glued to
        // the viewport edge on each axis — no backdrop gap can open.
        let zoomed = EditorViewport.identity.zoomed(to: 4, anchoredAt: CGPoint(x: 150, y: 100), fit: wideFit, canvas: canvas)
        let states = [
            zoomed.panned(by: CGSize(width: 9_999, height: -9_999), fit: wideFit, canvas: canvas),
            zoomed.panned(by: CGSize(width: -9_999, height: 9_999), fit: wideFit, canvas: canvas),
        ]
        for viewport in states {
            let display = viewport.displayRect(fit: wideFit, canvas: canvas)
            XCTAssertLessThanOrEqual(display.minX, canvas.minX, "the covered x axis must not leave a gap at the left")
            XCTAssertGreaterThanOrEqual(display.maxX, canvas.maxX, "the covered x axis must not leave a gap at the right")
            XCTAssertLessThanOrEqual(display.minY, canvas.minY, "the covered y axis must not leave a gap at the top")
            XCTAssertGreaterThanOrEqual(display.maxY, canvas.maxY, "the covered y axis must not leave a gap at the bottom")
        }
    }

    func testAnAxisTheImageDoesNotCoverCannotLeaveTheViewport() {
        // tallFit's x axis (200 pt in a 300 pt canvas) is letterboxed at the
        // fit: panning slides it inside the letterbox slack, never past it.
        XCTAssertEqual(
            EditorViewport.identity.panned(by: CGSize(width: 60, height: 0), fit: tallFit, canvas: canvas)
                .displayRect(fit: tallFit, canvas: canvas).maxX,
            canvas.maxX,
            "panning right stops with the image's right edge at the canvas edge")
        XCTAssertEqual(
            EditorViewport.identity.panned(by: CGSize(width: -60, height: 0), fit: tallFit, canvas: canvas)
                .displayRect(fit: tallFit, canvas: canvas).minX,
            canvas.minX,
            "panning left stops with the image's left edge at the canvas edge")
    }

    // MARK: - Mapping round trip

    func testPointsRoundTripThroughSeveralZoomAndPanStates() {
        let states: [EditorViewport] = [
            EditorViewport.identity,
            EditorViewport(zoom: 2, pan: CGSize(width: 10, height: -4)).clamped(fit: wideFit, canvas: canvas),
            EditorViewport(zoom: 8, pan: CGSize(width: -120, height: -80)).clamped(fit: wideFit, canvas: canvas),
            EditorViewport.identity.zoomed(to: 3, anchoredAt: CGPoint(x: 150, y: 120), fit: tallFit, canvas: canvas),
        ]
        let points = [
            CGPoint(x: 150, y: 100),
            CGPoint(x: 80, y: 60),
            CGPoint(x: 220, y: 30),
        ]
        for viewport in states {
            for point in points {
                let view = viewport.viewPoint(fromFit: point, fit: wideFit, canvas: canvas)
                let roundTrip = viewport.fitPoint(fromView: view, fit: wideFit, canvas: canvas)
                XCTAssertEqual(
                    roundTrip.x, point.x, accuracy: 0.0001,
                    "the fit ↔ view mapping must invert itself at zoom \(viewport.zoom), pan \(viewport.pan)")
                XCTAssertEqual(
                    roundTrip.y, point.y, accuracy: 0.0001,
                    "the fit ↔ view mapping must invert itself at zoom \(viewport.zoom), pan \(viewport.pan)")
            }
        }
    }

    func testPanFollowsThePointerInsideTheClamp() {
        // Interior drag, wideFit's y slack: 100 pt of letterbox, centred, so
        // a 20 pt drag down shifts the content down 20 pt and no clamping
        // intervenes.
        let panned = EditorViewport.identity.panned(by: CGSize(width: 0, height: 20), fit: wideFit, canvas: canvas)
        XCTAssertEqual(
            panned.displayRect(fit: wideFit, canvas: canvas),
            CGRect(x: 0, y: 70, width: 300, height: 100),
            "the content follows the drag one to one in view points while the clamp stays quiet")
    }

    // MARK: - The scroll-pan gate (review: direction + momentum)

    /// The default setting keeps the direction the editor has always panned
    /// in: AppKit's raw content-directed delta
    func testTheGatePansTheRawDeltaWhenTheDeviceIsNotInverted() {
        XCTAssertEqual(
            ScrollPan.decide(for: ScrollPan.Event(deltaX: 12, deltaY: 30, isDirectionInvertedFromDevice: false)),
            .pan(delta: CGSize(width: 12, height: 30)),
            "without inversion the felt direction is the raw delta's, exactly as the editor has always panned")
    }

    /// Natural scrolling inverts the raw deltas' relationship to the felt
    /// direction: the same physical gesture must pan the same way on a
    /// device with the setting and on one without it.
    func testAnInvertedDevicePansTheSameFeltDirectionAsAnotherWithoutInversion() {
        let plain = ScrollPan.decide(for: ScrollPan.Event(deltaX: 12, deltaY: 30, isDirectionInvertedFromDevice: false))
        let inverted = ScrollPan.decide(for: ScrollPan.Event(deltaX: -12, deltaY: -30, isDirectionInvertedFromDevice: true))
        XCTAssertEqual(inverted, plain, "the same physical gesture must pan the same felt direction whatever the natural-scrolling setting says")
        XCTAssertEqual(inverted, .pan(delta: CGSize(width: 12, height: 30)), "natural scrolling must not flip the felt direction")
    }

    /// The zoom gesture's own discipline — momentum belongs to no live
    /// gesture (v0.5/S2) — now says so for panning too: a flick's tail moves
    /// nothing, however large its delta.
    func testTheMomentumTailNeverPans() {
        for phase in [ScrollZoom.MomentumPhase.begin, .continued, .end] {
            XCTAssertEqual(
                ScrollPan.decide(for: ScrollPan.Event(deltaX: 40, deltaY: 300, momentumPhase: phase)),
                .ignore,
                "momentum phase \(phase) belongs to no live gesture and must neither pan nor zoom")
        }
    }

    /// The gate's routing is unchanged where the review touched nothing: ⌘
    /// held sends the event to the zoom gesture, and a non-⌘ event while the
    /// gesture holds is its wind-down, which pans nothing.
    func testTheGateRoutesZoomAndTheGestureWindDownAsBefore() {
        XCTAssertEqual(
            ScrollPan.decide(for: ScrollPan.Event(deltaY: 30, commandHeld: true)),
            .zoom,
            "⌘ + scroll belongs to the zoom gesture")
        XCTAssertEqual(
            ScrollPan.decide(for: ScrollPan.Event(deltaY: 30, commandHeld: false, zoomGestureLive: true)),
            .ignore,
            "a non-⌘ event while the zoom gesture holds is its wind-down")
    }
}
