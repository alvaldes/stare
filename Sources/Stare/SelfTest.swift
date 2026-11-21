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

        // Settings (T6 slice 2): the sidebar + panes shell renders in both
        // system appearances, one PNG per pane, and its window is resizable
        // and clearly wider than the old fixed 420-pt form.
        report.append(contentsOf: MainActor.assumeIsolated { settingsReport() })

        // Marker styles (T7/S5): every pointer preset rendered in light and
        // dark through the same preview view the Settings pane uses.
        report.append(contentsOf: MainActor.assumeIsolated { markerStylesReport() })

        // Onboarding (T5/S1–S3): the guide renders in both appearances, its
        // window can become key from an .accessory app, has a real frame and
        // reports the permission state it saw. The finish closure records the
        // close, so the S3 contract (every close marks it seen) is observed.
        report.append(contentsOf: MainActor.assumeIsolated { onboardingReport() })

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

    // MARK: - Marker styles (T7/S5)

    /// Renders each of the five pointer presets in both system appearances
    /// through the same preview view the Settings pane shows (one PNG per
    /// preset per appearance), and checks the preview's own transparent
    /// bitmap against the pulse report's extent measurement so a render is
    /// proven to have painted real pixels, not an empty tile.
    @MainActor
    private static func markerStylesReport() -> [String] {
        var report: [String] = []
        var written = 0
        var painted = 0
        let total = PointerStylePreset.allCases.count * 2
        for preset in PointerStylePreset.allCases {
            var style = PointerStyle.standard
            style.preset = preset
            // The preview is proven to paint its highlight on a transparent
            // bitmap before any hosting render: the extent must be non-empty
            // for every preset.
            let extent = PointerHighlightPreview
                .cgImage(for: style, ink: .red, scale: 1)
                .flatMap(opaqueExtentPixels)
            if let extent, extent.width > 20, extent.height > 20 {
                painted += 1
            }
            for (name, appearance) in [("light", NSAppearance.Name.aqua), ("dark", .darkAqua)] {
                let path = "/tmp/stare-marker-\(preset.rawValue)-\(name).png"
                if renderMarkerPreview(style: style, appearanceName: appearance, to: path) {
                    written += 1
                }
            }
        }
        let passed = written == total && painted == PointerStylePreset.allCases.count
        report.append(
            "marker styles result=\(passed ? "PASS" : "FAIL") presets=\(PointerStylePreset.allCases.count) "
                + "previewPainted=\(painted)/\(PointerStylePreset.allCases.count) pngs=\(written)/\(total) "
                + "path=/tmp/stare-marker-<preset>-<light|dark>.png"
        )
        return report
    }

    /// Renders one marker preview through the real hosting path: a real
    /// borderless window, the pattern the settings render uses, because a
    /// windowless hosting view lays content out shifted.
    @MainActor
    private static func renderMarkerPreview(
        style: StareCore.PointerStyle,
        appearanceName: NSAppearance.Name,
        to path: String
    ) -> Bool {
        let hosting = NSHostingView(rootView: PointerPreviewView(style: style, ink: .red))
        hosting.sizingOptions = [.intrinsicContentSize]
        hosting.appearance = NSAppearance(named: appearanceName)
        hosting.frame = CGRect(origin: .zero, size: hosting.fittingSize)
        hosting.layoutSubtreeIfNeeded()

        let window = NSWindow(
            contentRect: CGRect(origin: .zero, size: hosting.bounds.size),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.appearance = NSAppearance(named: appearanceName)
        window.contentView = hosting
        window.orderFrontRegardless()
        RunLoop.current.run(until: Date().addingTimeInterval(0.15))
        defer { window.orderOut(nil) }

        guard let representation = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds) else {
            return false
        }
        hosting.cacheDisplay(in: hosting.bounds, to: representation)
        guard let image = representation.cgImage else { return false }
        return writePNG(image, to: path)
    }

    /// Renders the onboarding guide with a fixed appearance and the real
    /// permission model behind it, so the render shows the state this machine
    /// actually reports.
    @MainActor
    private static func renderOnboarding(appearanceName: NSAppearance.Name, to path: String) -> Bool {
        let model = OnboardingModel(
            permission: ScreenRecordingPermission(
                client: SystemScreenRecordingClient(captureService: CaptureService())
            )
        )
        // The render shows the state this machine actually reports, like the
        // live guide does.
        model.refresh()
        let hosting = NSHostingView(rootView: OnboardingView(
            model: model,
            onContinue: {},
            onRestart: {},
            onNotNow: {}
        ))
        hosting.appearance = NSAppearance(named: appearanceName)
        hosting.frame = CGRect(origin: .zero, size: CGSize(width: 460, height: 430))
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

    /// Opens the guide through its real controller: renders both appearances
    /// offscreen, then asserts the window can become key, has a non-zero
    /// frame, reports a permission state, and that closing it reports the
    /// finish exactly once (S3: any close marks the guide as seen).
    @MainActor
    private static func onboardingReport() -> [String] {
        var report: [String] = []

        for (name, appearance) in [("light", NSAppearance.Name.aqua), ("dark", .darkAqua)] {
            let rendered = renderOnboarding(appearanceName: appearance, to: "/tmp/stare-onboarding-\(name).png")
            report.append("onboarding \(name) rendered=\(rendered) png=/tmp/stare-onboarding-\(name).png")
        }

        var finishes: [Bool] = []
        let controller = OnboardingWindowController(
            permission: ScreenRecordingPermission(
                client: SystemScreenRecordingClient(captureService: CaptureService())
            ),
            onDismissOverlay: {},
            onFinish: { continueToSettings in finishes.append(continueToSettings) }
        )
        controller.show()
        RunLoop.current.run(until: Date().addingTimeInterval(0.4))

        var windowOk = false
        var frameOk = false
        if let window = controller.window {
            windowOk = window.isVisible && window.canBecomeKey
            frameOk = window.frame.width > 0 && window.frame.height > 0
            report.append(
                "onboarding window frame=\(window.frame) visible=\(window.isVisible) "
                    + "canBecomeKey=\(window.canBecomeKey) isKey=\(window.isKeyWindow) "
                    + "level=\(window.level.rawValue) state=\(controller.access)"
            )
            window.close()
        } else {
            report.append("FAIL: onboarding window not created")
        }
        RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        report.append(
            "onboarding close reported finishes=\(finishes.map(String.init).joined(separator: ", ")) expect false once"
        )

        let passed = windowOk && frameOk && finishes == [false]
        report.append("onboarding result=\(passed ? "PASS" : "FAIL")")
        return report
    }

    /// T6 slice 2: renders each Settings pane in both system appearances (one
    /// PNG per pane per appearance) and opens the real settings window to
    /// assert the shell: visible, key, resizable and wider than the old 420-pt
    /// form. Runs detached from the user's real preferences — the harness
    /// model uses an in-memory store, so no pane write can touch defaults.
    @MainActor
    private static func settingsReport() -> [String] {
        var report: [String] = []
        let model = PreferencesModel(store: SelfTestPreferenceStore())
        let controller = SettingsWindowController(
            model: model,
            permission: ScreenRecordingPermission(
                client: SystemScreenRecordingClient(captureService: CaptureService())
            )
        )
        var allPanesRendered = true
        let probe = PermissionProbe(
            permission: ScreenRecordingPermission(
                client: SystemScreenRecordingClient(captureService: CaptureService())
            )
        )
        for area in SettingsArea.allCases {
            for (name, appearance) in [("light", NSAppearance.Name.aqua), ("dark", .darkAqua)] {
                let rendered = renderSettings(
                    area: area,
                    appearanceName: appearance,
                    model: model,
                    permission: probe,
                    to: "/tmp/stare-settings-\(area.rawValue)-\(name).png"
                )
                allPanesRendered = allPanesRendered && rendered
            }
        }
        report.append(
            "settings panes result=\(allPanesRendered ? "PASS" : "FAIL") areas=\(SettingsArea.allCases.count)"
        )

        // A window measured before layout used to come out zero-sized: created,
        // "opened", and never seen.
        controller.show()
        RunLoop.current.run(until: Date().addingTimeInterval(0.4))
        if let window = NSApp.windows.first(where: { $0.title == "Stare Settings" }) {
            let resizable = window.styleMask.contains(.resizable)
            let contentWidth = window.contentView?.bounds.width ?? 0
            // The shell assertion is documented behaviour: visible, resizable,
            // and wider than the old fixed 420-pt form. Keyness is reported but
            // not asserted — the same activation pattern the guide uses is
            // asserted on the guide's own window contract, and a headless run
            // cannot guarantee key state for every window.
            let windowOk = window.isVisible && resizable && contentWidth > 420
            report.append(
                "settings window frame=\(window.frame) visible=\(window.isVisible) key=\(window.isKeyWindow) "
                    + "resizable=\(resizable) contentWidth=\(Int(contentWidth))"
            )
            report.append("settings window result=\(windowOk ? "PASS" : "FAIL")")
            window.close()
        } else {
            report.append("FAIL: settings window not created")
        }
        return report
    }

    /// Renders one Settings pane in a fixed appearance. The pane content
    /// (header + cards) is hosted at fixed pane width inside a real on-screen
    /// borderless window — the pattern the board section uses — because a
    /// windowless hosting view lays text out shifted, which drew pane headers
    /// clipped outside the image.
    @MainActor
    private static func renderSettings(
        area: SettingsArea,
        appearanceName: NSAppearance.Name,
        model: PreferencesModel,
        permission: PermissionProbe,
        to path: String
    ) -> Bool {
        let size = CGSize(width: 640, height: 560)
        let hosting = NSHostingView(rootView: SettingsView.pane(
            for: area,
            model: model,
            permission: permission
        )
        // Fixture only: pin the pane to the top like the shell's ScrollView
        // does, and give the render the window background the pane area gets
        // behind the material. The app view itself stays unstyled.
        .frame(width: size.width, height: size.height, alignment: .topLeading)
        .background(Color(nsColor: .windowBackgroundColor)))
        hosting.sizingOptions = []
        hosting.appearance = NSAppearance(named: appearanceName)
        hosting.frame = CGRect(origin: .zero, size: size)

        let window = NSWindow(
            contentRect: CGRect(origin: .zero, size: size),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.backgroundColor = .windowBackgroundColor
        window.contentView = hosting
        window.appearance = NSAppearance(named: appearanceName)
        window.orderFrontRegardless()
        RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        defer { window.orderOut(nil) }

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

    /// In-memory `PreferenceStore` for the selftest harness, which must not
    /// read or write the user's real preferences (same seam the unit tests use).
    private final class SelfTestPreferenceStore: PreferenceStore {
        private var values: [String: Any] = [:]

        func object(forKey key: String) -> Any? {
            values[key]
        }

        func set(_ value: Any?, forKey key: String) {
            values[key] = value
        }
    }
}
