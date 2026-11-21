import AppKit
import SwiftUI
import StareCore

/// `--selftest` gathers the facts that a headless unit test cannot: real screen
/// and window geometry, whether a panel is on screen and whether the render path
/// produces pixels. It writes a report and a PNG and exits.
enum SelfTest {
    static let reportPath = "/tmp/stare-selftest.txt"
    static let imagePath = "/tmp/stare-selftest.png"
    static let blurImagePath = "/tmp/stare-selftest-blur.png"

    /// A mouse down, drag and up inside the panel, so the view commits a mark
    /// without the window server being involved.
    private static func sendDrag(to panel: NSWindow, from start: CGPoint, to end: CGPoint) {
        func send(_ type: NSEvent.EventType, _ point: CGPoint) {
            guard let event = NSEvent.mouseEvent(
                with: type,
                location: point,
                modifierFlags: [],
                timestamp: ProcessInfo.processInfo.systemUptime,
                windowNumber: panel.windowNumber,
                context: nil,
                eventNumber: 1,
                clickCount: 1,
                pressure: 1
            ) else { return }
            panel.sendEvent(event)
        }
        send(.leftMouseDown, start)
        send(.leftMouseDragged, CGPoint(x: (start.x + end.x) / 2, y: (start.y + end.y) / 2))
        send(.leftMouseDragged, end)
        send(.leftMouseUp, end)
    }

    static func run() -> Int32 {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)

        var report: [String] = []
        report.append("Stare self test")
        report.append("screens=\(NSScreen.screens.count)")
        report.append("mouse=\(NSEvent.mouseLocation)")

        for (index, screen) in NSScreen.screens.enumerated() {
            report.append(
                """
                screen[\(index)] id=\(displayID(of: screen) ?? 0) \
                frame=\(screen.frame) visible=\(screen.visibleFrame) \
                scale=\(screen.backingScaleFactor)
                """
            )
        }

        let state = EditorState()
        guard let screen = NSScreen.screens.first else {
            report.append("FAIL: no screens")
            return finish(report, code: 1)
        }

        guard let canvas = DisplayCanvas(screen: screen, state: state, onEscape: {}) else {
            report.append("FAIL: canvas could not be created")
            return finish(report, code: 1)
        }

        let panel = canvas.panel
        NSApp.activate()
        panel.orderFrontRegardless()
        RunLoop.current.run(until: Date().addingTimeInterval(0.5))

        report.append(
            """
            panel frame=\(panel.frame) isVisible=\(panel.isVisible) \
            isKey=\(panel.isKeyWindow) isOnActiveSpace=\(panel.isOnActiveSpace) \
            level=\(panel.level.rawValue) styleMask=\(panel.styleMask.rawValue) \
            ignoresMouse=\(panel.ignoresMouseEvents) \
            alpha=\(panel.alphaValue) occlusion=\(panel.occlusionState.rawValue) \
            appActive=\(NSApp.isActive) \
            collection=\(panel.collectionBehavior.rawValue) \
            contentIsOverlayView=\(panel.contentView is OverlayView) \
            contentFrame=\(String(describing: panel.contentView?.frame))
            """
        )
        report.append("canvas display=\(canvas.displayID) windowNumber=\(panel.windowNumber)")
        report.append(contentsOf: windowServerReport(for: panel))

        // Does the view respond to a mouse event at all, bypassing the window
        // server? If this leaves a mark, the view and its model are fine and the
        // problem is window-server routing.
        let syntheticPoint = CGPoint(x: 200, y: 200)
        if let event = NSEvent.mouseEvent(
            with: .leftMouseDown,
            location: syntheticPoint,
            modifierFlags: [],
            timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: panel.windowNumber,
            context: nil,
            eventNumber: 1,
            clickCount: 1,
            pressure: 1
        ) {
            panel.sendEvent(event)
        }
        report.append("syntheticClickStrokes=\(canvas.view.session.visibleStrokes.count)")

        // A full drag, so there is a committed mark for the history to work on.
        sendDrag(to: panel, from: CGPoint(x: 400, y: 300), to: CGPoint(x: 520, y: 380))
        report.append("syntheticDragStrokes=\(canvas.view.session.strokes.count)")

        // Redo through the view, which is the path the global history uses: the
        // mark removed by id has to come back by id, and nothing else.
        if let mark = canvas.view.session.strokes.last {
            let removed = canvas.view.removeMark(id: mark.id)
            let restored = canvas.view.redoMark(id: mark.id)
            report.append(
                "redo removed=\(removed) restored=\(restored) "
                    + "marks=\(canvas.view.session.strokes.count) "
                    + "sameMark=\(canvas.view.session.strokes.last?.id == mark.id)"
            )
        } else {
            report.append("redo skipped: no committed mark to undo")
        }

        panel.orderOut(nil)

        // Front window (T7/S3): the frontmost normal window from the actual
        // window list and the display its bounds land on.
        report.append(contentsOf: frontWindowReport())

        // Pin is controller state the view cannot show: every layer has to stop
        // taking clicks while the marks stay visible, and come back on unpin.
        let controller = OverlayController(captureService: CaptureService())
        controller.activate()
        report.append("pin before=\(controller.interactiveCanvasCount) pinned=\(controller.isPinned)")
        controller.togglePin()
        report.append("pin on=\(controller.interactiveCanvasCount) pinned=\(controller.isPinned)")
        controller.togglePin()
        report.append("pin off=\(controller.interactiveCanvasCount) pinned=\(controller.isPinned)")
        controller.deactivate(restoringFocus: false)

        // Whiteboard (T6/S3): pages, background colour and pan through the real
        // board canvas and its view.
        report.append(contentsOf: boardReport())

        // Board pages (T12/S9): delete, reorder, index select and pan reset
        // through the real view path.
        report.append(contentsOf: boardPagesReport())

        // Board blur of content (S1): through the real board canvas, a blur
        // mark diffuses the page's own content with no frame source, and the
        // capture shows the same result.
        report.append(contentsOf: boardBlurReport())

        // Palette in both system appearances: the same view must read on a light
        // and on a dark system, which a screenshot of one theme cannot prove.
        for (name, appearance) in [("light", NSAppearance.Name.aqua), ("dark", .darkAqua)] {
            let rendered = renderPalette(appearanceName: appearance, to: "/tmp/stare-palette-\(name).png")
            report.append("palette \(name) rendered=\(rendered)")
        }

        for (name, appearance) in [("light", NSAppearance.Name.aqua), ("dark", .darkAqua)] {
            let rendered = renderEditorChrome(appearanceName: appearance, to: "/tmp/stare-editor-\(name).png")
            report.append("editor chrome \(name) rendered=\(rendered)")
        }

        for (name, appearance) in [("light", NSAppearance.Name.aqua), ("dark", .darkAqua)] {
            let rendered = renderSettings(appearanceName: appearance, to: "/tmp/stare-settings-\(name).png")
            report.append("settings \(name) rendered=\(rendered)")
        }

        // A window measured before layout used to come out zero-sized: created,
        // "opened", and never seen.
        let settingsController = SettingsWindowController(state: EditorState())
        settingsController.show()
        RunLoop.current.run(until: Date().addingTimeInterval(0.4))
        if let window = NSApp.windows.first(where: { $0.title == "Stare Settings" }) {
            report.append(
                "settings window frame=\(window.frame) visible=\(window.isVisible) key=\(window.isKeyWindow)"
            )
            window.close()
        } else {
            report.append("FAIL: settings window not created")
        }

        // Render path: same code the overlay uses.
        let marks = sampleSession()
        let rendered = renderToPNG(strokes: marks.visibleStrokes)
        report.append("rendered marks=\(marks.visibleStrokes.count) png=\(imagePath) ok=\(rendered)")

        // Live blur (T5/S3): render a blur mark through the view's own draw
        // path over a synthetic screen and measure the pixels.
        report.append(contentsOf: blurRenderReport())

        // Edit cursor (T11/S6): select, move, scale, rotate and delete a mark
        // through the real view path, with the geometry asserts on the session.
        report.append(contentsOf: selectReport())

        // Numbered badge placement (owner report): a click with the number tool
        // must paint the whole round badge with its digit immediately, exactly
        // like a committed mark, in drawing mode and on the whiteboard.
        report.append(contentsOf: numberBadgeReport())

        // Numbered badge undo (owner-approved follow-up): the click-committed
        // mark has to reach the controller's global history exactly once, the
        // same way a drag-committed mark does — one ⌘Z removes exactly that
        // badge, ⇧⌘Z brings the same mark back, and the sequence neither gains
        // nor loses a number.
        report.append(contentsOf: numberUndoReport())

        // Escape (owner report): the drawing hint promises "esc to clear", so
        // with nothing selected Escape must clear the layer's marks and keep
        // drawing mode up — never leave it by way of the exit path.
        report.append(contentsOf: escapeReport())

        // Click pulse (T7/S3): the pulse curve sampled the way the pointer
        // timer samples it, and the highlight rendered through the real
        // pointer drawing path at rest, peak and settled.
        report.append(contentsOf: pointerPulseReport())

        return finish(report, code: 0)
    }

    private static func displayID(of screen: NSScreen) -> CGDirectDisplayID? {
        let key = NSDeviceDescriptionKey("NSScreenNumber")
        guard let number = screen.deviceDescription[key] as? NSNumber else { return nil }
        return CGDirectDisplayID(number.uint32Value)
    }

    // MARK: - Click pulse (T7)

    /// Samples the pulse curve the way the pointer timer samples it, then
    /// renders the highlight through the real pointer drawing path (the same
    /// `draw` the overlay uses) at rest, peak and settled, and measures the
    /// opaque pixel extent of each render: it must grow with the pulse and
    /// return to the resting size.
    private static func pointerPulseReport() -> [String] {
        var report: [String] = []
        let size = CGSize(width: 900, height: 600)
        let state = EditorState()
        state.pointerFadeWhenIdle = false
        let view = OverlayView(frame: CGRect(origin: .zero, size: size), state: state, onEscape: {})
        view.showsOnlyPointer = true
        let centre = CGPoint(x: size.width / 2, y: size.height / 2)

        var pulse = PointerPulse()
        let t0: TimeInterval = 100
        pulse.start(at: t0)
        let samples: [(String, TimeInterval)] = [
            ("click", t0),
            ("rise", t0 + pulse.riseDuration / 2),
            ("peak", t0 + pulse.riseDuration),
            ("settle", t0 + pulse.duration - pulse.settleDuration / 2),
            ("end", t0 + pulse.duration),
            ("after", t0 + pulse.duration + 1),
        ]
        let curve = samples.map { tag, t -> String in
            "\(tag)=\(String(format: "%.3f", pulse.scale(at: t)))"
        }.joined(separator: " ")
        report.append(
            "pointer pulse curve \(curve) duration=\(String(format: "%.2f", pulse.duration))s peak=\(pulse.peakScale)"
        )

        // A second click mid-pulse restarts the curve from the new instant.
        pulse.start(at: t0 + pulse.duration / 2)
        report.append(
            "pointer pulse restart scaleAtNewAnchor=\(String(format: "%.3f", pulse.scale(at: t0 + pulse.duration / 2))) expect 1.000"
        )
        pulse.start(at: t0)

        func render(_ tag: String, scale: CGFloat) -> CGSize? {
            view.followPointer(at: centre, pulseScale: scale)
            guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return nil }
            view.cacheDisplay(in: view.bounds, to: rep)
            guard let image = rep.cgImage else { return nil }
            _ = writePNG(image, to: "/tmp/stare-pointer-pulse-\(tag).png")
            return opaqueExtentPixels(image)
        }

        let rest = render("rest", scale: pulse.scale(at: t0))
        let peak = render("peak", scale: pulse.scale(at: t0 + pulse.riseDuration))
        let settled = render("settled", scale: pulse.scale(at: t0 + pulse.duration))

        guard let rest, let peak, let settled, rest.width > 0 else {
            report.append("FAIL: pointer pulse render failed rest=\(String(describing: rest)) peak=\(String(describing: peak)) settled=\(String(describing: settled))")
            return report
        }
        let grew = String(format: "%.2f", peak.width / rest.width)
        report.append("pointer pulse rest png=/tmp/stare-pointer-pulse-rest.png extent=\(Int(rest.width))x\(Int(rest.height))px")
        report.append("pointer pulse peak png=/tmp/stare-pointer-pulse-peak.png extent=\(Int(peak.width))x\(Int(peak.height))px grew=\(grew)x expect ~\(pulse.peakScale)")
        report.append(
            "pointer pulse settled extent=\(Int(settled.width))x\(Int(settled.height))px returnedToRest=\(settled == rest)"
        )
        let passed = peak.width > rest.width * 1.2 && peak.width < rest.width * 1.45 && settled == rest
        report.append("pointer pulse result=\(passed ? "PASS" : "FAIL")")
        return report
    }

    /// Bounding box of pixels whose alpha is visible, in pixels of the image.
    private static func opaqueExtentPixels(_ image: CGImage) -> CGSize? {
        let rep = NSBitmapImageRep(cgImage: image)
        guard let data = rep.bitmapData, rep.samplesPerPixel == 4, rep.bitsPerSample == 8 else { return nil }
        let width = rep.pixelsWide
        let height = rep.pixelsHigh
        let bytesPerRow = rep.bytesPerRow
        var minX = width, maxX = -1, minY = height, maxY = -1
        for y in 0..<height {
            let row = data.advanced(by: y * bytesPerRow)
            for x in 0..<width where row[x * 4 + 3] > 24 {
                if x < minX { minX = x }
                if x > maxX { maxX = x }
                if y < minY { minY = y }
                if y > maxY { maxY = y }
            }
        }
        guard maxX >= minX, maxY >= minY else { return nil }
        return CGSize(width: maxX - minX + 1, height: maxY - minY + 1)
    }

    // MARK: - Front window (T7)

    /// Reports the frontmost normal window from the actual window list — the
    /// answer the palette's "front window" placement uses — together with the
    /// display frames and the mapping result. No such window exercises the
    /// fallback (frontmost application heuristic).
    private static func frontWindowReport() -> [String] {
        var report: [String] = []
        let displayFrames = NSScreen.screens.map(\.frame)
        let primaryScreenTop = NSScreen.screens.first?.frame.maxY ?? 0
        report.append(
            "front window displays=[\(displayFrames.map(String.init(describing:)).joined(separator: ", "))] primaryTop=\(primaryScreenTop)"
        )
        let front = NSWorkspace.shared.frontmostApplication
        report.append(
            "front window frontmostApp=\(front?.localizedName ?? "nil") pid=\(front?.processIdentifier ?? -1)"
        )
        if let bounds = FrontWindowLocator.frontmostNormalWindowBounds() {
            let appKit = FrontWindowDisplay.appKitFrame(cgWindowBounds: bounds, primaryScreenTop: primaryScreenTop)
            let index = FrontWindowDisplay.displayIndex(windowFrame: appKit, displayFrames: displayFrames)
            let screen = index.map { NSScreen.screens[$0] }
            report.append(
                "front window cg=\(bounds) appkit=\(appKit) index=\(index.map(String.init) ?? "nil") screen=\(screen?.localizedName ?? "nil")"
            )
        } else {
            report.append("front window none in the window list; exercising the fallback")
            let fallback = front.flatMap {
                FrontWindowLocator.frontmostWindowBounds(ownerPID: $0.processIdentifier)
            }
            report.append("front window fallbackBounds=\(fallback.map(String.init(describing:)) ?? "nil")")
        }
        return report
    }

    // MARK: - Whiteboard (T6)

    /// Renders a view through its own draw path and writes it to a PNG.
    private static func renderView(_ view: NSView, to path: String) -> CGImage? {
        guard let representation = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return nil }
        view.cacheDisplay(in: view.bounds, to: representation)
        guard let image = representation.cgImage else { return nil }
        return writePNG(image, to: path) ? image : nil
    }

    /// Opens the board through its real canvas, draws a mark on page 1, moves
    /// to page 2 (which inherits the background and is flipped black with the
    /// \u{2318}B-equivalent toggle), draws a different mark and switches back.
    /// Reports per page the mark count and the rendered background colour
    /// sampled through the real view render, the capture composition over the
    /// page's own solid background, and the pan check: an existing mark's
    /// on-screen position shifts by the offset while its stored points do not
    /// change.
    private static func boardReport() -> [String] {
        var report: [String] = []
        guard let screen = NSScreen.screens.first else {
            report.append("FAIL: board no screens")
            return report
        }
        let state = EditorState()
        let board = WhiteboardPages()
        guard let canvas = DisplayCanvas(screen: screen, state: state, onEscape: {}, board: board),
              let view = canvas.boardView else {
            report.append("FAIL: board canvas could not be created")
            return report
        }

        let panel = canvas.panel
        panel.orderFrontRegardless()
        RunLoop.current.run(until: Date().addingTimeInterval(0.3))
        report.append("board panel visible=\(panel.isVisible) opaque=\(panel.isOpaque) isKey=\(panel.isKeyWindow)")

        // Page 1: one red pen mark through the panel's own event path.
        state.tool = .pen
        state.ink = .red
        sendDrag(to: panel, from: CGPoint(x: 150, y: 150), to: CGPoint(x: 350, y: 150))
        guard let mark1 = board.pages[0].session.strokes.first else {
            report.append("FAIL: board page 1 mark was not committed")
            panel.orderOut(nil)
            return report
        }
        report.append("board page=1 marks=\(board.pages[0].session.strokes.count) background=\(board.pages[0].background.rawValue)")

        // › past the last page creates page 2 inheriting the background; the
        // \u{2318}B toggle (togglePageBackground) flips page 2 to black while
        // page 1 stays white.
        view.selectNextPage()
        let inherited = board.currentPage.background == board.pages[0].background
        view.togglePageBackground()
        state.ink = .blue
        sendDrag(to: panel, from: CGPoint(x: 200, y: 400), to: CGPoint(x: 400, y: 400))
        guard let mark2 = board.pages[1].session.strokes.first else {
            report.append("FAIL: board page 2 mark was not committed")
            panel.orderOut(nil)
            return report
        }
        report.append(
            "board page=2 created=\(board.count == 2) inherited=\(inherited) "
                + "marks=\(board.pages[1].session.strokes.count) background=\(board.pages[1].background.rawValue)"
        )

        // Sample points derived from the stored marks, never hardcoded: events
        // sent to the panel land at window y measured from the bottom, so the
        // view point of a mark is read back through the view's own conversion.
        func samplePoint(of stroke: Stroke) -> CGPoint {
            guard let first = stroke.points.first, let last = stroke.points.last else { return .zero }
            return view.viewPoint(fromPage: CGPoint(x: (first.x + last.x) / 2, y: (first.y + last.y) / 2))
        }

        // Per page render through the real view path, background sampled.
        // The sample scale is the render's own backing scale, never assumed:
        // the view's window carries the screen's scale (1x on a non-Retina
        // main display), and sampling outside the bitmap answers nil.
        func sampleScale(of image: CGImage?) -> CGFloat {
            guard let image, view.bounds.width > 0 else { return 2 }
            return CGFloat(image.width) / max(view.bounds.width, 1)
        }
        view.selectPreviousPage()
        let page1 = renderView(view, to: "/tmp/stare-board-1.png")
        let page1Scale = sampleScale(of: page1)
        let page1Background = page1.map { rgb($0, at: CGPoint(x: 600, y: 100), scale: page1Scale) } ?? (red: -1, green: -1, blue: -1)
        let page1Mark = page1.map { rgb($0, at: samplePoint(of: mark1), scale: page1Scale) } ?? (red: -1, green: -1, blue: -1)
        let page1Ok = page1Background.red >= 245 && page1Mark.red >= 180 && page1Mark.green < 120
        report.append(
            "board page=1 png=/tmp/stare-board-1.png background=\(page1Background) expect 255/255/255 "
                + "mark@\(samplePoint(of: mark1))=\(page1Mark) expect red ok=\(page1Ok)"
        )

        view.selectNextPage()
        let page2 = renderView(view, to: "/tmp/stare-board-2.png")
        let page2Scale = sampleScale(of: page2)
        let page2Background = page2.map { rgb($0, at: CGPoint(x: 600, y: 100), scale: page2Scale) } ?? (red: -1, green: -1, blue: -1)
        let page2Mark = page2.map { rgb($0, at: samplePoint(of: mark2), scale: page2Scale) } ?? (red: -1, green: -1, blue: -1)
        let page2Ok = page2Background.red <= 15 && page2Mark.blue >= 180 && page2Mark.red < 120
        report.append(
            "board page=2 png=/tmp/stare-board-2.png background=\(page2Background) expect 0/0/0 "
                + "mark@\(samplePoint(of: mark2))=\(page2Mark) expect blue ok=\(page2Ok)"
        )

        // Capture path: marks composed over the page's own solid background at
        // the display's pixel size — never transparent, never a bare
        // background-coloured image with nothing drawn.
        let pixelSize = CGSize(
            width: screen.frame.size.width * screen.backingScaleFactor,
            height: screen.frame.size.height * screen.backingScaleFactor
        )
        let captureImage = board.pages[1].background.captureBase(
            width: Int(pixelSize.width),
            height: Int(pixelSize.height)
        ).flatMap { base in
            MarkCompositor.composite(marks: board.pages[1].session.strokes, over: base, scale: screen.backingScaleFactor)
        }
        let captureMid = CGPoint(
            x: ((mark2.points.first?.x ?? 0) + (mark2.points.last?.x ?? 0)) / 2,
            y: ((mark2.points.first?.y ?? 0) + (mark2.points.last?.y ?? 0)) / 2
        )
        let captureSamplePoint = CGPoint(x: captureMid.x * screen.backingScaleFactor, y: captureMid.y * screen.backingScaleFactor)
        let captureSample = captureImage.map { rgb($0, at: captureSamplePoint, scale: 1) } ?? (red: -1, green: -1, blue: -1)
        let captureOk = captureImage != nil && captureImage?.width == Int(pixelSize.width) && captureSample.blue >= 180
        report.append("board capture composed=\(captureImage != nil) size=\(captureImage.map { "\($0.width)x\($0.height)" } ?? "nil") mark@\(captureSamplePoint)=\(captureSample) expect blue ok=\(captureOk)")

        // Pan check: an existing mark moves on screen by the offset while its
        // stored points never change. One page point P is sampled before and
        // after the pan: before, it renders at P itself; after, at P shifted
        // by the negative of the offset, and its old screen spot is empty.
        view.selectPreviousPage()
        let storedBefore = board.pages[0].session.strokes.flatMap(\.points)
        let probePage = CGPoint(x: (mark1.points.first?.x ?? 0) + 10, y: mark1.points.first?.y ?? 0)
        let beforePan = renderView(view, to: "/tmp/stare-board-pan-before.png")
        let beforePanPoint = view.viewPoint(fromPage: probePage)
        let beforeHit = beforePan.map { rgb($0, at: beforePanPoint, scale: page1Scale) } ?? (red: -1, green: -1, blue: -1)
        view.pan(byPointerDelta: CGSize(width: 60, height: 40))
        let afterPan = renderView(view, to: "/tmp/stare-board-pan-after.png")
        let storedAfter = board.pages[0].session.strokes.flatMap(\.points)
        let afterPanPoint = view.viewPoint(fromPage: probePage)
        let afterHit = afterPan.map { rgb($0, at: afterPanPoint, scale: page1Scale) } ?? (red: -1, green: -1, blue: -1)
        let oldSpotHit = afterPan.map { rgb($0, at: beforePanPoint, scale: page1Scale) } ?? (red: -1, green: -1, blue: -1)
        let storedUnchanged = storedBefore == storedAfter
        let panOk = beforePan != nil && afterPan != nil
            && beforeHit.red >= 180 && beforeHit.green < 120
            && oldSpotHit.red >= 245
            && afterHit.red >= 180 && afterHit.green < 120
            && storedUnchanged
        report.append(
            "board pan offset=\(board.pages[0].offset) probe page=\(probePage) before@\(beforePanPoint)=\(beforeHit) expect red, "
                + "after old spot@\(beforePanPoint)=\(oldSpotHit) expect white, after shifted@\(afterPanPoint)=\(afterHit) expect red, "
                + "stored-unchanged=\(storedUnchanged) ok=\(panOk)"
        )

        panel.orderOut(nil)
        let passed = page1Ok && page2Ok && captureOk && panOk && inherited && board.count == 2
        report.append("board result=\(passed ? "PASS" : "FAIL")")
        return report
    }

    // MARK: - Board pages (T12/S9)

    /// Page management end to end through the real board view: adding pages,
    /// deleting the current one (which keeps the remaining pages and their
    /// marks), refusing to delete the last page, moving left/right (which keeps
    /// the moved page current, with its marks) and resetting the pan. The
    /// board's blur of its own content has its own section (`board blur`).
    private static func boardPagesReport() -> [String] {
        var report: [String] = []
        guard let screen = NSScreen.screens.first else {
            report.append("FAIL: board pages no screens")
            return report
        }
        let state = EditorState()
        let board = WhiteboardPages()
        guard let canvas = DisplayCanvas(screen: screen, state: state, onEscape: {}, board: board),
              let view = canvas.boardView else {
            report.append("FAIL: board pages canvas could not be created")
            return report
        }
        let panel = canvas.panel
        panel.orderFrontRegardless()
        RunLoop.current.run(until: Date().addingTimeInterval(0.3))
        defer { panel.orderOut(nil) }

        func markID(on pageIndex: Int) -> UUID? {
            board.pages[pageIndex].session.strokes.first?.id
        }

        // Adding pages: page 2 is created past the last one and gets a mark.
        state.tool = .pen
        state.ink = .red
        sendDrag(to: panel, from: CGPoint(x: 150, y: 150), to: CGPoint(x: 350, y: 150))
        let page1Mark = markID(on: 0)
        view.selectNextPage()
        state.ink = .blue
        sendDrag(to: panel, from: CGPoint(x: 200, y: 400), to: CGPoint(x: 400, y: 400))
        let addOk = board.count == 2 && board.currentIndex == 1
            && page1Mark != nil && markID(on: 1) != nil
        report.append(
            "board pages add count=\(board.count) current=\(board.currentIndex + 1) "
                + "page1Mark=\(page1Mark != nil) page2Mark=\(markID(on: 1) != nil) ok=\(addOk)"
        )

        // Deleting the current page keeps the remaining pages and their marks.
        let deleted = view.deleteCurrentPage()
        let deleteKeepsOthers = deleted && board.count == 1 && board.currentIndex == 0
            && board.pages[0].session.strokes.first?.id == page1Mark
            && !board.pages[0].session.strokes.isEmpty
        report.append(
            "board pages delete deleted=\(deleted) count=\(board.count) "
                + "page1MarkKept=\(board.pages[0].session.strokes.first?.id == page1Mark) ok=\(deleteKeepsOthers)"
        )

        // The last page cannot be deleted: the board never goes empty.
        let refused = !view.deleteCurrentPage() && board.count == 1
            && !board.pages[0].session.strokes.isEmpty
        report.append(
            "board pages last-page-refused count=\(board.count) marks=\(board.pages[0].session.strokes.count) ok=\(refused)"
        )

        // Rebuild three pages with distinct marks for the reorder checks.
        view.selectNextPage()
        state.ink = .blue
        sendDrag(to: panel, from: CGPoint(x: 200, y: 400), to: CGPoint(x: 400, y: 400))
        view.selectNextPage()
        state.ink = .green
        sendDrag(to: panel, from: CGPoint(x: 300, y: 250), to: CGPoint(x: 500, y: 250))
        let page1 = markID(on: 0), page2 = markID(on: 1), page3 = markID(on: 2)
        let rebuilt = board.count == 3 && page1 != nil && page2 != nil && page3 != nil
        report.append("board pages rebuilt count=\(board.count) marksDistinct=\(Set([page1, page2, page3]).count == 3) ok=\(rebuilt)")

        // ⌥← on page 3: it swaps with page 2 and stays current, marks intact.
        let movedLeft = view.moveCurrentPageLeft()
        let leftOk = movedLeft && board.count == 3 && board.currentIndex == 1
            && markID(on: 1) == page3 && markID(on: 2) == page2 && markID(on: 0) == page1
            && !board.currentPage.session.strokes.isEmpty
        func pageIndex(of id: UUID?) -> Int {
            guard let id else { return -1 }
            return board.pages.firstIndex { $0.session.strokes.first?.id == id } ?? -1
        }
        let order = [page1, page2, page3].map(pageIndex(of:)).map(String.init).joined(separator: ",")
        report.append(
            "board pages move-left moved=\(movedLeft) current=\(board.currentIndex + 1) "
                + "order=[\(order)] ok=\(leftOk)"
        )

        // ⌥→ twice: page 3 walks back to the end. At the end a further ⌥→ and
        // at the start a ⌥← are refused.
        view.moveCurrentPageRight()
        let refusedRight = !view.moveCurrentPageRight()
        view.moveCurrentPageLeft()
        let moveOk = leftOk && refusedRight
            && view.moveCurrentPageLeft()
            && board.currentIndex == 0 && markID(on: 0) == page3
            && !view.moveCurrentPageLeft()
            && board.currentIndex == 0 && board.count == 3
        report.append(
            "board pages move-right boundaryRefused=\(refusedRight) "
                + "current=\(board.currentIndex + 1)/\(board.count) ok=\(moveOk)"
        )

        // ⌘0: pan first through the real view path (the same translation a
        // space-drag produces), then the reset must return the offset to zero.
        // Asserting the pan before resetting is what makes a broken reset fail.
        view.pan(byPointerDelta: CGSize(width: -80, height: -50))
        let panned = board.currentPage.offset == CGSize(width: 80, height: 50)
        view.resetPagePan()
        let panReset = panned && board.currentPage.offset == .zero
        report.append(
            "board pages pan-reset panned=\(panned) offset=\(board.currentPage.offset) ok=\(panReset)"
        )

        // ⌘⌫ menu item: the key equivalent has to match what a real Delete key
        // press delivers ("\u{7F}", keyCode 51 — the same key the view
        // answers), which a synthetic key event through the real menu
        // machinery proves. A "\u{8}" binding never fires.
        let menuKeyReport = menuKeyProbe()
        report.append(contentsOf: menuKeyReport)
        let menuKeyOk = menuKeyReport.contains { $0.contains("ok=true") }

        let passed = addOk && deleteKeepsOthers && refused && rebuilt && leftOk && moveOk && panReset && menuKeyOk
        report.append("board pages result=\(passed ? "PASS" : "FAIL")")
        return report
    }

    // MARK: - Board blur of content (S1)

    /// The board's blur through the real view path: a blur mark diffuses the
    /// board's own content — the red rectangle painted before it — while a
    /// mark painted after it stays sharp, with no frame source and nothing
    /// asking for Screen Recording, and the board capture composes the same
    /// blurred patch over the page's solid background.
    private static func boardBlurReport() -> [String] {
        var report: [String] = []
        guard let screen = NSScreen.screens.first else {
            report.append("FAIL: board blur no screens")
            return report
        }
        let state = EditorState()
        let board = WhiteboardPages()
        guard let canvas = DisplayCanvas(screen: screen, state: state, onEscape: {}, board: board),
              let view = canvas.boardView else {
            report.append("FAIL: board blur canvas could not be created")
            return report
        }
        let panel = canvas.panel
        panel.orderFrontRegardless()
        RunLoop.current.run(until: Date().addingTimeInterval(0.3))
        defer { panel.orderOut(nil) }

        // S1: board canvases are never given a frame source, a display id or
        // blur interest — the board never reads frames for its blur.
        let noFrameSource = view.liveFrameSource == nil && view.displayID == 0 && !view.hasLiveBlurMarks
        report.append(
            "board blur frames frameSource=\(view.liveFrameSource == nil ? "nil" : "set") "
                + "displayID=\(view.displayID) blurInterest=\(view.hasLiveBlurMarks) ok=\(noFrameSource)"
        )

        // A red rectangle, then a blur overlapping its bottom border, then a
        // blue pen mark painted after the blur crossing the patch: draw order
        // decides what the blur diffuses and what stays sharp.
        state.tool = .rectangle
        state.ink = .red
        sendDrag(to: panel, from: CGPoint(x: 150, y: 150), to: CGPoint(x: 450, y: 300))
        state.tool = .blur
        sendDrag(to: panel, from: CGPoint(x: 200, y: 220), to: CGPoint(x: 500, y: 380))
        state.tool = .pen
        state.ink = .blue
        sendDrag(to: panel, from: CGPoint(x: 250, y: 250), to: CGPoint(x: 480, y: 330))
        let strokes = board.currentPage.session.strokes
        guard strokes.count == 3, strokes[1].tool == .blur else {
            report.append("FAIL: board blur marks were not committed (strokes=\(strokes.count))")
            return report
        }

        guard let rendered = renderView(view, to: "/tmp/stare-board-blur-content.png") else {
            report.append("FAIL: board blur render failed")
            return report
        }
        let scale = CGFloat(rendered.width) / max(view.bounds.width, 1)

        // Sample points come from the stored marks in page space (the drags
        // were sent in window coordinates), converted to view space through
        // the view's own mapping — never hardcoded screen positions.
        let rectMark = strokes[0], blurMark = strokes[1], penMark = strokes[2]
        let rectBox = PathBuilder.normalizedRect(from: rectMark.points[0], to: rectMark.points[1])
        let patch = PathBuilder.normalizedRect(from: blurMark.points[0], to: blurMark.points[1])
        // A border point of the rectangle inside the patch: the horizontal
        // border whose y the patch covers, at the patch's middle x.
        let borderY = patch.contains(CGPoint(x: patch.midX, y: rectBox.minY)) ? rectBox.minY : rectBox.maxY
        let borderX = min(max(patch.midX, rectBox.minX + 5), rectBox.maxX - 5)
        let borderPage = CGPoint(x: borderX, y: borderY)
        // A little into the patch from that border, over plain page.
        let tintedPage = CGPoint(x: borderX, y: borderY + (borderY == rectBox.minY ? 8 : -8))
        // The pen mark painted after the blur: its midpoint must cross the
        // patch, where it has to stay sharp.
        let penMid = CGPoint(
            x: (penMark.points[0].x + penMark.points[1].x) / 2,
            y: (penMark.points[0].y + penMark.points[1].y) / 2
        )
        // Border and page points well clear of the patch (more than two blur
        // radii from its edge).
        let outsideRedPage = CGPoint(x: rectBox.minX + 5, y: borderY)
        let outsidePagePoint = CGPoint(x: rectBox.minX - 40, y: rectBox.maxY + 40)
        guard patch.contains(borderPage), patch.contains(tintedPage), patch.contains(penMid),
              !patch.contains(outsideRedPage), board.currentPage.offset == .zero else {
            report.append(
                "FAIL: board blur geometry did not overlap (rect=\(rectBox) patch=\(patch) penMid=\(penMid))"
            )
            return report
        }

        func viewRGB(_ image: CGImage, _ page: CGPoint) -> (red: Int, green: Int, blue: Int) {
            rgb(image, at: view.viewPoint(fromPage: page), scale: scale)
        }
        let diffused = viewRGB(rendered, borderPage)
        let tinted = viewRGB(rendered, tintedPage)
        let afterSharp = viewRGB(rendered, penMid)
        let outsideRed = viewRGB(rendered, outsideRedPage)
        let outsidePage = viewRGB(rendered, outsidePagePoint)
        // On the border inside the patch: red (g≈59) and page white (255)
        // mixed — neither pure colour, the content was diffused, not cropped
        // from the page colour (the old behaviour read exactly 255).
        let diffusedOk = diffused.green > 70 && diffused.green < 252
        // Near the border the diffusion tints the plain page too.
        let tintedOk = tinted.green < 250 && tinted.green > 59
        // The pen mark painted after the blur reads as pure ink over the patch.
        let sharpOk = afterSharp.red < 80 && afterSharp.blue > 200
        // Outside the patch the border and the page are untouched.
        let outsideOk = outsideRed.red > 150 && outsideRed.green < 120
            && outsidePage.green > 240
        let contentOk = diffusedOk && tintedOk && sharpOk && outsideOk
        report.append(
            "board blur content diffused g=\(diffused.green) expect 70<g<252, "
                + "tinted g=\(tinted.green) expect 59<g<250, "
                + "afterSharp r=\(afterSharp.red) b=\(afterSharp.blue) expect sharp, "
                + "outside r=\(outsideRed.red) g=\(outsideRed.green) page g=\(outsidePage.green) "
                + "png=/tmp/stare-board-blur-content.png ok=\(contentOk)"
        )

        // The board capture composes the page the way captureBoardMarks does —
        // the page's solid background, the marks, the pan — and its patch must
        // show the same diffused result the view shows.
        guard let base = board.currentPage.background.captureBase(
            width: Int(view.bounds.width * scale),
            height: Int(view.bounds.height * scale)
        ) else {
            report.append("FAIL: board blur capture base failed")
            return report
        }
        guard let capture = MarkCompositor.composite(
            marks: board.currentPage.session.strokes,
            over: base,
            scale: scale,
            diffusesContent: true,
            offset: board.currentPage.offset
        ) else {
            report.append("FAIL: board blur capture composition failed")
            return report
        }
        let captureDiffused = viewRGB(capture, borderPage)
        let captureTinted = viewRGB(capture, tintedPage)
        let captureSharp = viewRGB(capture, penMid)
        func delta(_ a: (red: Int, green: Int, blue: Int), _ b: (red: Int, green: Int, blue: Int)) -> Int {
            max(abs(a.red - b.red), max(abs(a.green - b.green), abs(a.blue - b.blue)))
        }
        let diffusedDelta = delta(diffused, captureDiffused)
        let tintedDelta = delta(tinted, captureTinted)
        let sharpDelta = delta(afterSharp, captureSharp)
        // The blurred patch must agree almost exactly (same compositor, same
        // scale); the sharp pen mark's antialiasing may differ a little
        // between the view's scaled context and the pixel compositor.
        let captureOk = diffusedDelta <= 6 && tintedDelta <= 6 && sharpDelta <= 12
        report.append(
            "board blur capture diffusedDelta=\(diffusedDelta) tintedDelta=\(tintedDelta) "
                + "sharpDelta=\(sharpDelta) expect<=6/6/12 ok=\(captureOk)"
        )

        let passed = noFrameSource && contentOk && captureOk
        report.append("board blur result=\(passed ? "PASS" : "FAIL")")
        return report
    }

    /// Which character a real Delete key press has to be bound to in an
    /// NSMenuItem for the item to fire: the probe sends the exact key event a
    /// ⌘⌫ press produces (characters "\u{7F}", keyCode 51) through the real
    /// menu key-equivalent machinery with each candidate binding.
    private static func menuKeyProbe() -> [String] {
        final class ProbeTarget: NSObject {
            var fired = false
            @objc func hit() { fired = true }
        }

        func fires(with key: String) -> Bool {
            let target = ProbeTarget()
            let item = NSMenuItem(title: "probe", action: #selector(ProbeTarget.hit), keyEquivalent: key)
            item.keyEquivalentModifierMask = .command
            item.target = target
            let menu = NSMenu()
            menu.addItem(item)
            guard let event = NSEvent.keyEvent(
                with: .keyDown,
                location: .zero,
                modifierFlags: .command,
                timestamp: 0,
                windowNumber: 0,
                context: nil,
                characters: "\u{7F}",
                charactersIgnoringModifiers: "\u{7F}",
                isARepeat: false,
                keyCode: 51
            ) else { return false }
            _ = menu.performKeyEquivalent(with: event)
            return target.fired
        }

        let backspaceBindingFires = fires(with: "\u{8}")
        let deleteBindingFires = fires(with: "\u{7F}")
        let ok = deleteBindingFires && !backspaceBindingFires
        return [
            "board pages menu-key backspace(\\u{8})-fires=\(backspaceBindingFires) "
                + "delete(\\u{7F})-fires=\(deleteBindingFires) ok=\(ok)",
        ]
    }

    // MARK: - Select (T11/S6)

    /// The edit cursor end to end through the real view path: draw a rectangle,
    /// select it, move it, scale it, rotate it, deselect it, delete it. Every
    /// assert is on the session's geometry — what a capture composes from — and
    /// the renders go to /tmp for a visual check of the selection chrome.
    private static func selectReport() -> [String] {
        var report: [String] = []
        let size = CGSize(width: 900, height: 600)
        let state = EditorState()
        state.tool = .rectangle
        let view = OverlayView(frame: CGRect(origin: .zero, size: size), state: state, onEscape: {})

        // A real borderless window, the way the board section drives its view:
        // for a windowless view the event-to-view conversion is ambient and
        // mirrors y, so coordinates would not be trustworthy. Events carry
        // window-base coordinates (bottom-left origin); the view fills the
        // window and is flipped, so view point P is window point (P.x, H-P.y).
        let window = NSWindow(
            contentRect: CGRect(origin: .zero, size: size),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.contentView = view
        window.orderFrontRegardless()
        RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        defer { window.orderOut(nil) }

        func send(_ type: NSEvent.EventType, _ point: CGPoint) {
            guard let event = NSEvent.mouseEvent(
                with: type,
                location: CGPoint(x: point.x, y: size.height - point.y),
                modifierFlags: [],
                timestamp: ProcessInfo.processInfo.systemUptime,
                windowNumber: window.windowNumber,
                context: nil,
                eventNumber: 1,
                clickCount: 1,
                pressure: 1
            ) else {
                report.append("FAIL: select \(type.rawValue) event could not be created")
                return
            }
            switch type {
            case .leftMouseDown: view.mouseDown(with: event)
            case .leftMouseDragged: view.mouseDragged(with: event)
            default: view.mouseUp(with: event)
            }
        }
        func drag(from start: CGPoint, to end: CGPoint) {
            send(.leftMouseDown, start)
            send(.leftMouseDragged, CGPoint(x: (start.x + end.x) / 2, y: (start.y + end.y) / 2))
            send(.leftMouseUp, end)
        }
        @discardableResult
        func key(_ keyCode: UInt16, _ characters: String) -> Bool {
            guard let event = NSEvent.keyEvent(
                with: .keyDown,
                location: .zero,
                modifierFlags: [],
                timestamp: ProcessInfo.processInfo.systemUptime,
                windowNumber: 0,
                context: nil,
                characters: characters,
                charactersIgnoringModifiers: characters,
                isARepeat: false,
                keyCode: keyCode
            ) else { return false }
            view.keyDown(with: event)
            return true
        }

        // The mark to edit: one rectangle through the real drag path.
        drag(from: CGPoint(x: 100, y: 100), to: CGPoint(x: 300, y: 200))
        guard var mark = view.session.strokes.first, mark.tool == .rectangle else {
            report.append("FAIL: select rectangle was not committed")
            return report
        }
        let originalPoints = mark.points
        let originalGeometry = PathBuilder.path(for: mark).boundingBoxOfPath

        // Select and move in one gesture: click the body, drag it. The session
        // keeps exactly one mark, transformed in place — never a second one.
        state.tool = .select
        drag(from: CGPoint(x: 200, y: 150), to: CGPoint(x: 350, y: 220))
        guard let moved = view.session.strokes.first, moved.id == mark.id,
              view.session.strokes.count == 1 else {
            report.append("FAIL: the move did not transform the selected mark")
            return report
        }
        let expected = originalPoints.map { CGPoint(x: $0.x + 150, y: $0.y + 70) }
        let moveOk = moved.points == expected
        report.append(
            "select move points=\(moved.points.map { "(\(Int($0.x)),\(Int($0.y)))" }.joined(separator: "→")) "
                + "expect +150,+70 marks=\(view.session.strokes.count) ok=\(moveOk)"
        )
        mark = moved

        // One drag is one undo step: undo restores the drawn geometry, redo
        // reapplies the move, all through the session's transform journal.
        let undoRestoresMove = view.undoMark(id: mark.id)
            && view.session.strokes.first?.points == originalPoints
            && view.redoMark(id: mark.id)
            && view.session.strokes.first?.points == moved.points
        report.append("select move undo-restores redo-reapplies ok=\(undoRestoresMove)")

        _ = renderView(view, to: "/tmp/stare-select-selected.png")

        // Scale from the bottom-right corner handle: exactly 2×, and the shape
        // keeps its proportions (measured on the geometry, whose box has no
        // constant padding).
        let handles = MarkSelection(stroke: mark).handlePoints(
            rotationHandleOffset: MarkSelection.defaultRotationHandleOffset
        )
        guard let draggedHandle = handles[.bottomRight], let anchorHandle = handles[.topLeft] else {
            report.append("FAIL: selection handles missing")
            return report
        }
        drag(
            from: draggedHandle,
            to: CGPoint(x: anchorHandle.x + 2 * (draggedHandle.x - anchorHandle.x),
                        y: anchorHandle.y + 2 * (draggedHandle.y - anchorHandle.y))
        )
        guard let scaled = view.session.strokes.first else {
            report.append("FAIL: scale did not commit")
            return report
        }
        let scaledGeometry = PathBuilder.path(for: scaled).boundingBoxOfPath
        let scaleRatioW = scaledGeometry.width / originalGeometry.width
        let scaleRatioH = scaledGeometry.height / originalGeometry.height
        let scaleOk = abs(scaleRatioW - 2) < 0.01 && abs(scaleRatioH - 2) < 0.01
        report.append(
            "select scale geometry \(String(format: "%.1f", scaledGeometry.width))x\(String(format: "%.1f", scaledGeometry.height)) "
                + "ratio=\(String(format: "%.3f", scaleRatioW))x\(String(format: "%.3f", scaleRatioH)) expect 2.000x2.000 ok=\(scaleOk)"
        )
        mark = scaled

        // Rotate from the knob: a quarter turn about the anchor. The rotated
        // body is still hit where it now looks, and the old unrotated corner
        // is empty — the shape never changed, only its orientation.
        let pivot = mark.anchor
        let knob = MarkSelection(stroke: mark).handlePoints(
            rotationHandleOffset: MarkSelection.defaultRotationHandleOffset
        )[.rotation]!
        let unrotatedCorner = CGPoint(x: mark.bounds.maxX, y: mark.bounds.maxY)
        let cornerHitBefore = mark.hitTest(unrotatedCorner, radius: 3)
        drag(from: knob, to: knob.applying(Stroke.rotationTransform(around: pivot, by: .pi / 2)))
        guard let rotated = view.session.strokes.first else {
            report.append("FAIL: rotate did not commit")
            return report
        }
        let quarterTurn = abs(rotated.rotation - .pi / 2) < 0.01
        let rotatedCorner = unrotatedCorner.applying(
            Stroke.rotationTransform(around: rotated.anchor, by: rotated.rotation)
        )
        let hitOk = cornerHitBefore
            && rotated.hitTest(rotatedCorner, radius: 3)
            && !rotated.hitTest(unrotatedCorner, radius: 3)
        report.append(
            "select rotate angle=\(String(format: "%.3f", rotated.rotation))rad expect 1.571, "
                + "rotated corner hit=\(rotated.hitTest(rotatedCorner, radius: 3)) expect true, "
                + "old corner hit=\(rotated.hitTest(unrotatedCorner, radius: 3)) expect false ok=\(hitOk)"
        )
        _ = renderView(view, to: "/tmp/stare-select-rotated.png")

        // ⎋ gives the selection up without leaving drawing mode.
        var escapeLeftDrawingMode = false
        view.onEscape = { escapeLeftDrawingMode = true }
        let escapeOk = key(53, "\u{1B}") && view.selectedMarkID == nil && !escapeLeftDrawingMode
        report.append(
            "select escape cleared=\(view.selectedMarkID == nil) stayedInMode=\(!escapeLeftDrawingMode) ok=\(escapeOk)"
        )

        // Select again and delete with ⌫ through the session.
        drag(from: rotated.anchor, to: rotated.anchor)
        let reselected = view.selectedMarkID == rotated.id
        let deleteKeyEvent = key(51, "\u{7F}") // ⌫
        let deleteOk = reselected && deleteKeyEvent
            && view.session.strokes.isEmpty && view.selectedMarkID == nil
        report.append(
            "select delete reselected=\(reselected) marks=\(view.session.strokes.count) expect 0 ok=\(deleteOk)"
        )

        let passed = moveOk && undoRestoresMove && scaleOk && quarterTurn && hitOk && escapeOk && deleteOk
        report.append("select result=\(passed ? "PASS" : "FAIL")")
        return report
    }

    // MARK: - Numbered badge placement

    /// The dirty-rect recording both the overlay and the board probes share.
    private protocol InvalidationsRecording: OverlayView {
        func resetInvalidations()
        var recordedInvalidations: [NSRect] { get }
    }

    /// Records the dirty rects the view asks AppKit to repaint, so the self
    /// test can replay an NSView's real incremental painting regime.
    private final class RecordingOverlayView: OverlayView, InvalidationsRecording {
        private(set) var recordedInvalidations: [NSRect] = []

        func resetInvalidations() { recordedInvalidations.removeAll() }

        override func setNeedsDisplay(_ invalidRect: NSRect) {
            recordedInvalidations.append(invalidRect)
            super.setNeedsDisplay(invalidRect)
        }
    }

    /// A numbered step commits inside `session.begin`, so `mouseUp` never runs
    /// for it and the badge must be invalidated at its full size on mouse-down.
    /// The rule pinned here: the pixels the app paints for the placed mark (only
    /// the rects the view itself invalidated, over the pre-click pixels — the
    /// real regime AppKit repaints with) must equal the pixels of the same
    /// stroke repainted as a committed mark. A badge invalidated as the small
    /// drag band around the click point fails both: the rim pixels outside the
    /// band are never painted and the digit is clipped away.
    private static func numberBadgeReport() -> [String] {
        var report: [String] = []
        let size = CGSize(width: 900, height: 600)

        func overlayRender(_ view: NSView) -> CGImage? {
            guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return nil }
            view.cacheDisplay(in: view.bounds, to: rep)
            return rep.cgImage
        }

        /// The incremental painting regime: repaint exactly `rect` with the
        /// view's fresh render, blended over the previous pixels. Rects the
        /// view never marks keep whatever was on screen before — there is no
        /// full repaint to rescue a forgotten region.
        func flush(_ context: CGContext, with image: CGImage, rect: CGRect, scale: CGFloat) {
            context.saveGState()
            // Overlay space is top-left origin; the bitmap context is bottom-left.
            context.clip(to: CGRect(
                x: rect.minX * scale,
                y: (size.height - rect.maxY) * scale,
                width: rect.width * scale,
                height: rect.height * scale
            ))
            context.draw(image, in: CGRect(x: 0, y: 0, width: size.width * scale, height: size.height * scale))
            context.restoreGState()
        }

        /// Places one numbered badge at `centre` through the real mouse-down
        /// path, then repaints only the rects the view itself invalidated over
        /// a baseline of the pre-click pixels. Returns the flushed screen
        /// pixels and the full committed repaint's pixels at the badge rim,
        /// the fill beside the digit and a `digitVisible` scan, so the flushed
        /// screen can be asserted equal to what a committed mark renders.
        func placementCheck(
            view: InvalidationsRecording, window: NSWindow, centre: CGPoint
        ) -> (
            rects: Int, flushedRim: (Int, Int, Int), flushedFill: (Int, Int, Int), digitVisible: Bool,
            committedRim: (Int, Int, Int), committedFill: (Int, Int, Int), parityOk: Bool
        )? {
            view.resetInvalidations()
            // The pixels before the click, with the session still empty.
            guard let baseline = overlayRender(view) else { return nil }
            guard let down = NSEvent.mouseEvent(
                with: .leftMouseDown,
                location: CGPoint(x: centre.x, y: size.height - centre.y),
                modifierFlags: [],
                timestamp: ProcessInfo.processInfo.systemUptime,
                windowNumber: window.windowNumber,
                context: nil,
                eventNumber: 1,
                clickCount: 1,
                pressure: 1
            ) else { return nil }
            view.mouseDown(with: down)
            guard let mark = view.session.strokes.last, mark.tool == .number else { return nil }
            guard let first = mark.points.first else { return nil }

            let renderScale = CGFloat(baseline.width) / max(view.bounds.width, 1)
            guard let space = CGColorSpace(name: CGColorSpace.sRGB),
                  let screen = CGContext(
                    data: nil,
                    width: Int(size.width * renderScale),
                    height: Int(size.height * renderScale),
                    bitsPerComponent: 8,
                    bytesPerRow: 0,
                    space: space,
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                  ) else { return nil }
            // The pixels before the click: the page surface with the empty
            // overlay already drawn on it.
            screen.draw(baseline, in: CGRect(x: 0, y: 0, width: size.width * renderScale, height: size.height * renderScale))

            let recorded = view.recordedInvalidations.filter { !$0.isEmpty && $0.intersects(view.bounds) }
            guard let fresh = overlayRender(view) else { return nil }
            for rect in recorded {
                flush(screen, with: fresh, rect: rect, scale: renderScale)
            }
            guard let screenImage = screen.makeImage(),
                  let committed = overlayRender(view) else { return nil }

            let rim = CGPoint(x: first.x, y: first.y - 10)
            let fill = CGPoint(x: first.x + 8, y: first.y)
            let flushedRim = rgb(screenImage, at: rim, scale: renderScale)
            let flushedFill = rgb(screenImage, at: fill, scale: renderScale)
            let committedRim = rgb(committed, at: rim, scale: renderScale)
            let committedFill = rgb(committed, at: fill, scale: renderScale)
            var digitVisible = false
            let digitRangeX = stride(from: -6.0, through: 6.0, by: 2)
            let digitRangeY = stride(from: -9.0, through: 9.0, by: 2)
            for dx in digitRangeX {
                for dy in digitRangeY {
                    let point = CGPoint(x: first.x + dx, y: first.y + dy)
                    let pixel = rgb(screenImage, at: point, scale: renderScale)
                    if pixel.0 > 230 && pixel.1 > 230 && pixel.2 > 230 { digitVisible = true }
                }
            }
            // Same stroke, painted the way the app paints a placed mark and
            // repainted as a committed mark: the pixels must agree.
            func close(_ a: (Int, Int, Int), _ b: (Int, Int, Int)) -> Bool {
                abs(a.0 - b.0) <= 10 && abs(a.1 - b.1) <= 10 && abs(a.2 - b.2) <= 10
            }
            let parityOk = close(flushedRim, committedRim) && close(flushedFill, committedFill)
            return (
                rects: recorded.count, flushedRim: flushedRim, flushedFill: flushedFill,
                digitVisible: digitVisible, committedRim: committedRim, committedFill: committedFill,
                parityOk: parityOk
            )
        }

        func borderlessWindow(_ view: NSView) -> NSWindow {
            let window = NSWindow(
                contentRect: CGRect(origin: .zero, size: size),
                styleMask: [.borderless],
                backing: .buffered,
                defer: false
            )
            window.contentView = view
            window.orderFrontRegardless()
            RunLoop.current.run(until: Date().addingTimeInterval(0.2))
            return window
        }

        // Drawing mode: the badge on the transparent overlay.
        let state = EditorState()
        state.tool = .number
        state.ink = .red
        let overlay = RecordingOverlayView(frame: CGRect(origin: .zero, size: size), state: state, onEscape: {})
        let overlayWindow = borderlessWindow(overlay)
        defer { overlayWindow.orderOut(nil) }

        if let check = placementCheck(view: overlay, window: overlayWindow, centre: CGPoint(x: 450, y: 300)) {
            let rimOk = check.flushedRim.0 >= 200 && check.flushedRim.1 < 150
            let fillOk = check.flushedFill.0 >= 200 && check.flushedFill.1 < 150
            let ok = check.rects > 0 && rimOk && fillOk && check.digitVisible && check.parityOk
            report.append(
                "number overlay rects=\(check.rects) rim=\(check.flushedRim) expect red, "
                    + "fill=\(check.flushedFill) expect red, digit=\(check.digitVisible) expect true, "
                    + "committed rim=\(check.committedRim) fill=\(check.committedFill) parity=\(check.parityOk) "
                    + "png=/tmp/stare-number-overlay.png ok=\(ok)"
            )
        } else {
            report.append("FAIL: number overlay badge was not committed")
            return report
        }
        _ = overlayRender(overlay).map { writePNG($0, to: "/tmp/stare-number-overlay.png") }

        // The whiteboard: same click path over the page's own background.
        let boardState = EditorState()
        boardState.tool = .number
        boardState.ink = .blue
        let board = WhiteboardPages()
        let boardView = RecordingBoardView(frame: CGRect(origin: .zero, size: size), state: boardState, board: board, onEscape: {})
        let boardWindow = borderlessWindow(boardView)
        defer { boardWindow.orderOut(nil) }

        if let check = placementCheck(view: boardView, window: boardWindow, centre: CGPoint(x: 300, y: 300)) {
            let rimOk = check.flushedRim.2 >= 180 && check.flushedRim.0 < 120
            let fillOk = check.flushedFill.2 >= 180 && check.flushedFill.0 < 120
            let ok = check.rects > 0 && rimOk && fillOk && check.digitVisible && check.parityOk
            report.append(
                "number board rects=\(check.rects) rim=\(check.flushedRim) expect blue, "
                    + "fill=\(check.flushedFill) expect blue, digit=\(check.digitVisible) expect true, "
                    + "committed rim=\(check.committedRim) fill=\(check.committedFill) parity=\(check.parityOk) "
                    + "png=/tmp/stare-number-board.png ok=\(ok)"
            )
        } else {
            report.append("FAIL: number board badge was not committed")
            return report
        }
        _ = overlayRender(boardView).map { writePNG($0, to: "/tmp/stare-number-board.png") }

        let passed = report.allSatisfy { !$0.contains("ok=false") && !$0.contains("FAIL") }
        report.append("number result=\(passed ? "PASS" : "FAIL")")
        return report
    }

    /// The whiteboard flavour of the recording view: the incremental-painting
    /// probe has to run through the board's own click path too, where the same
    /// mouse-down code lays the badge over the page background.
    private final class RecordingBoardView: WhiteboardView, InvalidationsRecording {
        private(set) var recordedInvalidations: [NSRect] = []

        func resetInvalidations() { recordedInvalidations.removeAll() }

        override func setNeedsDisplay(_ invalidRect: NSRect) {
            recordedInvalidations.append(invalidRect)
            super.setNeedsDisplay(invalidRect)
        }
    }

    // MARK: - Escape clears and stays

    /// Escape through the real key path in a real borderless window: with a
    /// mark selected it still gives the selection up first; with nothing
    /// selected it clears the layer's marks and stays in drawing mode (the
    /// exit path stays silent — leaving stays on ⌥⇧A / Done). The whiteboard
    /// flavour clears the current page and the board stays open.
    private static func escapeReport() -> [String] {
        var report: [String] = []
        let size = CGSize(width: 900, height: 600)

        func borderlessWindow(_ view: NSView) -> NSWindow {
            let window = NSWindow(
                contentRect: CGRect(origin: .zero, size: size),
                styleMask: [.borderless],
                backing: .buffered,
                defer: false
            )
            window.contentView = view
            window.orderFrontRegardless()
            RunLoop.current.run(until: Date().addingTimeInterval(0.2))
            return window
        }
        func mouseEvent(_ type: NSEvent.EventType, at point: CGPoint, window: NSWindow) -> NSEvent? {
            NSEvent.mouseEvent(
                with: type,
                location: CGPoint(x: point.x, y: size.height - point.y),
                modifierFlags: [],
                timestamp: ProcessInfo.processInfo.systemUptime,
                windowNumber: window.windowNumber,
                context: nil,
                eventNumber: 1,
                clickCount: 1,
                pressure: 1
            )
        }
        func drag(_ view: OverlayView, window: NSWindow, from start: CGPoint, to end: CGPoint) {
            view.mouseDown(with: mouseEvent(.leftMouseDown, at: start, window: window)!)
            view.mouseDragged(with: mouseEvent(.leftMouseDragged, at: end, window: window)!)
            view.mouseUp(with: mouseEvent(.leftMouseUp, at: end, window: window)!)
        }
        @discardableResult
        func key(_ view: NSView, _ keyCode: UInt16, _ characters: String, modifiers: NSEvent.ModifierFlags = []) -> Bool {
            guard let event = NSEvent.keyEvent(
                with: .keyDown,
                location: .zero,
                modifierFlags: modifiers,
                timestamp: ProcessInfo.processInfo.systemUptime,
                windowNumber: 0,
                context: nil,
                characters: characters,
                charactersIgnoringModifiers: characters,
                isARepeat: false,
                keyCode: keyCode
            ) else { return false }
            view.keyDown(with: event)
            return true
        }

        // The overlay: drawing mode is a plain view in a real window.
        let state = EditorState()
        state.tool = .pen
        state.ink = .red
        let view = OverlayView(frame: CGRect(origin: .zero, size: size), state: state, onEscape: {})
        let window = borderlessWindow(view)
        defer { window.orderOut(nil) }

        var exitCalls = 0
        var clearCalls = 0
        view.onEscape = { exitCalls += 1 }
        // The controller's real routing: drop the display's marks and keep
        // the layer up.
        view.onClearMarks = { clearCalls += 1; view.clear() }

        drag(view, window: window, from: CGPoint(x: 100, y: 100), to: CGPoint(x: 300, y: 140))
        guard view.session.strokes.count == 1 else {
            report.append("FAIL: escape pen mark was not committed")
            return report
        }

        // Escape with nothing selected: the hint's promise — the marks clear
        // and drawing mode stays up; the exit path never fires.
        key(view, 53, "\u{1B}")
        let cleared = view.session.strokes.isEmpty && clearCalls == 1
        let stayedInDrawing = exitCalls == 0
        report.append(
            "escape cleared=\(cleared) stayedInDrawing=\(stayedInDrawing) "
                + "marks=\(view.session.strokes.count) expect 0 exits=\(exitCalls) expect 0 ok=\(cleared && stayedInDrawing)"
        )

        // A new stroke can be drawn immediately after the clear.
        drag(view, window: window, from: CGPoint(x: 400, y: 200), to: CGPoint(x: 500, y: 240))
        let keepsDrawing = view.session.strokes.count == 1
        report.append("escape keeps-drawing marks=\(view.session.strokes.count) expect 1 ok=\(keepsDrawing)")

        // With a mark selected, Escape still clears the selection first.
        state.tool = .select
        drag(view, window: window, from: CGPoint(x: 450, y: 220), to: CGPoint(x: 450, y: 220))
        let reselected = view.selectedMarkID != nil
        key(view, 53, "\u{1B}")
        let selectionFirst = reselected && view.selectedMarkID == nil
            && view.session.strokes.count == 1 && clearCalls == 1 && exitCalls == 0
        report.append(
            "escape selection-first deselected=\(view.selectedMarkID == nil) marks=\(view.session.strokes.count) expect 1 "
                + "clears=\(clearCalls) expect 1 ok=\(selectionFirst)"
        )

        // The whiteboard: Escape clears the current page and the board stays open.
        let boardState = EditorState()
        boardState.tool = .pen
        boardState.ink = .blue
        let board = WhiteboardPages()
        let boardView = WhiteboardView(frame: CGRect(origin: .zero, size: size), state: boardState, board: board, onEscape: {})
        let boardWindow = borderlessWindow(boardView)
        defer { boardWindow.orderOut(nil) }

        var boardExitCalls = 0
        var boardClearCalls = 0
        boardView.onEscape = { boardExitCalls += 1 }
        boardView.onClearMarks = { boardClearCalls += 1; boardView.clear() }
        drag(boardView, window: boardWindow, from: CGPoint(x: 150, y: 150), to: CGPoint(x: 350, y: 190))
        guard board.pages[0].session.strokes.count == 1 else {
            report.append("FAIL: escape board mark was not committed")
            return report
        }
        key(boardView, 53, "\u{1B}")
        let boardCleared = board.pages[0].session.strokes.isEmpty && boardClearCalls == 1
        let boardStayedOpen = boardExitCalls == 0 && board.count == 1
        report.append(
            "escape board cleared=\(boardCleared) stayedOpen=\(boardStayedOpen) "
                + "marks=\(board.pages[0].session.strokes.count) expect 0 exits=\(boardExitCalls) expect 0 ok=\(boardCleared && boardStayedOpen)"
        )

        let passed = cleared && stayedInDrawing && keepsDrawing && selectionFirst
            && boardCleared && boardStayedOpen
        report.append("escape result=\(passed ? "PASS" : "FAIL")")
        return report
    }

    // MARK: - Number undo (global history)

    /// A numbered step commits inside `DrawingSession.begin`, so `mouseUp`
    /// never runs for it. The rule pinned here: the placement still reaches
    /// the controller's global history exactly once, the same way a
    /// drag-committed mark does — one ⌘Z removes exactly that badge, ⇧⌘Z
    /// brings the same mark back, and the sequence neither gains nor loses a
    /// number. Driven through the real controller canvases and their history.
    private static func numberUndoReport() -> [String] {
        var report: [String] = []
        let controller = OverlayController(captureService: CaptureService())
        controller.activate()
        defer {
            if controller.isBoardActive { controller.toggleBoard() }
            controller.deactivate(restoringFocus: false)
        }
        RunLoop.current.run(until: Date().addingTimeInterval(0.2))

        controller.state.tool = .number

        /// One real click through the view's own mouse-down path; returns the
        /// placed badge.
        func place(on view: OverlayView, at point: CGPoint) -> Stroke? {
            guard let window = view.window else { return nil }
            let height = view.bounds.height
            guard let down = NSEvent.mouseEvent(
                with: .leftMouseDown,
                location: CGPoint(x: point.x, y: height - point.y),
                modifierFlags: [],
                timestamp: ProcessInfo.processInfo.systemUptime,
                windowNumber: window.windowNumber,
                context: nil,
                eventNumber: 1,
                clickCount: 1,
                pressure: 1
            ) else { return nil }
            view.mouseDown(with: down)
            return view.session.strokes.last
        }

        // Drawing mode: place, undo through the controller, redo through it.
        guard let view = controller.selfTestViews.first else {
            report.append("FAIL: number undo no drawing canvas")
            return report
        }
        guard let placed = place(on: view, at: CGPoint(x: 320, y: 320)),
              placed.stepNumber == 1, view.session.strokes.count == 1 else {
            report.append("FAIL: number undo badge was not placed")
            return report
        }
        controller.undo()
        let removed = view.session.strokes.isEmpty && view.session.stepCount == 0
        controller.redo()
        guard let restored = view.session.strokes.first else {
            report.append("FAIL: number undo redo restored nothing")
            return report
        }
        // The same mark comes back — which only counts when the undo really
        // removed it — with its number, and the sequence moves on to 2.
        let restoredOk = removed && restored.id == placed.id && restored.stepNumber == 1
            && view.session.stepCount == 1 && view.session.nextStepNumber == 2
        // The sequence keeps running without a gap: the next badge takes
        // number 2, and undoing it hands the number back while badge 1 stays.
        guard let second = place(on: view, at: CGPoint(x: 520, y: 320)), second.stepNumber == 2 else {
            report.append("FAIL: number undo next badge did not take number 2")
            return report
        }
        controller.undo()
        let keepsSequence = view.session.strokes.count == 1
            && view.session.strokes.first?.stepNumber == 1
            && view.session.nextStepNumber == 2
        report.append(
            "number undo removed=\(removed) restored=\(restoredOk) keep=\(keepsSequence) "
                + "marks=\(view.session.strokes.count) expect 1 ok=\(removed && restoredOk && keepsSequence)"
        )
        let overlayOk = removed && restoredOk && keepsSequence

        // The whiteboard: the same controller path over the board's canvases,
        // and the page's own session (what captures compose from) stays in step.
        controller.toggleBoard()
        guard let boardView = controller.selfTestViews.first as? WhiteboardView else {
            report.append("FAIL: number undo no board canvas")
            return report
        }
        guard let boardPlaced = place(on: boardView, at: CGPoint(x: 400, y: 400)),
              boardPlaced.stepNumber == 1 else {
            report.append("FAIL: number undo board badge was not placed")
            return report
        }
        controller.undo()
        let boardRemoved = boardView.session.strokes.isEmpty
            && boardView.board.currentPage.session.strokes.isEmpty
        controller.redo()
        let boardRestoredMark = boardView.session.strokes.first
        let boardRestored = boardRemoved && boardRestoredMark?.id == boardPlaced.id
            && boardRestoredMark?.stepNumber == 1
            && boardView.board.currentPage.session.strokes.first?.id == boardPlaced.id
        report.append(
            "number undo board removed=\(boardRemoved) restored=\(boardRestored) "
                + "marks=\(boardView.session.strokes.count) expect 1 ok=\(boardRemoved && boardRestored)"
        )

        let passed = overlayOk && boardRemoved && boardRestored
        report.append("number undo result=\(passed ? "PASS" : "FAIL")")
        return report
    }

    /// What the window server itself believes is on screen for this process.
    private static func windowServerReport(for panel: NSWindow) -> [String] {
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        let list = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] ?? []
        let pid = ProcessInfo.processInfo.processIdentifier
        let ours = list.filter { ($0[kCGWindowOwnerPID as String] as? Int32) == pid }

        var lines = ["windowServerOnScreen=(\(ours.count)) for windowNumber=\(panel.windowNumber)"]
        for window in ours {
            let number = window[kCGWindowNumber as String] ?? "?"
            let layer = window[kCGWindowLayer as String] ?? "?"
            let bounds = window[kCGWindowBounds as String] ?? "?"
            let alpha = window[kCGWindowAlpha as String] ?? "?"
            lines.append("  ws id=\(number) layer=\(layer) alpha=\(alpha) bounds=\(bounds)")
        }
        return lines
    }

    /// Renders the settings form with a fixed appearance.
    private static func renderSettings(appearanceName: NSAppearance.Name, to path: String) -> Bool {
        let hosting = NSHostingView(rootView: SettingsView(state: EditorState()))
        hosting.sizingOptions = [.intrinsicContentSize, .preferredContentSize]
        hosting.appearance = NSAppearance(named: appearanceName)
        hosting.frame = CGRect(origin: .zero, size: hosting.fittingSize)
        hosting.layoutSubtreeIfNeeded()

        guard let representation = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds) else {
            return false
        }
        hosting.cacheDisplay(in: hosting.bounds, to: representation)
        guard let png = representation.representation(using: .png, properties: [:]) else {
            return false
        }
        return (try? png.write(to: URL(fileURLWithPath: path))) != nil
    }

    /// Renders the editor toolbar with a fixed appearance.
    private static func renderEditorChrome(appearanceName: NSAppearance.Name, to path: String) -> Bool {
        let state = EditorState()
        state.tool = .rectangle
        state.ink = .blue
        let chrome = EditorChrome(
            state: state,
            onUndo: {}, onRedo: {}, onClear: {}, onCrop: {}, onCopy: {}, onSave: {}, onClose: {}
        )
        let hosting = NSHostingView(rootView: chrome)
        hosting.sizingOptions = [.intrinsicContentSize]
        hosting.appearance = NSAppearance(named: appearanceName)
        hosting.frame = CGRect(origin: .zero, size: hosting.fittingSize)
        hosting.layoutSubtreeIfNeeded()

        guard let representation = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds) else {
            return false
        }
        hosting.cacheDisplay(in: hosting.bounds, to: representation)
        guard let png = representation.representation(using: .png, properties: [:]) else {
            return false
        }
        return (try? png.write(to: URL(fileURLWithPath: path))) != nil
    }

    /// Renders the drawing palette offscreen with a fixed appearance.
    private static func renderPalette(appearanceName: NSAppearance.Name, to path: String) -> Bool {
        let state = EditorState()
        state.tool = .arrow
        state.ink = .green
        let hosting = NSHostingView(
            rootView: ToolbarView(state: state, onUndo: {}, onRedo: {}, onClear: {}, onDone: {})
        )
        hosting.sizingOptions = [.intrinsicContentSize]
        hosting.appearance = NSAppearance(named: appearanceName)
        hosting.frame = CGRect(origin: .zero, size: hosting.fittingSize)
        hosting.layoutSubtreeIfNeeded()

        guard let representation = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds) else {
            return false
        }
        hosting.cacheDisplay(in: hosting.bounds, to: representation)
        guard let png = representation.representation(using: .png, properties: [:]) else {
            return false
        }
        return (try? png.write(to: URL(fileURLWithPath: path))) != nil
    }

    private static func sampleSession() -> DrawingSession {
        var session = DrawingSession()
        session.begin(at: CGPoint(x: 120, y: 120), tool: .pen, ink: .red)
        for step in stride(from: 0, through: 40, by: 2) {
            session.extend(to: CGPoint(
                x: 120 + CGFloat(step) * 4,
                y: 120 + sin(CGFloat(step) / 4) * 40
            ))
        }
        session.commit()

        session.begin(at: CGPoint(x: 120, y: 260), tool: .arrow, ink: .green)
        session.extend(to: CGPoint(x: 420, y: 340))
        session.commit()

        session.begin(at: CGPoint(x: 500, y: 100), tool: .rectangle, ink: .blue)
        session.extend(to: CGPoint(x: 760, y: 220))
        session.commit()

        session.begin(at: CGPoint(x: 500, y: 280), tool: .ellipse, ink: .purple)
        session.extend(to: CGPoint(x: 700, y: 380))
        session.commit()

        session.begin(at: CGPoint(x: 120, y: 420), tool: .highlighter, ink: .yellow)
        session.extend(to: CGPoint(x: 600, y: 420))
        session.commit()

        session.begin(at: CGPoint(x: 700, y: 430), tool: .number, ink: .orange)
        session.begin(at: CGPoint(x: 760, y: 430), tool: .number, ink: .orange)

        return session
    }

    private static func renderToPNG(strokes: [Stroke]) -> Bool {
        let size = CGSize(width: 900, height: 600)
        let scale: CGFloat = 2
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(
                data: nil,
                width: Int(size.width * scale),
                height: Int(size.height * scale),
                bitsPerComponent: 8,
                bytesPerRow: 0,
                space: space,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              ) else { return false }

        context.scaleBy(x: scale, y: scale)
        context.setFillColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1))
        context.fill(CGRect(origin: .zero, size: size))

        // Overlay space is top-left origin; the bitmap context is bottom-left.
        context.translateBy(x: 0, y: size.height)
        context.scaleBy(x: 1, y: -1)

        MarkRenderer.draw(strokes: strokes, in: context)

        guard let image = context.makeImage() else { return false }
        let representation = NSBitmapImageRep(cgImage: image)
        guard let png = representation.representation(using: .png, properties: [:]) else {
            return false
        }
        return (try? png.write(to: URL(fileURLWithPath: imagePath))) != nil
    }

    // MARK: - Live blur

    /// Renders a blur mark through the view's own draw path over a synthetic
    /// screen and measures the result: inside the rectangle the pixels must be
    /// a real blur of the pattern underneath (a pixel on the sharp edge lands
    /// strictly between the two sides' values), pixels outside must be
    /// unchanged, the red band must appear at its real height (not mirrored),
    /// and without a frame the neutral fallback must show. The composition is
    /// written to `blurImagePath` for a visual orientation check.
    private static func blurRenderReport() -> [String] {
        var report: [String] = []
        let size = CGSize(width: 900, height: 600)
        let scale: CGFloat = 2
        let markRect = CGRect(x: 300, y: 200, width: 300, height: 200)

        guard let pattern = syntheticScreenPattern(size: size, scale: scale) else {
            report.append("FAIL: blur pattern could not be built")
            return report
        }

        let state = EditorState()
        state.tool = .blur
        let view = OverlayView(frame: CGRect(origin: .zero, size: size), state: state, onEscape: {})
        // The session is driven by the view, so draw the blur mark the way a
        // drag would: down, drag, up through the view's own handlers.
        for (type, point) in [
            (NSEvent.EventType.leftMouseDown, CGPoint(x: markRect.minX, y: markRect.minY)),
            (NSEvent.EventType.leftMouseDragged, CGPoint(x: markRect.midX, y: markRect.midY)),
            (NSEvent.EventType.leftMouseUp, CGPoint(x: markRect.maxX, y: markRect.maxY)),
        ] {
            guard let event = NSEvent.mouseEvent(
                with: type,
                location: point,
                modifierFlags: [],
                timestamp: ProcessInfo.processInfo.systemUptime,
                windowNumber: 0,
                context: nil,
                eventNumber: 1,
                clickCount: 1,
                pressure: 1
            ) else {
                report.append("FAIL: blur drag event could not be created")
                return report
            }
            switch type {
            case .leftMouseDown: view.mouseDown(with: event)
            case .leftMouseDragged: view.mouseDragged(with: event)
            default: view.mouseUp(with: event)
            }
        }
        guard let mark = view.session.strokes.last, mark.tool == .blur, view.hasLiveBlurMarks else {
            report.append("FAIL: blur mark was not committed (strokes=\(view.session.strokes.count))")
            return report
        }

        // Feed a known synthetic frame through the real frame source path.
        let displayID = CGDirectDisplayID(1)
        let live = LiveFrameSource(capture: { _, _ in pattern })
        live.displaysNeedingFrames = { [displayID] }
        defer { live.stop() }
        live.wake()
        RunLoop.current.run(until: Date().addingTimeInterval(0.5))
        report.append("blur frame fed=\(live.frame(for: displayID) != nil) path=\(blurImagePath)")

        view.displayID = displayID
        view.liveFrameSource = live
        guard let composed = compose(view, over: pattern, size: size, scale: scale) else {
            report.append("FAIL: blur composition failed")
            return report
        }
        let wrotePNG = writePNG(composed, to: blurImagePath)
        report.append("blur png written=\(wrotePNG)")

        // On the sharp vertical edge at the centre: a real blur mixes both
        // sides, so the value lands strictly between white (255) and black (0).
        let edge = rgb(composed, at: CGPoint(x: 450, y: 300), scale: scale)
        // Same edge, above the rectangle: outside is untouched.
        let outsideLeft = rgb(composed, at: CGPoint(x: 430, y: 100), scale: scale)
        let outsideRight = rgb(composed, at: CGPoint(x: 470, y: 100), scale: scale)
        // The red band sits at y 220-260; green betrays red mixed into white.
        // A mirrored render would put it near y 340-400 instead.
        let band = rgb(composed, at: CGPoint(x: 350, y: 240), scale: scale)
        let bandMirror = rgb(composed, at: CGPoint(x: 350, y: 370), scale: scale)

        // Profile the transition so the geometry is observable, not assumed:
        // where the sharp edge actually lands horizontally, and the band's
        // vertical profile inside the rectangle.
        let edgeProfile = stride(from: 430, through: 470, by: 5).map { x -> Int in
            rgb(composed, at: CGPoint(x: x, y: 300), scale: scale).red
        }
        report.append(
            "blur edge profile r@y=300 "
                + stride(from: 430, through: 470, by: 5).enumerated().map { index, x -> String in
                    "\(x):\(edgeProfile[index])"
                }.joined(separator: " ")
        )
        let bandProfile = stride(from: 210, through: 290, by: 10).map { y -> String in
            "\(y):\(rgb(composed, at: CGPoint(x: 350, y: y), scale: scale).green)"
        }.joined(separator: " ")
        report.append("blur band profile g@x=350 \(bandProfile)")

        // The edge pixel mixes both sides (a sharp render would read 0 or 255
        // there) and the transition spans a wide, gradual range. The blur runs
        // in CIContext's linear-light working space, so the midpoint of the
        // mix reads well above 128 in sRGB — that is the shared `BlurEffect`
        // behaviour, identical to what the capture compositor paints.
        let edgeSpread = (edgeProfile.max() ?? 0) - (edgeProfile.min() ?? 255)
        let edgeBlurred = edge.red > 30 && edge.red < 225 && edgeSpread > 100
        let outsideUntouched = outsideLeft.red >= 245 && outsideRight.red <= 10
        let orientationCorrect = band.green <= 200 && bandMirror.green >= 230
        report.append(
            "blur inside edge r=\(edge.red) expect 30<r<225 spread=\(edgeSpread) expect>100 blurred=\(edgeBlurred) | "
                + "outside r=\(outsideLeft.red)/\(outsideRight.red) expect 255/0 unchanged=\(outsideUntouched)"
        )
        report.append(
            "blur orientation band g=\(band.green) at y=240 expect<=200, mirror g=\(bandMirror.green) at y=370 expect>=200 ok=\(orientationCorrect)"
        )

        // Fallback: without a frame source, the mark must still show.
        view.liveFrameSource = nil
        guard let fallback = compose(view, over: pattern, size: size, scale: scale) else {
            report.append("FAIL: blur fallback composition failed")
            return report
        }
        let fallbackInside = rgb(fallback, at: CGPoint(x: 350, y: 240), scale: scale)
        let fallbackOutside = rgb(fallback, at: CGPoint(x: 430, y: 100), scale: scale)
        let fallbackVisible = fallbackInside.red >= 200 && fallbackInside.red <= 235
            && fallbackOutside.red >= 245
        report.append(
            "blur fallback inside r=\(fallbackInside.red) expect 200<r<235, outside r=\(fallbackOutside.red) expect 255 ok=\(fallbackVisible)"
        )

        let passed = edgeBlurred && outsideUntouched && orientationCorrect && fallbackVisible
        report.append("blur result=\(passed ? "PASS" : "FAIL")")
        return report
    }

    /// Synthetic screen for the blur check: left half white, right half black
    /// with a sharp vertical edge at the centre, and a solid red band across
    /// the top whose position proves the orientation. Built in view points.
    private static func syntheticScreenPattern(size: CGSize, scale: CGFloat) -> CGImage? {
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(
                data: nil,
                width: Int(size.width * scale),
                height: Int(size.height * scale),
                bitsPerComponent: 8,
                bytesPerRow: 0,
                space: space,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              ) else { return nil }

        context.scaleBy(x: scale, y: scale)
        context.translateBy(x: 0, y: size.height)
        context.scaleBy(x: 1, y: -1)

        context.setFillColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1))
        context.fill(CGRect(origin: .zero, size: size))
        context.setFillColor(CGColor(gray: 0, alpha: 1))
        context.fill(CGRect(x: size.width / 2, y: 0, width: size.width / 2, height: size.height))
        context.setFillColor(CGColor(srgbRed: 1, green: 0, blue: 0, alpha: 1))
        context.fill(CGRect(x: 0, y: 220, width: size.width, height: 40))
        return context.makeImage()
    }

    /// Renders the view with the app's own draw path onto the background, so
    /// the measured pixels are what a user would see on screen.
    private static func compose(_ view: NSView, over background: CGImage, size: CGSize, scale: CGFloat) -> CGImage? {
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(
                data: nil,
                width: Int(size.width * scale),
                height: Int(size.height * scale),
                bitsPerComponent: 8,
                bytesPerRow: 0,
                space: space,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              ) else { return nil }

        context.draw(
            background,
            in: CGRect(x: 0, y: 0, width: size.width * scale, height: size.height * scale)
        )
        guard let representation = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return nil }
        view.cacheDisplay(in: view.bounds, to: representation)
        guard let overlay = representation.cgImage else { return nil }
        context.draw(
            overlay,
            in: CGRect(x: 0, y: 0, width: size.width * scale, height: size.height * scale)
        )
        return context.makeImage()
    }

    /// RGB (0-255 each) of the pixel at a view point, sampling from the top.
    private static func rgb(_ image: CGImage, at point: CGPoint, scale: CGFloat) -> (red: Int, green: Int, blue: Int) {
        let representation = NSBitmapImageRep(cgImage: image)
        guard let colour = representation.colorAt(
            x: Int(point.x * scale),
            y: Int(point.y * scale)
        ) else { return (-1, -1, -1) }
        var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
        let resolved = colour.usingColorSpace(.deviceRGB) ?? colour
        resolved.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        return (Int((red * 255).rounded()), Int((green * 255).rounded()), Int((blue * 255).rounded()))
    }

    private static func writePNG(_ image: CGImage, to path: String) -> Bool {
        let representation = NSBitmapImageRep(cgImage: image)
        guard let png = representation.representation(using: .png, properties: [:]) else {
            return false
        }
        return (try? png.write(to: URL(fileURLWithPath: path))) != nil
    }

    private static func finish(_ report: [String], code: Int32) -> Int32 {
        let text = report.joined(separator: "\n") + "\n"
        try? text.write(toFile: reportPath, atomically: true, encoding: .utf8)
        FileHandle.standardOutput.write(Data(text.utf8))
        NSLog("Stare: selftest\n%@", text)
        return code
    }
}
