import AppKit
import SwiftUI
import XCTest

@testable import Stare
@testable import StareCore

/// S2/S3 with S4's revision: the spotlight keeps its one button and picks its
/// shape from the button itself — a context menu offering exactly the two
/// shapes with the armed one checked, right-click over the non-key bar being
/// a control a user can actually find (⌥-click, the withdrawn gesture, is
/// gone). Pinned over the real bar with the real menu route down to the
/// button's own view, on both surfaces the bar serves (the drawing bar and
/// the capture editor's chrome), and the armed shape rides `EditorState` into
/// every minting site the way `arrowHeadStyle` does.
@MainActor
final class CaptureSpotlightShapeTests: XCTestCase {
    // MARK: - Fixtures

    /// SwiftUI buttons cannot be pressed from a test; the spotlight's button
    /// is an AppKit-backed press surface precisely so a real `NSEvent` with
    /// its modifiers reaches the view route both the bar and the chrome share.
    private func spotlightButton(in root: NSView) -> SpotlightToolButtonView? {
        var stack: [NSView] = [root]
        while let view = stack.popLast() {
            if view is SpotlightToolButtonView { return view as? SpotlightToolButtonView }
            stack.append(contentsOf: view.subviews)
        }
        return nil
    }

    private func click(
        _ view: NSView,
        file: StaticString = #filePath, line: UInt = #line
    ) throws {
        let event = try XCTUnwrap(NSEvent.mouseEvent(
            with: .leftMouseDown, location: CGPoint(x: view.bounds.midX, y: 5),
            modifierFlags: [], timestamp: 0,
            windowNumber: view.window?.windowNumber ?? 0, context: nil,
            eventNumber: 0, clickCount: 1, pressure: 1),
            "the synthetic press could not be built", file: file, line: line)
        view.mouseDown(with: event)
    }

    /// A real bar in a real borderless window, the drawing toolbar's own. The
    /// shipped bar hides the spotlight behind the `⁞`, so the fixture keeps a
    /// full-bar layout — the control is the same button either way.
    private func hostedDrawingBar() throws -> (NSWindow, EditorState) {
        let state = EditorState()
        state.tool = .pen
        state.toolbarTools = ToolbarToolLayout(
            items: ToolbarToolLayout.itemsWithFamilySeparators(Tool.allCases), pool: [])
        let hosting = NSHostingView(
            rootView: ToolbarView(state: state, onUndo: {}, onRedo: {}, onClear: {}, onDone: {}))
        hosting.frame = CGRect(origin: .zero, size: hosting.fittingSize)
        hosting.layoutSubtreeIfNeeded()
        let window = NSWindow(
            contentRect: hosting.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.confineToPrimaryScreen()
        window.contentView = hosting
        window.orderFrontRegardless()
        RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        hosting.layoutSubtreeIfNeeded()
        return (window, state)
    }

    /// The subview classes under a root view, for test diagnostics.
    private func dumpTree(_ root: NSView) -> [String] {
        var stack: [NSView] = [root], names: [String] = []
        while let view = stack.popLast() {
            names.append(String(describing: Swift.type(of: view)))
            stack.append(contentsOf: view.subviews)
        }
        return names
    }

    // MARK: - The context menu offers exactly the two shapes (S4)

    /// The menu is read off the real button — the same route a right-click
    /// travels — so the checkmark and the items are the user's, not a copy.
    private func shapeMenu(item shape: SpotlightShape, on button: NSView) throws -> NSMenuItem {
        let press = try XCTUnwrap(NSEvent.mouseEvent(
            with: .leftMouseDown, location: CGPoint(x: button.bounds.midX, y: 5),
            modifierFlags: [], timestamp: 0, windowNumber: button.window?.windowNumber ?? 0,
            context: nil, eventNumber: 0, clickCount: 1, pressure: 1))
        let menu = try XCTUnwrap(
            button.menu(for: press), "the spotlight's button must carry a context menu")
        return try XCTUnwrap(
            menu.items.first { ($0.representedObject as? SpotlightShape) == shape })
    }

    func testTheSpotlightButtonSContextMenuOffersExactlyTheTwoShapesWithTheArmedOneChecked() throws {
        let (window, state) = try hostedDrawingBar()
        defer { window.orderOut(nil) }
        let button = try XCTUnwrap(
            spotlightButton(in: window.contentView!),
            "the drawing bar must carry the spotlight's own button; tree: \(dumpTree(window.contentView!))")

        // The shipped armed shape is the ellipse — today's spotlight.
        XCTAssertEqual(state.spotlightShape, .ellipse)
        let press = try XCTUnwrap(NSEvent.mouseEvent(
            with: .leftMouseDown, location: CGPoint(x: button.bounds.midX, y: 5),
            modifierFlags: [], timestamp: 0, windowNumber: button.window?.windowNumber ?? 0,
            context: nil, eventNumber: 0, clickCount: 1, pressure: 1))
        let menu = try XCTUnwrap(button.menu(for: press))
        XCTAssertEqual(
            menu.items.map(\.title),
            [SpotlightShape.ellipse.displayName, SpotlightShape.roundedRectangle.displayName],
            "exactly the two offered shapes, in menu order")
        XCTAssertEqual(
            menu.items.first { $0.state == .on }?.representedObject as? SpotlightShape,
            .ellipse, "the armed shape is the checked one")
        XCTAssertNil(
            menu.items.first { ($0.representedObject as? SpotlightShape) == .rectangle },
            "the plain rectangle is withdrawn from the offer")
    }

    /// Picking a shape arms it on the state — and the state's shape is what
    /// the next mark carries (the minting site route the overlay test pins).
    func testPickingAShapeFromTheMenuArmsTheNextMarkWithIt() throws {
        let (window, state) = try hostedDrawingBar()
        defer { window.orderOut(nil) }
        let button = try XCTUnwrap(spotlightButton(in: window.contentView!))

        let pick = try shapeMenu(item: .roundedRectangle, on: button)
        pick.target!.perform(try XCTUnwrap(pick.action), with: pick)
        XCTAssertEqual(
            state.spotlightShape, .roundedRectangle, "the pick arms the shape")
        try click(button)
        XCTAssertEqual(
            state.tool, .spotlight, "the plain click arms the tool with the armed shape")
        let mark = try XCTUnwrap(
            self.mintedSpotlight(state, size: CGSize(width: 500, height: 400)),
            "the drag commits a spotlight mark")
        XCTAssertEqual(
            mark.spotlightShape, .roundedRectangle, "and the next mark carries it")
    }

    /// A plain click on the button stays exactly the tool pick every tool's
    /// button makes — the cycle must not swallow the tool's own press.
    func testAPlainClickArmsTheSpotlightAsEveryToolButtonDoes() throws {
        let (window, state) = try hostedDrawingBar()
        defer { window.orderOut(nil) }
        let button = try XCTUnwrap(spotlightButton(in: window.contentView!))

        try click(button)
        XCTAssertEqual(state.tool, .spotlight, "the plain click arms the tool")
        XCTAssertEqual(state.spotlightShape, .ellipse, "and names the armed shape nothing")
    }

    // MARK: - The same control on the capture editor's chrome

    func testTheEditorChromeSMenuMatchesTheDrawingBarS() throws {
        let content = CaptureEditorContent(
            image: try XCTUnwrap(Self.solidImage()),
            capture: .standard,
            redactionStyle: .blur)
        let window = NSWindow(
            contentRect: CGRect(origin: .zero, size: content.preferredSize),
            styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        window.confineToPrimaryScreen()
        window.contentView = content
        window.orderFrontRegardless()
        content.layoutSubtreeIfNeeded()
        defer { window.orderOut(nil) }

        let button = try XCTUnwrap(
            spotlightButton(in: content),
            "the editor's chrome carries the same spotlight button name")
        XCTAssertEqual(content.state.spotlightShape, .ellipse)
        let press = try XCTUnwrap(NSEvent.mouseEvent(
            with: .leftMouseDown, location: CGPoint(x: button.bounds.midX, y: 5),
            modifierFlags: [], timestamp: 0, windowNumber: button.window?.windowNumber ?? 0,
            context: nil, eventNumber: 0, clickCount: 1, pressure: 1))
        let menu = try XCTUnwrap(button.menu(for: press))
        XCTAssertEqual(
            menu.items.map(\.title),
            [SpotlightShape.ellipse.displayName, SpotlightShape.roundedRectangle.displayName])
        XCTAssertEqual(
            menu.items.first { $0.state == .on }?.representedObject as? SpotlightShape, .ellipse)
        let pick = try shapeMenu(item: .roundedRectangle, on: button)
        pick.target!.perform(try XCTUnwrap(pick.action), with: pick)
        XCTAssertEqual(content.state.spotlightShape, .roundedRectangle)
    }

    // MARK: - Every minting site stamps the armed shape

    /// The drawing overlay mints with the state's shape the way it mints with
    /// the state's redaction style (T6b's route) — a real drag through
    /// `OverlayView` commits a mark carrying the armed shape.
    func testTheDrawingOverlayMintsTheArmedShape() throws {
        for shape in SpotlightShape.menuChoices {
            let state = EditorState()
            state.tool = .spotlight
            if shape != .ellipse { state.spotlightShape = shape }
            let mark = try XCTUnwrap(
                self.mintedSpotlight(state, size: CGSize(width: 500, height: 400)),
                "the drag commits a spotlight mark")
            XCTAssertEqual(
                mark.spotlightShape, shape,
                "the minting site stamps the armed shape: \(shape)")
        }
    }

    /// Draws one spotlight drag through the real `OverlayView` and answers
    /// the committed mark.
    private func mintedSpotlight(_ state: EditorState, size: CGSize) throws -> Stroke? {
        let view = OverlayView(
            frame: CGRect(origin: .zero, size: size),
            state: state, onEscape: {})
        view.onAreaSelectionFrame = {}
        let window = NSWindow(
            contentRect: view.frame,
            styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = view
        window.confineToPrimaryScreen()

        func sample(_ type: NSEvent.EventType, at point: CGPoint) throws -> NSEvent {
            try XCTUnwrap(NSEvent.mouseEvent(
                with: type, location: CGPoint(x: point.x, y: size.height - point.y),
                modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber,
                context: nil, eventNumber: 0, clickCount: 1, pressure: 1))
        }
        view.mouseDown(with: try sample(.leftMouseDown, at: CGPoint(x: 100, y: 100)))
        view.mouseDragged(with: try sample(.leftMouseDragged, at: CGPoint(x: 200, y: 160)))
        view.mouseUp(with: try sample(.leftMouseUp, at: CGPoint(x: 200, y: 160)))
        return view.session.strokes.first(where: { $0.tool == .spotlight })
    }

    private static func solidImage() -> CGImage? {
        let context = CGContext(
            data: nil, width: 300, height: 200, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(CGColor(gray: 0.5, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 300, height: 200))
        return context.makeImage()
    }
}
