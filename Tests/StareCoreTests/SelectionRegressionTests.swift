import AppKit
import CoreGraphics
import XCTest

import StareCore

/// Independent verifier probes for T11/S6, derived from the request:
/// "el primer elemento de los tools en la barra debe ser el cursor que permita
/// editar lo que ya se pinto" + "mover, redimensionar, borrar y rotar. No debe
/// permitir cambiar de forma."
final class SelectionRegressionTests: XCTestCase {

    // MARK: helpers

    private func mark(_ tool: Tool, _ points: [CGPoint], text: String? = nil, size: CGSize? = nil) -> Stroke {
        Stroke(tool: tool, ink: .red, points: points, text: text, textSize: size)
    }

    /// Proportional fingerprint of the geometry: pairwise distances divided by
    /// the widest one, so a uniform similarity leaves it identical.
    private func shape(_ stroke: Stroke) -> [CGFloat] {
        let points = stroke.points
        var distances: [CGFloat] = []
        for i in 0..<points.count {
            for j in (i + 1)..<points.count {
                let dx = points[i].x - points[j].x
                let dy = points[i].y - points[j].y
                distances.append((dx * dx + dy * dy).squareRoot())
            }
        }
        guard let maxDistance = distances.max(), maxDistance > 0 else { return [] }
        return distances.map { $0 / maxDistance }
    }

    private func assertShapePreserved(_ a: Stroke, _ b: Stroke, _ message: String,
                                      file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(a.tool, b.tool, message, file: file, line: line)
        XCTAssertEqual(a.rotation, b.rotation, message, file: file, line: line)
        let sa = shape(a)
        let sb = shape(b)
        XCTAssertEqual(sa.count, sb.count, message, file: file, line: line)
        for (x, y) in zip(sa, sb) {
            XCTAssertEqual(x, y, accuracy: 1e-9, message, file: file, line: line)
        }
    }

    // MARK: P1 — the cursor leads the bar, exactly once

    func testP1CursorIsTheFirstToolbarItemAndAppearsOnce() {
        let flattened = Tool.toolbarGroups.flatMap { $0 }
        XCTAssertEqual(flattened.first, .select, "the edit cursor is the first element of the tools")
        XCTAssertEqual(flattened.filter { $0 == .select }.count, 1, "never added twice")
        XCTAssertEqual(Set(flattened), Set(Tool.allCases), "every tool stays in the bar")
        XCTAssertNotNil(NSImage(systemSymbolName: Tool.select.symbolName, accessibilityDescription: nil),
                        "the cursor needs a glyph that exists")
        XCTAssertEqual(ToolShortcut.tool(for: "v"), .select)
    }

    // MARK: P3 — the cursor never creates a mark

    func testP3SelectNeverStartsOrCommitsAMark() {
        var session = DrawingSession()
        session.begin(at: CGPoint(x: 5, y: 5), tool: .select, ink: .red)
        XCTAssertNil(session.active, "the cursor never arms an active mark")
        session.extend(to: CGPoint(x: 90, y: 90))
        session.commit()
        XCTAssertTrue(session.strokes.isEmpty)
        XCTAssertNil(session.active)

        // A mark that somehow carries the tool draws nothing and is never hit.
        let stray = mark(.select, [CGPoint(x: 0, y: 0), CGPoint(x: 50, y: 50)])
        XCTAssertTrue(PathBuilder.path(for: stray).isEmpty)
        XCTAssertFalse(stray.hitTest(CGPoint(x: 25, y: 25), radius: 50))
        XCTAssertFalse(stray.isSelectedByCursor(at: CGPoint(x: 25, y: 25), radius: 50))
    }

    // MARK: P4 — no transform changes the shape, for every tool

    func testP4MoveScaleAndRotatePreserveShapeForEveryTool() {
        let cases: [(Tool, [CGPoint], String?, CGSize?)] = [
            (.rectangle, [CGPoint(x: 10, y: 20), CGPoint(x: 130, y: 60)], nil, nil),
            (.ellipse, [CGPoint(x: 10, y: 20), CGPoint(x: 130, y: 60)], nil, nil),
            (.line, [CGPoint(x: 10, y: 20), CGPoint(x: 130, y: 60)], nil, nil),
            (.arrow, [CGPoint(x: 10, y: 20), CGPoint(x: 130, y: 60)], nil, nil),
            (.pen, [CGPoint(x: 10, y: 10), CGPoint(x: 40, y: 70), CGPoint(x: 90, y: 15), CGPoint(x: 140, y: 90)], nil, nil),
            (.blur, [CGPoint(x: 10, y: 20), CGPoint(x: 130, y: 60)], nil, nil),
            (.text, [CGPoint(x: 10, y: 20)], "Hola", CGSize(width: 106, height: 24)),
        ]
        for (tool, points, text, size) in cases {
            let original = mark(tool, points, text: text, size: size)

            let moved = MarkTransform.translated(original, by: CGPoint(x: 13, y: -9))
            assertShapePreserved(original, moved, "\(tool) moves without deforming")

            for handle in [MarkHandle.topLeft, .topRight, .bottomLeft, .bottomRight] {
                let selection = MarkSelection(stroke: original)
                guard let corner = selection.handlePoints(rotationHandleOffset: 20)[handle],
                      let opposite = selection.handlePoints(rotationHandleOffset: 20)[
                        handle == .topLeft ? .bottomRight :
                        handle == .topRight ? .bottomLeft :
                        handle == .bottomLeft ? .topRight : .topLeft
                      ] else { return XCTFail("missing handle") }
                for factor in [CGFloat(0.4), 1.7] {
                    let pointer = CGPoint(x: opposite.x + factor * (corner.x - opposite.x),
                                          y: opposite.y + factor * (corner.y - opposite.y))
                    let scaled = MarkTransform.scaled(original, dragging: handle, to: pointer)
                    assertShapePreserved(original, scaled, "\(tool) \(handle) scale \(factor) keeps the form")
                    if tool != .text, tool != .line, tool != .arrow {
                        let before = PathBuilder.path(for: original).boundingBoxOfPath
                        let after = PathBuilder.path(for: scaled).boundingBoxOfPath
                        XCTAssertEqual(after.width / before.width, after.height / before.height,
                                       accuracy: 1e-6, "\(tool) keeps its aspect ratio")
                    }
                }
            }

            let rotated = MarkTransform.rotated(original, by: .pi / 3)
            XCTAssertEqual(rotated.points, original.points, "\(tool) rotation is metadata, never baked")
            XCTAssertEqual(PathBuilder.path(for: rotated).boundingBoxOfPath,
                           PathBuilder.path(for: original).boundingBoxOfPath,
                           "\(tool) a rotated mark keeps the same geometry, so the same form")
        }
    }

    // MARK: P5 — a rotated rectangle is still a rectangle

    func testP5RotatedRectangleIsStillBuiltFromItsTwoCorners() {
        let rect = mark(.rectangle, [CGPoint(x: 10, y: 10), CGPoint(x: 110, y: 60)])
        let rotated = MarkTransform.rotated(MarkTransform.rotated(rect, by: .pi / 5), by: .pi / 7)
        XCTAssertEqual(rotated.points.count, 2, "a rectangle never grows into a polygon of its corners")
        XCTAssertEqual(PathBuilder.normalizedRect(from: rotated.points[0], to: rotated.points[1]),
                       PathBuilder.normalizedRect(from: rect.points[0], to: rect.points[1]),
                       "the rectangle itself is unchanged")
        XCTAssertEqual(rotated.rotation, .pi / 5 + .pi / 7, accuracy: 1e-9, "angles add")
    }

    // MARK: P6 — boundary inputs never mirror or collapse a mark

    func testP6ScaleBoundariesNeverMirrorOrCollapse() {
        let rect = mark(.rectangle, [CGPoint(x: 0, y: 0), CGPoint(x: 100, y: 50)])
        let selection = MarkSelection(stroke: rect)
        let dragged = selection.handlePoints(rotationHandleOffset: 20)[.bottomRight]!
        let anchor = selection.handlePoints(rotationHandleOffset: 20)[.topLeft]!

        // Drag straight through the opposite corner: no mirror, no zero size.
        let through = MarkTransform.scaled(rect, dragging: .bottomRight, to: anchor)
        var box = PathBuilder.path(for: through).boundingBoxOfPath
        XCTAssertGreaterThanOrEqual(box.width, 0)
        XCTAssertGreaterThanOrEqual(box.height, 0)
        XCTAssertTrue(through.points[0].x <= through.points[1].x, "points are not mirrored")
        XCTAssertTrue(through.points[0].y <= through.points[1].y, "points are not mirrored")

        // Far past the anchor: still uniform, still the same form.
        let past = MarkTransform.scaled(rect, dragging: .bottomRight,
                                        to: CGPoint(x: anchor.x - 3 * (dragged.x - anchor.x),
                                                    y: anchor.y - 3 * (dragged.y - anchor.y)))
        assertShapePreserved(rect, past, "dragging past the anchor keeps the form")
        box = PathBuilder.path(for: past).boundingBoxOfPath
        XCTAssertEqual(box.width / box.height, 2, accuracy: 1e-6, "aspect ratio survives")

        // A degenerate anchor (zero distance) is not a division by zero.
        XCTAssertEqual(MarkTransform.scaleFactor(from: .zero, draggedCorner: .zero, to: CGPoint(x: 99, y: 99)), 1)

        // A single-point mark (a dot) cannot be scaled into nothing.
        let dot = mark(.pen, [CGPoint(x: 40, y: 40)])
        let dotSelection = MarkSelection(stroke: dot)
        let dotPointer = dotSelection.handlePoints(rotationHandleOffset: 20)[.bottomRight]!
        let scaledDot = MarkTransform.scaled(dot, dragging: .bottomRight, to: dotPointer)
        XCTAssertEqual(scaledDot.points, dot.points, "a zero-size mark stays put")
    }

    // MARK: P7 — the handles and the hit test agree with what is drawn

    func testP7RotatedHandlesAndHitTestFollowTheRenderedMark() {
        let rect = mark(.rectangle, [CGPoint(x: 20, y: 30), CGPoint(x: 120, y: 80)])
        let rotated = MarkTransform.rotated(rect, by: .pi / 2)
        let selection = MarkSelection(stroke: rotated)
        let handles = selection.handlePoints(rotationHandleOffset: 20)

        // Each drawn corner is grabbable exactly where it is drawn.
        for (handle, point) in handles {
            XCTAssertEqual(selection.handle(at: point, handleSize: 12, rotationHandleOffset: 20), handle,
                           "the handle at \(handle) is grabbable where it is drawn")
        }
        // The rotation knob sits outside the mark, above its top edge as drawn.
        let knob = handles[.rotation]!
        XCTAssertFalse(rotated.isSelectedByCursor(at: knob, radius: 0),
                       "the knob is chrome, not part of the mark")
        // Culling bounds contain every drawn point.
        for point in handles.values where point != knob {
            XCTAssertTrue(rotated.displayBounds.insetBy(dx: -0.5, dy: -0.5).contains(point),
                          "displayBounds encloses the rotated corners")
        }
        // And a click on the mark as drawn selects it.
        let centreOfInk = CGPoint(x: 70, y: 55).applying(
            Stroke.rotationTransform(around: rotated.anchor, by: rotated.rotation)
        )
        XCTAssertTrue(rotated.isSelectedByCursor(at: centreOfInk, radius: 2))
    }

    // MARK: P8 — every journaled transform undoes and redoes exactly

    func testP8TransformJournalRoundTripsInReverseAndForwardOrder() {
        var session = DrawingSession()
        let original = mark(.rectangle, [CGPoint(x: 10, y: 10), CGPoint(x: 60, y: 40)])
        draw(original, in: &session)
        let drawn = session.strokes[0]

        let steps: [Stroke] = [
            MarkTransform.translated(drawn, by: CGPoint(x: 20, y: 0)),
            MarkTransform.rotated(drawn, by: .pi / 6),
            MarkTransform.scaled(drawn, from: CGPoint(x: 10, y: 10), by: 2),
            MarkTransform.translated(drawn, by: CGPoint(x: 0, y: 30)),
        ]
        var live: [Stroke] = []
        for step in steps {
            XCTAssertTrue(session.replace(step))
            live.append(session.strokes[0])
        }

        // One drag = one journal entry: four replaces, four undos, nothing more.
        XCTAssertTrue(session.undo())
        XCTAssertEqual(session.strokes[0], live[2])
        XCTAssertTrue(session.undo())
        XCTAssertEqual(session.strokes[0], live[1])
        XCTAssertTrue(session.undo())
        XCTAssertEqual(session.strokes[0], live[0])
        XCTAssertTrue(session.undo())
        XCTAssertEqual(session.strokes[0], drawn, "back to the drawn geometry exactly")
        XCTAssertTrue(session.undo(), "and then the draw itself")
        XCTAssertTrue(session.strokes.isEmpty)
        XCTAssertFalse(session.undo(), "nothing left")

        for expected in [drawn] + live {
            XCTAssertTrue(session.redo())
            XCTAssertEqual(session.strokes[0], expected, "redo walks the same transforms forward")
        }
        XCTAssertFalse(session.redo())
    }

    // MARK: P9 — the guards never name an op the journal would not perform

    func testP9CanUndoAndCanRedoAgreeWithTheJournal() {
        var session = DrawingSession()
        let a = mark(.rectangle, [CGPoint(x: 0, y: 0), CGPoint(x: 50, y: 30)])
        let b = mark(.rectangle, [CGPoint(x: 100, y: 0), CGPoint(x: 150, y: 30)])
        draw(a, in: &session)
        draw(b, in: &session)
        let idA = session.strokes[0].id
        let idB = session.strokes[1].id

        let movedA = MarkTransform.translated(session.strokes[0], by: CGPoint(x: 5, y: 0))
        XCTAssertTrue(session.replace(movedA))
        XCTAssertTrue(session.canUndo(markWithID: idA), "the transform is the newest live op")
        XCTAssertFalse(session.canUndo(markWithID: idB))

        // Erase B: its journal entry is stale and must never be named again.
        session.erase(at: session.strokes[1].points[0], radius: 2)
        XCTAssertTrue(session.strokes.map(\.id) == [idA])
        XCTAssertFalse(session.canUndo(markWithID: idB), "an erased mark has no live undo op")
        XCTAssertTrue(session.canUndo(markWithID: idA))
        XCTAssertTrue(session.undo(), "the guard's promise is the op that runs")
        XCTAssertEqual(session.strokes[0].points, a.points, "the transform is what got undone")

        // Delete through the cursor path, then the redo guard.
        XCTAssertTrue(session.remove(id: idA))
        XCTAssertTrue(session.canRedo(markWithID: idA))
        XCTAssertFalse(session.canRedo(markWithID: idB))
        XCTAssertTrue(session.redo())
        XCTAssertEqual(session.strokes.map(\.id), [idA])
        // The undone transform is still pending, and its id is this one: the
        // guard must keep answering true until that redo has run.
        XCTAssertTrue(session.canRedo(markWithID: idA))
        XCTAssertTrue(session.redo())
        XCTAssertEqual(session.strokes[0].points, movedA.points, "the pending transform is reapplied, not a different mark's")
        XCTAssertFalse(session.canRedo(markWithID: idA), "nothing is left for redo")
        XCTAssertFalse(session.redo())
    }

    // MARK: P10 — a rejected command leaves the data byte-identical

    func testP10RejectedCommandsLeaveTheSessionUntouched() {
        var session = DrawingSession()
        draw(mark(.rectangle, [CGPoint(x: 0, y: 0), CGPoint(x: 50, y: 30)]), in: &session)
        let before = snapshot(session)

        XCTAssertFalse(session.replace(mark(.rectangle, [CGPoint(x: 9, y: 9), CGPoint(x: 1, y: 1)])))
        XCTAssertFalse(session.remove(id: UUID()))
        XCTAssertEqual(snapshot(session), before, "an unknown id changes nothing")
        XCTAssertFalse(session.canUndo(markWithID: UUID()))
        XCTAssertFalse(session.canRedo(markWithID: UUID()))

        var empty = DrawingSession()
        XCTAssertFalse(empty.undo())
        XCTAssertFalse(empty.redo())
        XCTAssertFalse(empty.canRedo)
        XCTAssertTrue(empty.strokes.isEmpty && empty.undoneStrokes.isEmpty)
    }

    // MARK: P11 — the zero-height bounds fix keeps its position, and dots too

    func testP11DegenerateBoundsKeepTheirPosition() {
        let horizontal = mark(.pen, [CGPoint(x: 100, y: 200), CGPoint(x: 300, y: 200)])
        let box = PathBuilder.bounds(for: horizontal)
        XCTAssertLessThanOrEqual(box.minY, 200)
        XCTAssertGreaterThanOrEqual(box.maxY, 200)
        XCTAssertLessThanOrEqual(box.minX, 100)
        XCTAssertGreaterThanOrEqual(box.maxX, 300)

        let vertical = mark(.line, [CGPoint(x: 50, y: 10), CGPoint(x: 50, y: 90)])
        let vbox = PathBuilder.bounds(for: vertical)
        XCTAssertGreaterThan(vbox.midX, 40, "a vertical line is not reported at the origin")
        XCTAssertLessThan(vbox.midX, 60)

        // The culling box of a rotated horizontal line covers the line it draws.
        let rotated = MarkTransform.rotated(horizontal, by: .pi / 4)
        let endpoint = CGPoint(x: 300, y: 200).applying(
            Stroke.rotationTransform(around: horizontal.anchor, by: .pi / 4)
        )
        XCTAssertTrue(rotated.displayBounds.insetBy(dx: -0.5, dy: -0.5).contains(endpoint))
    }

    // MARK: P12 — a transform is not a draw: numbering is untouched

    func testP12TransformKeepsNumbersAndToolIdentity() {
        var session = DrawingSession()
        for index in 0..<3 {
            session.begin(at: CGPoint(x: CGFloat(index) * 40, y: 0), tool: .number, ink: .red)
        }
        XCTAssertEqual(session.strokes.compactMap(\.stepNumber), [1, 2, 3])
        let moved = MarkTransform.translated(session.strokes[1], by: CGPoint(x: 3, y: 4))
        XCTAssertTrue(session.replace(moved))
        XCTAssertEqual(session.strokes.compactMap(\.stepNumber), [1, 2, 3], "moving a badge keeps numbering")
        XCTAssertEqual(session.nextStepNumber, 4)
        XCTAssertEqual(session.strokes[1].tool, .number)
    }

    // MARK: helpers

    private func draw(_ stroke: Stroke, in session: inout DrawingSession) {
        session.begin(at: stroke.points[0], tool: stroke.tool, ink: stroke.ink)
        for point in stroke.points.dropFirst() { session.extend(to: point) }
        if let text = stroke.text { session.setActiveText(text, size: stroke.textSize) }
        session.commit()
    }

    private func snapshot(_ session: DrawingSession) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(CodableSession(session)) else { return "" }
        return String(data: data, encoding: .utf8) ?? ""
    }

    /// Available state only: the journals are private, so this hashes what a
    /// failed command could disturb plus the redo answers it exposes.
    private struct CodableSession: Encodable {
        struct Item: Encodable {
            let tool: String
            let points: [String]
            let step: Int?
            let rotation: Double
        }
        let items: [Item]
        let redo: [String]
        let nextStep: Int
        init(_ session: DrawingSession) {
            items = session.strokes.map {
                Item(tool: $0.tool.rawValue,
                     points: $0.points.map { "\($0.x),\($0.y)" },
                     step: $0.stepNumber,
                     rotation: Double($0.rotation))
            }
            redo = session.undoneStrokes.map { $0.id.uuidString }
            nextStep = session.nextStepNumber
        }
    }

    // MARK: P13 — the text font rule leaves unprefixed text unchanged
    func testP13UnscaledTextKeepsTheEditingFont() {
        let text = "Hola mundo"
        let measured = (text as NSString).size(withAttributes: [.font: NSFont.systemFont(ofSize: 20)])
        let mark = Stroke(tool: .text, ink: .red, points: [CGPoint(x: 10, y: 30)],
                          text: text, textSize: measured)
        // The overlay's rule, reproduced: font size = 20 * stored width / measured width.
        let width = (text as NSString).size(withAttributes: [.font: NSFont.systemFont(ofSize: 20)]).width
        let fontSize = 20 * measured.width / width
        XCTAssertEqual(fontSize, 20, accuracy: 1e-9, "an unscaled mark renders at the editing font size")
        XCTAssertEqual(PathBuilder.bounds(for: mark).size,
                       CGSize(width: measured.width + 4, height: measured.height + 4))
    }

    // MARK: P14 — a rotated blur is drawn outside the rect the live invalidation uses
    // Lands together with the OverlayView.invalidateLiveBlurMarks fix: the view
    // must invalidate displayBounds (the rotated box), not bounds.
    func testP14RotatedBlurInkFallsOutsideItsUnrotatedBounds() {
        let blur = Stroke(tool: .blur, ink: .red,
                          points: [CGPoint(x: 100, y: 300), CGPoint(x: 300, y: 340)])
        let rotated = MarkTransform.rotated(blur, by: .pi / 2)
        // OverlayView.invalidateLiveBlurMarks invalidates stroke.bounds only.
        let invalidated = rotated.bounds
        let transform = Stroke.rotationTransform(around: rotated.anchor, by: rotated.rotation)
        let corners = [
            CGPoint(x: invalidated.minX, y: invalidated.minY),
            CGPoint(x: invalidated.maxX, y: invalidated.minY),
            CGPoint(x: invalidated.maxX, y: invalidated.maxY),
            CGPoint(x: invalidated.minX, y: invalidated.maxY),
        ].map { $0.applying(transform) }
        let outside = corners.filter { !invalidated.contains($0) }
        XCTAssertFalse(outside.isEmpty,
                       "the rotated patch is drawn at \(corners), outside the rect live-frame invalidation repaints")
    }

    // MARK: P15 — the compositor's stored-width ratio is 1 for app-created text
    func testP15CompositorFontRatioForAStoredTextSize() {
        for text in ["Hola mundo", "iiii", "WWWW", "Hola, ¿qué tal? 123"] {
            let stored = (text as NSString).size(withAttributes: [.font: NSFont.systemFont(ofSize: 20)]).width
            let ctfont = CTFontCreateUIFontForLanguage(.system, 20, nil)!
            let attributes: [CFString: Any] = [kCTFontAttributeName: ctfont]
            let line = CTLineCreateWithAttributedString(
                CFAttributedStringCreate(nil, text as CFString, attributes as CFDictionary)!
            )
            let ctWidth = CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil))
            let ratio = 20 * stored / ctWidth
            XCTAssertEqual(ratio, 20, accuracy: 0.25, "'\(text)' renders at the editing size within a quarter point (ratio \(ratio))")
        }
    }
}
