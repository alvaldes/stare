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

        return finish(report, code: 0)
    }

    private static func displayID(of screen: NSScreen) -> CGDirectDisplayID? {
        let key = NSDeviceDescriptionKey("NSScreenNumber")
        guard let number = screen.deviceDescription[key] as? NSNumber else { return nil }
        return CGDirectDisplayID(number.uint32Value)
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
            onUndo: {}, onClear: {}, onCrop: {}, onCopy: {}, onSave: {}, onClose: {}
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
            rootView: ToolbarView(state: state, onUndo: {}, onClear: {}, onDone: {})
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
