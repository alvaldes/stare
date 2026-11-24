import AppKit
import StareCore

/// The OCR selection surface (T5/S7): its own lightweight window — a drag
/// over the screen with nothing else attached — opened by the fixed ⌥⇧O
/// global shortcut. It is deliberately **not** the drawing overlay rewired:
/// it owns no session, no toolbar and no marks, it never touches overlay
/// state, and it lives and dies with one gesture.
///
/// It appears on exactly one display — the one the pointer is on — and
/// never on another: the frame is set to that display's own frame (injected,
/// so the choice is pure and testable), and no window is opened when no
/// display holds the pointer.
@MainActor
final class TextSelectionWindow: NSPanel {
    // Key-capable on purpose: the surface is a nonactivating panel, so
    // becoming key never activates the app — and that key focus is how
    // Escape reaches an accessory app the system never makes frontmost,
    // with no new permission of any kind (S9).
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    /// Delivers the finished selection in screen coordinates.
    var onSelected: ((CGRect) -> Void)?
    /// Delivers every ending that was not a selection: Escape, a stray click.
    var onCancelled: (() -> Void)?

    /// Whether the gesture is over. A finished window answers no further
    /// input and no further callbacks.
    private(set) var isDismissed = false

    /// Chooses the display the pointer is on, purely: the first frame that
    /// contains the pointer's global position. Between displays — the dead
    /// corner — or with no display at all, nil, and the caller refuses the
    /// gesture instead of guessing where to open.
    static func screenFrame(containing point: CGPoint, in frames: [CGRect]) -> CGRect? {
        frames.first { $0.contains(point) }
    }

    init(pointerFrame: CGRect) {
        super.init(
            contentRect: pointerFrame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        level = .floating
        collectionBehavior = [.fullScreenAuxiliary, .stationary, .ignoresCycle]
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        becomesKeyOnlyIfNeeded = true
        contentView = TextSelectionSurfaceView(frame: CGRect(origin: .zero, size: pointerFrame.size))
        surfaceView?.onFinished = { [weak self] start, end, shift in
            self?.finishSelection(from: start, to: end, square: shift)
        }
        surfaceView?.onDragStarted = { [weak self] in
            self?.handleDragStarted()
        }
        Diag.log("text recognition selection armed inviting")
    }

    /// The surface's moment in the pure state machine (`StareCore`), mirrored
    /// onto the painter: inviting shows the veil and the instruction, dragging
    /// the rectangle, closing nothing.
    private(set) var phase: TextSelectionSurfacePhase = .inviting {
        didSet {
            surfaceView?.phase = phase
            surfaceView?.needsDisplay = true
        }
    }
    /// The surface's own machine: one gesture, one machine — every decision
    /// about how the gesture lives and dies is the tested one in `StareCore`.
    private var machine = TextSelectionSurfaceMachine(phase: .inviting)

    /// Whether the surface takes mouse input: it lives from the press until
    /// its teardown, and a click inside it while inviting is a drag's start.
    var acceptsGestures: Bool { phase == .inviting || phase == .dragging }

    /// Test helper with production parity: the drag surface the window owns.
    var surfaceView: TextSelectionSurfaceView? { contentView as? TextSelectionSurfaceView }

    /// Escape ends the gesture without selecting or recognising anything —
    /// the clipboard is untouched. Consumed while the gesture lives;
    /// afterwards the gesture is already over and this answers false.
    func handleEscapeKey() -> Bool {
        guard case .close(cancelled: true) = machine.send(.escapePressed) else { return false }
        finish(cancelled: true)
        return true
    }

    /// A second ⇧⌥O press while the surface is up: a visible cancel — the
    /// machine turns the press into a close, and the surface goes away in
    /// front of the user instead of leaving the shortcut silently dead.
    /// The clipboard is untouched.
    func cancelBySecondPress() {
        guard case .close(cancelled: true) = machine.send(.hotkeyPressed) else { return }
        finish(cancelled: true)
    }

    /// The last-resort dismissal: the surface sat through its whole idle
    /// budget (only before a drag starts — the machine refuses it mid-drag)
    /// and closes itself, so a dismissal channel the system cannot see can
    /// never strand the user inside the gesture.
    func handleIdleTimeout() {
        guard case .close(cancelled: true) = machine.send(.idleTimedOut) else { return }
        Diag.log("text recognition selection dismissed by idle timeout")
        finish(cancelled: true)
    }

    /// Closes without delivering any callback — the test teardown's way, and
    /// the flow's way when the gesture continues elsewhere.
    func closeWithoutCallbacks() {
        isDismissed = true
        close()
    }

    private func finishSelection(from start: CGPoint, to end: CGPoint, square: Bool) {
        guard !isDismissed else { return }
        // The same geometry the area drag trusts, in the surface's window
        // space, then lifted into screen coordinates — where the owner
        // reads pixels.
        let local = AreaSelectionGeometry.rect(
            from: start,
            to: end,
            square: square,
            bounds: CGRect(origin: .zero, size: frame.size)
        )
        // A drag below the 4×4 stray-click minimum is not a selection: the
        // gesture ends cancelled — no capture, no recognition, clipboard
        // untouched — exactly what the capture plan refuses for it.
        guard AreaSelectionGeometry.isCaptureWorthy(local) else {
            guard case .close(cancelled: true) = machine.send(.clickDismissed) else { return }
            finish(cancelled: true)
            return
        }
        guard case .close(cancelled: false) = machine.send(.selectionCommitted) else { return }
        let selected = local.offsetBy(dx: frame.minX, dy: frame.minY)
        finish(cancelled: false, selected: selected)
    }

    /// The drag's first mouse press: the machine moves the surface from
    /// inviting into dragging, and the instruction hands the stage over to
    /// the rectangle.
    private func handleDragStarted() {
        guard case .beganDrag = machine.send(.dragStarted) else { return }
        phase = machine.phase
    }

    /// Keys reach this panel while it is key (the app never activates):
    /// Escape is the dismissal, everything else stays quietly with the
    /// surface instead of beeping through the responder chain mid-gesture.
    override func keyDown(with event: NSEvent) {
        guard acceptsGestures else { return super.keyDown(with: event) }
        if event.keyCode == 53 {
            _ = handleEscapeKey()
        }
    }

    private func finish(cancelled: Bool, selected: CGRect? = nil) {
        guard !isDismissed else { return }
        isDismissed = true
        phase = machine.phase
        close()
        Diag.log("text recognition selection finished cancelled=\(cancelled)")
        if let selected {
            onSelected?(selected)
        } else {
            onCancelled?()
        }
    }
}

/// The drag surface: crosshair start, the rectangle following the pointer —
/// reusing the pure area-drag geometry — and nothing else. The ⇧ modifier
/// forces a square exactly like the capture area drag does.
final class TextSelectionSurfaceView: NSView {
    var onFinished: ((_ start: CGPoint, _ end: CGPoint, _ square: Bool) -> Void)?
    /// The surface's moment, pushed by its window's machine.
    var phase: TextSelectionSurfacePhase = .inviting {
        didSet { needsDisplay = true }
    }
    var onDragStarted: (() -> Void)?

    private var dragStart: CGPoint?
    private var dragCurrent: CGPoint?
    private var cursorPushed = false

    override init(frame: NSRect) {
        super.init(frame: frame)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("TextSelectionSurfaceView is created in code only")
    }

    override func mouseDown(with event: NSEvent) {
        guard phase == .inviting else { return }
        forceCursor()
        onDragStarted?()
        dragStart = convert(event.locationInWindow, from: nil)
        dragCurrent = dragStart
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        guard dragStart != nil, phase == .dragging else { return }
        dragCurrent = convert(event.locationInWindow, from: nil)
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        guard let start = dragStart, phase == .dragging else { return }
        dragStart = nil
        onFinished?(start, convert(event.locationInWindow, from: nil), event.modifierFlags.contains(.shift))
    }

    override func draw(_ dirtyRect: NSRect) {
        switch phase {
        case .inviting:
            // The press's first visible moment: a dim veil over the display,
            // the crosshair cursor already pushed, and a short instruction —
            // so a gesture nobody was looking for can be found.
            NSColor.black.withAlphaComponent(0.25).setFill()
            bounds.fill()
            drawInstruction()
        case .dragging:
            guard let start = dragStart, let current = dragCurrent else { return }
            let selection = AreaSelectionGeometry.rect(from: start, to: current, square: false, bounds: bounds)
            // A quiet frame around what is being chosen, nothing more: the OCR
            // surface never paints marks or a toolbar, and never pretends to
            // be the drawing overlay.
            NSColor.black.withAlphaComponent(0.12).setFill()
            selection.fill()
            NSColor.white.withAlphaComponent(0.9).setStroke()
            let border = NSBezierPath(rect: selection)
            border.lineWidth = 1.5
            border.stroke()
        case .idle, .closing:
            // After dismissal the surface paints nothing: the selection is
            // gone.
            return
        }
    }

    /// The instruction, in the same dark pill the capture paths' hint uses.
    private func drawInstruction() {
        let message = TextRecognitionSurfaceCopy.instruction(for: phase)
        guard !message.isEmpty else { return }
        let font = NSFont.systemFont(ofSize: 13)
        let attributes: [NSAttributedString.Key: Any] = [.font: font]
        let textSize = (message as NSString).size(withAttributes: attributes)
        let pill = CGRect(
            x: bounds.midX - (textSize.width + 48) / 2,
            y: bounds.midY - 18,
            width: textSize.width + 48,
            height: 36)
        NSColor.black.withAlphaComponent(0.85).setFill()
        NSBezierPath(roundedRect: pill, xRadius: 10, yRadius: 10).fill()
        var textAttributes = attributes
        textAttributes[.foregroundColor] = NSColor.white
        (message as NSString).draw(
            at: CGPoint(x: pill.midX - textSize.width / 2, y: pill.midY - textSize.height / 2),
            withAttributes: textAttributes)
    }

    /// The crosshair is the selection gesture's cursor; one push per drag,
    /// popped when the window finishes, so the pointer never keeps the
    /// crosshair after the surface is gone.
    func forceCursor() {
        guard !cursorPushed else { return }
        NSCursor.crosshair.push()
        cursorPushed = true
    }

    func releaseCursor() {
        guard cursorPushed else { return }
        NSCursor.pop()
        cursorPushed = false
    }
}

/// The one-line answer surface of the gesture (T5/S7): a missing Screen
/// Recording grant, a selection with nothing recognisable in it, or a failed
/// recognition are all *said* — on a small hint centred on the display the
/// user is working on — instead of copying an empty string over the user's
/// clipboard. It borrows the overlay's brevity and copy, never its session:
/// it is its own borderless window that closes itself after three and a half
/// seconds.
@MainActor
final class TextRecognitionHintWindow: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    private(set) var isDismissed = false
    var onDismissed: (() -> Void)?

    init(screenFrame: CGRect, message: String, duration: TimeInterval = 3.5) {
        let font = NSFont.systemFont(ofSize: 13)
        let textWidth = (message as NSString).size(
            withAttributes: [.font: font]
        ).width
        let width = min(
            screenFrame.width * 0.8,
            textWidth + 48
        )
        let height: CGFloat = 36
        let placement = CGRect(
            x: screenFrame.midX - width / 2,
            y: screenFrame.midY - height / 2,
            width: width,
            height: height
        )
        super.init(
            contentRect: placement,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        level = .floating
        collectionBehavior = [.fullScreenAuxiliary, .stationary, .ignoresCycle]
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        becomesKeyOnlyIfNeeded = true
        contentView = TextRecognitionHintView(frame: CGRect(origin: .zero, size: placement.size), message: message)
        DispatchQueue.main.asyncAfter(deadline: .now() + duration) { [weak self] in
            self?.closeSelf()
        }
        Diag.log("text recognition hint shown")
    }

    func closeSelf() {
        guard !isDismissed else { return }
        isDismissed = true
        let notified = onDismissed
        onDismissed = nil
        close()
        notified?()
    }
}

/// The hint's surface: a dark rounded pill with the one-line message.
final class TextRecognitionHintView: NSView {
    private let message: String

    init(frame: NSRect, message: String) {
        self.message = message
        super.init(frame: frame)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("TextRecognitionHintView is created in code only")
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.black.withAlphaComponent(0.85).setFill()
        NSBezierPath(roundedRect: bounds, xRadius: 10, yRadius: 10).fill()
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 13),
            .foregroundColor: NSColor.white,
        ]
        let size = (message as NSString).size(withAttributes: attributes)
        (message as NSString).draw(
            at: CGPoint(x: bounds.midX - size.width / 2, y: bounds.midY - size.height / 2),
            withAttributes: attributes
        )
    }
}

/// The gesture's owner (T5/S7): one ⌥⇧O press, one selection surface, one
/// recognition, one clipboard copy — everything else the user did before and
/// after is untouched. It works with no drawing session at all: no overlay is
/// opened, and an overlay that happens to be open keeps exactly the state it
/// had.
@MainActor
final class TextRecognitionFlow {
    private let client: TextRecognitionClient
    private var window: TextSelectionWindow?
    private var hintWindow: TextRecognitionHintWindow?
    private var escapeMonitor: Any?
    private var cursorPushed = false
    private var idleDismiss: DispatchWorkItem?

    init(client: TextRecognitionClient) {
        self.client = client
    }

    /// Arms the gesture. Every path says something: no display under the
    /// pointer and a missing permission are said in the pill (a pill that is
    /// still up is replaced, not waited out), and a second press while one
    /// surface is already open cancels it in front of the user — the
    /// shortcut is never left silently dead behind an open surface.
    func begin() {
        if let window {
            window.cancelBySecondPress()
            return
        }
        guard let pointerFrame = TextSelectionWindow.screenFrame(
            containing: NSEvent.mouseLocation,
            in: NSScreen.screens.map(\.frame)
        ) else {
            Diag.log("text recognition: pointer on no display, said in the pill")
            showHint(.noDisplay, on: NSScreen.main?.frame ?? .zero)
            return
        }
        // The preflight decides the gesture's whole shape: without the
        // permission there is no selection surface and no capture — the user
        // gets the app's usual copy pointing at System Settings, never a
        // system prompt mid-gesture (S9).
        guard client.captureService.hasPermission else {
            Diag.log("text recognition: screen recording missing, reporting instead of prompting")
            showHint(.permissionMissing, on: pointerFrame)
            return
        }

        // Escape leaves the gesture without selecting anything. A local
        // monitor scope-limited to the gesture's lifetime: the drawing
        // overlay's keys are untouched before and after, and no other key is
        // swallowed.
        escapeMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, event.keyCode == 53, self.window != nil else { return event }
            _ = self.window?.handleEscapeKey()
            return nil
        }
        let window = TextSelectionWindow(pointerFrame: pointerFrame)
        window.onSelected = { [weak self] selected in
            self?.recognise(selected, on: pointerFrame)
        }
        window.onCancelled = { [weak self] in
            self?.closeSurface()
        }
        self.window = window
        NSCursor.crosshair.push()
        cursorPushed = true
        window.orderFrontRegardless()
        // The dismissal channel: a key-capable nonactivating panel holds key
        // focus without activating the app, so Escape reaches an accessory
        // app that is never frontmost — with no new permission (S9).
        window.makeKey()
        scheduleIdleDismiss()
    }

    /// The safety net behind the key channel: if no key ever reaches the
    /// gesture, the surface closes itself after its idle budget — decided by
    /// the machine, which refuses the timeout once a drag is under way.
    private func scheduleIdleDismiss() {
        cancelIdleDismiss()
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.window != nil else { return }
            self.window?.handleIdleTimeout()
        }
        idleDismiss = work
        DispatchQueue.main.asyncAfter(
            deadline: .now() + TextRecognitionSurfaceCopy.idleDismissAfter,
            execute: work)
    }

    private func cancelIdleDismiss() {
        idleDismiss?.cancel()
        idleDismiss = nil
    }

    private func closeSurface() {
        if let escapeMonitor { NSEvent.removeMonitor(escapeMonitor) }
        escapeMonitor = nil
        cancelIdleDismiss()
        window?.surfaceView?.releaseCursor()
        window?.closeWithoutCallbacks()
        window = nil
        if cursorPushed { NSCursor.pop() }
        cursorPushed = false
    }

    private func recognise(_ selected: CGRect, on pointerFrame: CGRect) {
        closeSurface()
        guard let screen = NSScreen.screens.first(where: { $0.frame == pointerFrame }) else { return }
        let display = pointerFrame
        Task { @MainActor [client, weak self] in
            let result = await client.recognize(selection: selected, on: screen)
            Diag.log("text recognition result \(result)")
            guard let self else { return }
            switch result {
            case .clipboard, .dismissed:
                // Copied, or refused as a stray click: nothing to say.
                break
            case .nothingFound:
                self.showHint(.nothingFound, on: display)
            case .failed:
                self.showHint(.failed, on: display)
            case .permissionMissing:
                self.showHint(.permissionMissing, on: display)
            }
        }
    }

    private func showHint(_ feedback: TextRecognitionFeedback, on screenFrame: CGRect) {
        hintWindow?.closeSelf()
        let hint = TextRecognitionHintWindow(screenFrame: screenFrame, message: feedback.title)
        hint.onDismissed = { [weak self] in self?.hintWindow = nil }
        hintWindow = hint
        hint.orderFrontRegardless()
    }
}
