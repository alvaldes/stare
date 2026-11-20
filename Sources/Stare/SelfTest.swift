import AppKit
import SwiftUI
import StareCore

/// `--selftest` gathers the facts that a headless unit test cannot: real screen
/// and window geometry, whether a panel is on screen and whether the render path
/// produces pixels. It writes a report and a PNG and exits.
enum SelfTest {
    static let reportPath = "/tmp/stare-selftest.txt"
    static let imagePath = "/tmp/stare-selftest.png"

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

        panel.orderOut(nil)

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

    private static func finish(_ report: [String], code: Int32) -> Int32 {
        let text = report.joined(separator: "\n") + "\n"
        try? text.write(toFile: reportPath, atomically: true, encoding: .utf8)
        FileHandle.standardOutput.write(Data(text.utf8))
        NSLog("Stare: selftest\n%@", text)
        return code
    }
}
