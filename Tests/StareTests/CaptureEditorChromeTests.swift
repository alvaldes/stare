import AppKit
import XCTest

@testable import Stare
import StareCore

/// T4/S4: the editor's chrome is ALWAYS a horizontal row at the top of the
/// editor, whatever the user's own bar is configured as — the orientation
/// snapshot is withdrawn, so the editor consults nothing stored and builds
/// its own detached state, whose mirrors stay on the shipped horizontal/top
/// defaults the one layout needs. The palette carries the select tool, and
/// the close button and the gripper — the outside bar's window chrome — are
/// not editor items.
@MainActor
final class CaptureEditorChromeTests: XCTestCase {
    private func solid(_ width: Int, _ height: Int) -> CGImage {
        let context = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8,
            bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        context.setFillColor(CGColor(srgbRed: 0.2, green: 0.4, blue: 0.8, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage()!
    }

    /// An in-memory `PreferenceStore` double, so the stored-configuration
    /// probe never touches the user's real preferences — the same isolation
    /// the preference tests use.
    private final class InMemoryPreferenceStore: PreferenceStore {
        private var storage: [String: Any] = [:]
        func object(forKey key: String) -> Any? { storage[key] }
        func set(_ value: Any?, forKey key: String) { storage[key] = value }
    }

    /// A real editor content built the way the app builds it — with nothing
    /// handed in about the user's bar — laid out in a real window, with the
    /// measured layout printed for the record.
    private func layout() throws -> CaptureEditorContent {
        let content = CaptureEditorContent(
            image: solid(300, 200),
            capture: .standard,
            redactionStyle: .blur
        )
        let window = NSWindow(
            contentRect: CGRect(origin: .zero, size: content.preferredSize),
            styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        window.contentView = content
        window.confineToPrimaryScreen()
        content.layoutSubtreeIfNeeded()

        let chrome = try XCTUnwrap(content.chrome, "the content builds the chrome")
        print("CHROME: bounds=\(content.bounds) chrome=\(chrome.frame) canvas=\(content.canvas.frame) preferred=\(content.preferredSize) fitting=\(chrome.fittingSize)")
        return content
    }

    /// The chrome is one horizontal row docked at the top edge: it spans the
    /// content's width at its own fitting height, the canvas takes the rest,
    /// and the two account for the whole content with no gap or overlap.
    private func assertChromeEdge(
        _ content: CaptureEditorContent,
        file: StaticString = #filePath, line: UInt = #line
    ) throws {
        let chrome = try XCTUnwrap(content.chrome, file: file, line: line)
        let canvas = content.canvas
        let bounds = content.bounds
        let fit = chrome.fittingSize
        XCTAssertEqual(chrome.frame.minY, canvas.frame.maxY, "the bar rides the canvas, no gap, no overlap", file: file, line: line)
        XCTAssertEqual(chrome.frame.height, fit.height, "the row keeps its fitting height", file: file, line: line)
        XCTAssertEqual(chrome.frame.width, bounds.width, "the row spans the content's width", file: file, line: line)
        XCTAssertEqual(chrome.frame.maxY, bounds.height, "docked at the top edge", file: file, line: line)
        let gap = abs(canvas.frame.height + chrome.frame.height - bounds.height)
        XCTAssertLessThanOrEqual(gap, 1, "chrome + canvas account for the full content height", file: file, line: line)
        XCTAssertTrue(chrome.frame.intersection(canvas.frame).isEmpty, "the bar never covers the canvas", file: file, line: line)
    }

    // MARK: - Always horizontal, always on top (S4)

    func testTheChromeIsAHorizontalRowAtTheTop() throws {
        let content = try layout()
        try assertChromeEdge(content)
        // The detached state carries the shipped horizontal/top defaults the
        // one layout needs — there is no stored configuration in it at all.
        XCTAssertEqual(content.state.toolbarOrientation, .horizontal)
        XCTAssertEqual(content.state.toolbarBorder, .top)
        // Honest arithmetic for the one case that exists: the row's height
        // joins the canvas height, the width answers to the wider of the
        // canvas and the bar.
        XCTAssertEqual(
            content.preferredSize.height,
            content.canvas.frame.height + content.chrome.fittingSize.height, accuracy: 2)
        XCTAssertEqual(
            content.preferredSize.width,
            max(content.canvas.frame.width, content.chrome.fittingSize.width), accuracy: 2)
    }

    /// The orientation snapshot is withdrawn (S4): the editor reads nothing
    /// stored. A stored configuration that says vertical/left is real — the
    /// outside bar's own state mirrors it — and the editor still lays out
    /// the same horizontal row at the top.
    func testTheChromeIgnoresAStoredVerticalConfiguration() throws {
        let model = PreferencesModel(store: InMemoryPreferenceStore())
        model.toolbarOrientation = .vertical
        model.toolbarBorder = .left
        let outside = EditorState(preferences: model)
        XCTAssertEqual(outside.toolbarOrientation, .vertical, "the stored configuration is real")
        XCTAssertEqual(outside.toolbarBorder.docked(for: outside.toolbarOrientation), .left)

        let content = try layout()
        XCTAssertEqual(content.state.toolbarOrientation, .horizontal, "the editor consults nothing stored")
        XCTAssertEqual(content.state.toolbarBorder, .top)
        try assertChromeEdge(content)
    }

    // MARK: - The editor's own items (S4)

    func testTheEditorPaletteCarriesTheSelectTool() throws {
        // The editor's item list never had the select tool ('v') — S4 says it
        // belongs there, and the item list is the rule the palette renders.
        XCTAssertTrue(Tool.captureEditorTools.contains(.select))
        XCTAssertTrue(
            Tool.captureEditorGroups.flatMap(\.self).contains(.select),
            "the select tool leads its own family group in the outside bar's palette; the editor's list keeps it")
        // Through the real chrome: the bar the editor renders offers it.
        let content = CaptureEditorContent(
            image: solid(300, 200), capture: .standard, redactionStyle: .blur)
        let groups = try XCTUnwrap(
            content.chrome.rootView.chromeToolbar.fixedToolGroups,
            "the editor's chrome passes its fixed grouped palette")
        XCTAssertTrue(groups.flatMap(\.self).contains(.select))
    }

    // MARK: - Not the outside bar's window chrome (S4)

    func testTheEditorChromeHasNoCloseButtonAndNoGripper() throws {
        let content = try layout()
        let toolbar = content.chrome.rootView.chromeToolbar
        XCTAssertFalse(toolbar.showsWindowChrome, "the editor's chrome builds without the window chrome tail")
        XCTAssertFalse(toolbar.drawnTrailingItems.contains(.close), "the close 'X' is not an editor item (S4)")
        XCTAssertFalse(toolbar.drawnTrailingItems.contains(.gripper), "the gripper is not an editor item (S4)")
        // The outside bar's own tail is untouched — the pin
        // `ToolbarGripperTests` keeps, restated here as the boundary: a
        // default ToolbarView draws every trailing item, close and gripper
        // included, in the same order.
        XCTAssertEqual(ToolbarView.trailingItems.suffix(2), [.close, .gripper])
        XCTAssertEqual(
            ToolbarView(state: EditorState(), onUndo: {}, onRedo: {}, onClear: {}, onDone: {})
                .drawnTrailingItems,
            ToolbarView.trailingItems)
    }

    // MARK: - The spotlight's cell takes its neighbours' size (round four, S4)

    /// The spotlight's AppKit-backed cell (the shape menu's carrier) used to
    /// grow into whatever its row offered it: no fixed frame, so the editor's
    /// row stretched it while its plain neighbours kept their 28×26 — the
    /// owner's measurement "sigue igual", the cell ~400 pt wide, a third of
    /// the bar. The fixed frame is the fix; the right-click shape menu stays
    /// on the very same AppKit view, so this frame pin and the menu's tests
    /// together cover the whole correction.
    func testTheSpotlightsPaletteCellTakesTheToolCellSizeBack() throws {
        let content = try layout()
        let chrome = try XCTUnwrap(content.chrome)
        // One layout tick, the way the toolbar's own hosted-content tests
        // schedule SwiftUI's first pass.
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        func probe() -> NSView? {
            var stack: [NSView] = [chrome]
            var cell: NSView?
            while let view = stack.popLast() {
                if view is SpotlightToolButtonView { cell = view }
                stack.append(contentsOf: view.subviews)
            }
            return cell
        }
        XCTAssertNotNil(probe(), "the editor's palette hosts the spotlight's AppKit cell")
        // The editor's window is RESIZABLE: at a wide window the row has spare
        // width to hand out — adding width is what stretched the unframed
        // cell (the owner's "sigue igual" screenshot sat in a wide editor).
        for width in [706.0, 1000.0] {
            content.window?.setContentSize(NSSize(width: width, height: 320))
            content.layoutSubtreeIfNeeded()
            RunLoop.main.run(until: Date().addingTimeInterval(0.02))
        }
        let cell = try XCTUnwrap(probe())
        XCTAssertEqual(
            cell.frame.size, CGSize(width: 28, height: 26),
            "the spotlight cell must take its neighbours' 28×26 at every width, not the row's spare (measured \(cell.frame.size))")
    }

    // MARK: - The numbered step's digit, in the editor's own canvas path
    // (editor-save-in-place S1: the owner's "no se ve el numero solo la bola
    // de color")

    /// The number tool's glyph is ONE decision in `MarkRenderer`, and the
    /// editor's canvas is one of its callers: a step placed in the editor
    /// shows the digit the saved capture shows. Rendered through the
    /// canvas's own `draw(_:)` — the exact path a live edit paints — into a
    /// bitmap, and sampled: the digit's black pixels sit inside the ball.
    func testAStepMarkShowsItsNumberInTheEditorsOwnCanvasPath() throws {
        let image = try XCTUnwrap(Self.solidImage(width: 100, height: 100))
        let canvas = CaptureEditorCanvas(image: image)
        canvas.frame = CGRect(x: 0, y: 0, width: 300, height: 200)
        // A 100×100 capture in a 300×200 window fits at (50, 0, 200, 200):
        // pixels-per-point 2, so the ball sits at view (150, 100).
        canvas.seedMarks([
            Stroke(tool: .number, ink: .yellow, points: [CGPoint(x: 50, y: 50)], stepNumber: 1),
        ])
        let rep = try XCTUnwrap(NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: 300,
            pixelsHigh: 200,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ))
        NSGraphicsContext.saveGraphicsState()
        let context = try XCTUnwrap(NSGraphicsContext(bitmapImageRep: rep))
        NSGraphicsContext.current = context
        // AppKit pre-flips the context for a flipped view before draw(_:) is
        // called; calling draw directly has to supply that flip itself.
        context.cgContext.translateBy(x: 0, y: 200)
        context.cgContext.scaleBy(x: 1, y: -1)
        canvas.draw(canvas.bounds)
        NSGraphicsContext.restoreGraphicsState()

        // Scan only the PICTURE's own rect (the display the canvas fits the
        // capture into), never the letterboxed around it: inside it the only
        // possible sources are the white base and the one number mark, so a
        // near-black pixel can only ever be the digit's ink (the ball-contrast
        // rule draws it full-opacity black on a yellow ball; the ball itself
        // is yellow, its hairline at most 18% darker).
        let display = EditorCropSpace.fitted(
            coverage: CGRect(x: 0, y: 0, width: 100, height: 100),
            viewport: .identity,
            inCanvas: canvas.bounds).display
        var ballPixels = 0
        var digitPixels = 0
        for x in Int(display.minX.rounded())...Int(display.maxX.rounded()) - 1 {
            for y in Int(display.minY.rounded())...Int(display.maxY.rounded()) - 1 {
                let colour = try XCTUnwrap(rep.colorAt(x: x, y: 200 - 1 - y)?.usingColorSpace(.deviceRGB))
                var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
                colour.getRed(&r, green: &g, blue: &b, alpha: &a)
                if (r - 1).magnitude < 0.05 && (g - 0.8).magnitude < 0.06 && b < 0.06 { ballPixels += 1 }
                if r < 0.1 && g < 0.1 && b < 0.1 { digitPixels += 1 }
            }
        }
        XCTAssertGreaterThan(ballPixels, 0, "the ball rendered where the canvas placed it")
        XCTAssertGreaterThan(
            digitPixels, 0,
            "the editor's own canvas draws the step's number, not just the colour ball")
    }

    // MARK: - The Save control keeps its compact pinned cell (S1: the owner's
    // "el btn save se ve muy grande (ocupa mucho ancho) igual que como se
    // veia el spotlight antes")

    /// The labelled split keeps the word (the legibility the L5 shape
    /// landed) but it is measured: a pinned compact cell the neighbours'
    /// fixed-26/28 discipline gives it, exactly like the spotlight's bounded
    /// cell above — a resizable row can never hand the control spare width
    /// again.
    func testTheSaveSplitControlKeepsItsPinnedCompactCellWhereverTheRowStretches() throws {
        let content = try layout()
        let chrome = try XCTUnwrap(content.chrome)
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        func probe() -> NSView? {
            var stack: [NSView] = [chrome]
            var cell: NSView?
            while let view = stack.popLast() {
                if view is ToolbarSplitActionView { cell = view }
                stack.append(contentsOf: view.subviews)
            }
            return cell
        }
        XCTAssertNotNil(probe(), "the editor's chrome hosts the labelled split control")
        // The owner's measurement, pinned: at every row width the control
        // is its pinned cell — not a 400-pt spread like the un-framed
        // spotlight cell was, and not even word-and-chevron slack next to
        // its 26/28 neighbours.
        for width in [content.preferredSize.width, 706.0, 1000.0] {
            content.window?.setContentSize(NSSize(width: width, height: 320))
            content.layoutSubtreeIfNeeded()
            RunLoop.main.run(until: Date().addingTimeInterval(0.02))
            let cell = try XCTUnwrap(probe())
            XCTAssertEqual(
                cell.frame.size, ToolbarSplitActionView.cellSize,
                "the Save control must keep its pinned compact cell at every row width (measured \(cell.frame.size))")
        }
    }

    private static func solidImage(width: Int, height: Int) -> CGImage? {
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(
                data: nil,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: 0,
                space: space,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              ) else { return nil }
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage()
    }
}
