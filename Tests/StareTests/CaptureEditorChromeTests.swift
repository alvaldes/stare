import AppKit
import XCTest

@testable import Stare
import StareCore

/// T1/S1: the editor's chrome follows the user's own bar configuration, not
/// a fixed horizontal strip pinned to the top. For each of the four stored
/// orientation + docked-edge pairs, the real chrome lays out on the edge the
/// configuration names and the canvas takes the rest. The frames below are
/// the measured pins nothing had before.
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

    /// A real editor content seeded with the given snapshot, laid out in a
    /// real window the way the app opens one, with the measured layout
    /// printed for the record.
    private func layout(toolbar: EditorToolbarSnapshot) throws -> CaptureEditorContent {
        let content = CaptureEditorContent(
            image: solid(300, 200),
            capture: .standard,
            redactionStyle: .blur,
            toolbar: toolbar
        )
        let window = NSWindow(
            contentRect: CGRect(origin: .zero, size: content.preferredSize),
            styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        window.contentView = content
        window.confineToPrimaryScreen()
        content.layoutSubtreeIfNeeded()

        let chrome = try XCTUnwrap(content.chrome, "the content builds the chrome")
        let label = "\(toolbar.orientation.rawValue)-\(toolbar.border.rawValue)"
        print("CHROME \(label): bounds=\(content.bounds) chrome=\(chrome.frame) canvas=\(content.canvas.frame) preferred=\(content.preferredSize) fitting=\(chrome.fittingSize)")
        return content
    }

    private func assertChromeEdge(
        _ content: CaptureEditorContent, border: ToolbarBorder,
        file: StaticString = #filePath, line: UInt = #line
    ) throws {
        let chrome = try XCTUnwrap(content.chrome, file: file, line: line)
        let canvas = content.canvas
        let bounds = content.bounds
        let fit = chrome.fittingSize
        switch border {
        case .top:
            XCTAssertEqual(chrome.frame.minY, canvas.frame.maxY, "the bar rides the canvas, no gap, no overlap", file: file, line: line)
            XCTAssertEqual(chrome.frame.height, fit.height, "the row keeps its fitting height", file: file, line: line)
            XCTAssertEqual(chrome.frame.width, bounds.width, "the row spans the content's width", file: file, line: line)
            XCTAssertEqual(chrome.frame.maxY, bounds.height, "docked at the top edge", file: file, line: line)
        case .bottom:
            XCTAssertEqual(chrome.frame.maxY, canvas.frame.minY, "the bar rides the canvas, no gap, no overlap", file: file, line: line)
            XCTAssertEqual(chrome.frame.height, fit.height, "the row keeps its fitting height", file: file, line: line)
            XCTAssertEqual(chrome.frame.width, bounds.width, "the row spans the content's width", file: file, line: line)
            XCTAssertEqual(chrome.frame.minY, bounds.minY, "docked at the bottom edge", file: file, line: line)
        case .left:
            XCTAssertEqual(chrome.frame.maxX, canvas.frame.minX, "the bar rides the canvas, no gap, no overlap", file: file, line: line)
            XCTAssertEqual(chrome.frame.width, fit.width, "the column keeps its fitting width", file: file, line: line)
            XCTAssertEqual(chrome.frame.height, bounds.height, "the column spans the content's height", file: file, line: line)
            XCTAssertEqual(chrome.frame.minX, bounds.minX, "docked at the left edge", file: file, line: line)
        case .right:
            XCTAssertEqual(chrome.frame.minX, canvas.frame.maxX, "the bar rides the canvas, no gap, no overlap", file: file, line: line)
            XCTAssertEqual(chrome.frame.width, fit.width, "the column keeps its fitting width", file: file, line: line)
            XCTAssertEqual(chrome.frame.height, bounds.height, "the column spans the content's height", file: file, line: line)
            XCTAssertEqual(chrome.frame.maxX, bounds.maxX, "docked at the right edge", file: file, line: line)
        }
        // The bar never covers the canvas, and together they account for the
        // whole content view with no empty band between them.
        let gap = border == .top || border == .bottom
            ? abs(canvas.frame.height + chrome.frame.height - bounds.height)
            : abs(canvas.frame.width + chrome.frame.width - bounds.width)
        XCTAssertLessThanOrEqual(gap, 1, "chrome + canvas account for the full content height/width", file: file, line: line)
        // Touching frames share an edge; anything deeper is a real overlap.
        XCTAssertTrue(chrome.frame.intersection(canvas.frame).isEmpty, "the bar never covers the canvas", file: file, line: line)
    }

    // MARK: - The four configurations (S1)

    func testHorizontalRowDocksOnTopWhenTheUserStoredTop() throws {
        // Also today's shipped pair, laid out honestly.
        let content = try layout(toolbar: EditorToolbarSnapshot(orientation: .horizontal, border: .top))
        try assertChromeEdge(content, border: .top)
    }

    func testHorizontalRowDocksOnBottomWhenTheUserStoredBottom() throws {
        let content = try layout(toolbar: EditorToolbarSnapshot(orientation: .horizontal, border: .bottom))
        try assertChromeEdge(content, border: .bottom)
    }

    func testVerticalColumnDocksOnTheLeftWhenTheUserStoredLeft() throws {
        let content = try layout(toolbar: EditorToolbarSnapshot(orientation: .vertical, border: .left))
        try assertChromeEdge(content, border: .left)
        // Honest arithmetic: the column's width joins the canvas width.
        let chrome = try XCTUnwrap(content.chrome)
        XCTAssertEqual(
            content.preferredSize.width, content.canvas.frame.width + chrome.fittingSize.width, accuracy: 2)
    }

    func testVerticalColumnDocksOnTheRightWhenTheUserStoredRight() throws {
        let content = try layout(toolbar: EditorToolbarSnapshot(orientation: .vertical, border: .right))
        try assertChromeEdge(content, border: .right)
    }

    // MARK: - The snapshot is read-only

    /// The editor seeds a copy of the user's configuration into its own
    /// detached state — no preferences model is involved, so nothing the
    /// editor picks can persist into the user's saved bar.
    func testTheSnapshotSeedsTheStateWithoutAPreferencesModel() {
        let content = CaptureEditorContent(
            image: solid(300, 200), capture: .standard, redactionStyle: .blur,
            toolbar: EditorToolbarSnapshot(orientation: .vertical, border: .right))
        XCTAssertEqual(content.state.toolbarOrientation, .vertical)
        XCTAssertEqual(content.state.toolbarBorder, .right)
        // Detached state still runs its other values on the shipped
        // defaults, exactly as before.
        XCTAssertEqual(content.state.redactionStyle, .blur)
    }

    /// A stored pair the orientation cannot honour coerces the same way the
    /// outside bar's placement rule does: the chrome lands on a valid edge,
    /// never a mixed-up one.
    func testAMismatchedStoredPairCoercesLikeTheOutsideBar() {
        let content = CaptureEditorContent(
            image: solid(300, 200), capture: .standard, redactionStyle: .blur,
            toolbar: EditorToolbarSnapshot(orientation: .vertical, border: .top))
        XCTAssertEqual(
            content.state.toolbarBorder.docked(for: content.state.toolbarOrientation), .left,
            "the same coercion ToolbarPanel applies at placement")
    }
}
