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

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .crosshair)
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
        // apply to the display being drawn on. This does not activate the app.
        window?.makeKey()
        let point = convert(event.locationInWindow, from: nil)
        session.begin(at: point, tool: state.tool, ink: state.ink)
        invalidateActive(previousBounds: nil)
    }

    override func mouseDragged(with event: NSEvent) {
        let previousBounds = session.active?.bounds
        session.extend(to: convert(event.locationInWindow, from: nil))
        invalidateActive(previousBounds: previousBounds)
    }

    override func mouseUp(with event: NSEvent) {
        let previousBounds = session.active?.bounds
        session.extend(to: convert(event.locationInWindow, from: nil))
        session.commit()
        if let previousBounds {
            setNeedsDisplay(previousBounds)
        } else {
            needsDisplay = true
        }
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
                return
            }
            if let digit = character.wholeNumberValue, let ink = Ink.ink(forNumber: digit) {
                state.ink = ink
                return
            }
        }

        super.keyDown(with: event)
    }

    // MARK: - Drawing

    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        context.setLineCap(.round)
        context.setLineJoin(.round)

        for stroke in session.visibleStrokes where stroke.bounds.intersects(dirtyRect) {
            render(stroke, in: context)
        }
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
