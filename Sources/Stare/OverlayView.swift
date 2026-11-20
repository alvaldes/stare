import AppKit
import StareCore

/// Draws one display's marks and turns mouse and keyboard input into a
/// `DrawingSession`. Coordinates are top-left origin, local to the display.
final class OverlayView: NSView {
    let state: EditorState
    private(set) var session = DrawingSession()
    var onEscape: (() -> Void)?

    init(frame: NSRect, state: EditorState, onEscape: @escaping () -> Void) {
        self.state = state
        self.onEscape = onEscape
        super.init(frame: frame)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("OverlayView is created in code only")
    }

    // Top-left origin, so stroke points map directly onto screen and capture
    // coordinates without a flip.
    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    /// The panel must take key status on click so tool keys and Escape work
    /// while the app itself never shows a window or a Dock icon.
    override var needsPanelToBecomeKey: Bool { true }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .crosshair)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for area in trackingAreas { removeTrackingArea(area) }
        addTrackingArea(
            NSTrackingArea(
                rect: bounds,
                options: [.cursorUpdate, .activeAlways, .inVisibleRect, .mouseEnteredAndExited],
                owner: self,
                userInfo: nil
            )
        )
    }

    /// `.activeAlways` keeps the crosshair working even when the app is not the
    /// active one, which cursor rectangles alone do not allow.
    override func cursorUpdate(with event: NSEvent) {
        Diag.log("cursorUpdate")
        NSCursor.crosshair.set()
    }

    override func mouseEntered(with event: NSEvent) {
        NSCursor.crosshair.set()
    }

    // MARK: - Session

    var isEmpty: Bool { session.isEmpty }

    func clear() {
        session.clear()
        needsDisplay = true
    }

    func undo() {
        guard session.undo() else { return }
        needsDisplay = true
    }

    // MARK: - Mouse

    override func mouseDown(with event: NSEvent) {
        // The panel under the pointer owns the keyboard so tool keys always
        // apply to the display being drawn on.
        window?.makeKey()
        window?.makeFirstResponder(self)
        let point = convert(event.locationInWindow, from: nil)
        Diag.log("mouseDown \(Int(point.x)),\(Int(point.y)) tool=\(state.tool.rawValue)")
        session.begin(at: point, tool: state.tool, ink: state.ink)
        invalidateActive(previousBounds: nil)
    }

    override func mouseDragged(with event: NSEvent) {
        let previousBounds = session.active?.bounds
        session.extend(to: convert(event.locationInWindow, from: nil))
        invalidateActive(previousBounds: previousBounds)
    }

    override func mouseUp(with event: NSEvent) {
        session.extend(to: convert(event.locationInWindow, from: nil))
        session.commit()
        Diag.log("commit strokes=\(session.strokes.count)")
        // Full redraw: the first mark also removes the armed frame at the edges.
        needsDisplay = true
    }

    private func invalidateActive(previousBounds: CGRect?) {
        guard let bounds = session.active?.bounds else {
            needsDisplay = true
            return
        }
        setNeedsDisplay(previousBounds?.union(bounds) ?? bounds)
    }

    // MARK: - Keyboard

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { // Escape
            onEscape?()
            return
        }

        let characters = event.charactersIgnoringModifiers ?? ""

        if event.modifierFlags.contains(.command) {
            if characters.lowercased() == "z" {
                undo()
                return
            }
            super.keyDown(with: event)
            return
        }

        if let character = characters.first {
            if let tool = ToolShortcut.tool(for: character) {
                state.tool = tool
                Diag.log("tool=\(tool.rawValue)")
                return
            }
            if let digit = character.wholeNumberValue, let ink = Ink.ink(forNumber: digit) {
                state.ink = ink
                return
            }
        }

        super.keyDown(with: event)
    }

    // MARK: - Drawing mode hint

    private var hintUntil: Date?

    /// Drawing mode is an invisible layer by design, so the first moment of the
    /// session needs a visible signal: a pill that names the way out.
    func showIntroHint() {
        hintUntil = Date().addingTimeInterval(2.2)
        needsDisplay = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.2) { [weak self] in
            self?.hintUntil = nil
            self?.needsDisplay = true
        }
    }

    private func drawHint() {
        guard let until = hintUntil, Date() < until else { return }
        guard let context = NSGraphicsContext.current?.cgContext else { return }

        let text = "Drawing · esc to clear · \(HotkeyDefaults.displayName) to exit" as NSString
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 13, weight: .medium),
            .foregroundColor: NSColor.white,
        ]
        let textSize = text.size(withAttributes: attributes)
        let padding = CGSize(width: 18, height: 10)
        let pill = CGRect(
            x: (bounds.midX - (textSize.width + padding.width * 2) / 2).rounded(),
            y: 28,
            width: textSize.width + padding.width * 2,
            height: textSize.height + padding.height * 2
        )

        context.setFillColor(CGColor(gray: 0, alpha: 0.74))
        context.addPath(
            CGPath(
                roundedRect: pill,
                cornerWidth: pill.height / 2,
                cornerHeight: pill.height / 2,
                transform: nil
            )
        )
        context.fillPath()

        text.draw(
            at: CGPoint(x: pill.minX + padding.width, y: pill.minY + padding.height),
            withAttributes: attributes
        )
    }

    // MARK: - Drawing

    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        context.setLineCap(.round)
        context.setLineJoin(.round)

        for stroke in session.visibleStrokes where stroke.bounds.intersects(dirtyRect) {
            render(stroke, in: context)
        }

        drawArmedFrame(in: context)
        drawHint()
    }

    /// While the layer is armed and empty, a thin frame in the current ink shows
    /// which displays are live. It disappears with the first mark.
    private func drawArmedFrame(in context: CGContext) {
        guard session.isEmpty else { return }
        let rect = bounds.insetBy(dx: 3, dy: 3)
        context.setStrokeColor(state.ink.cgColor(alpha: 0.45))
        context.setLineWidth(3)
        context.addPath(
            CGPath(
                roundedRect: rect,
                cornerWidth: 10,
                cornerHeight: 10,
                transform: nil
            )
        )
        context.strokePath()
    }

    private func render(_ stroke: Stroke, in context: CGContext) {
        let path = PathBuilder.path(for: stroke)

        if stroke.tool == .number {
            context.setFillColor(stroke.ink.cgColor())
            context.addPath(path)
            context.fillPath()

            // A faint ring keeps a badge readable on any background.
            context.setStrokeColor(CGColor(gray: 0, alpha: 0.18))
            context.setLineWidth(1)
            context.addPath(path)
            context.strokePath()

            drawStepNumber(stroke)
            return
        }

        context.setStrokeColor(stroke.ink.cgColor(alpha: stroke.opacity))
        context.setLineWidth(stroke.lineWidth)
        context.addPath(path)
        context.strokePath()
    }

    private func drawStepNumber(_ stroke: Stroke) {
        guard let number = stroke.stepNumber, let center = stroke.points.first else { return }

        let text = "\(number)" as NSString
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 15, weight: .semibold),
            .foregroundColor: Self.numberColour(for: stroke.ink),
        ]
        let size = text.size(withAttributes: attributes)
        text.draw(
            at: CGPoint(x: center.x - size.width / 2, y: center.y - size.height / 2),
            withAttributes: attributes
        )
    }

    static func numberColour(for ink: Ink) -> NSColor {
        switch ink {
        case .yellow, .white: .black
        default: .white
        }
    }
}
