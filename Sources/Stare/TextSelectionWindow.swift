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

    /// The gesture's cursor (T5 follow-up): the same drafting crosshair the
    /// area capture drag shows, for the surface's whole life — from the
    /// moment the surface appears to the moment it closes. Held two ways:
    /// a pushed cursor at the instant the surface becomes key (a pointer
    /// that has not moved yet still sees the change), and a cursor rect over
    /// the whole surface in the view (`resetCursorRects`), so AppKit's own
    /// cursor management — the thing that otherwise resets a pushed cursor
    /// to the arrow on the first mouse move — keeps the crosshair instead of
    /// fighting it. The pop lives in `resignKey`: every exit path that ends
    /// the gesture (commit, Escape, a second press, the idle timeout, a
    /// refused stray click, teardown) closes the window, resigns its key and
    /// restores the pointer exactly as it was.
    private(set) var isShowingGestureCursor = false

    override func becomeKey() {
        super.becomeKey()
        showGestureCursor()
    }

    override func resignKey() {
        super.resignKey()
        hideGestureCursor()
    }

    private func showGestureCursor() {
        guard !isShowingGestureCursor else { return }
        NSCursor.crosshair.push()
        isShowingGestureCursor = true
    }

    private func hideGestureCursor() {
        guard isShowingGestureCursor else { return }
        NSCursor.pop()
        isShowingGestureCursor = false
    }

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

    /// The frame the loupe magnifies (T5 follow-up): the pointer's display
    /// as it was when the surface opened, captured once in the background by
    /// the flow and dropped off here when it lands. Not a per-event capture:
    /// each display capture costs a ScreenCaptureKit round trip (tens of
    /// milliseconds, and macOS serialises them), so covering a drag event
    /// would jank the gesture it assists. It does not paint over the
    /// recognition either — recognition re-captures the display at commit —
    /// so the loupe is honest about the one thing it is for: the edge being
    /// chosen is placed in screen coordinates, and a frame of the same
    /// display at the same scale maps the pixel under the loupe's crosshair
    /// exactly onto the screen point under the pointer. Whatever changed on
    /// screen since the surface opened stays visible around the translucent
    /// veil; the loupe's staleness is the same trade the area drag accepts
    /// on purpose, minus the freeze (nothing here gets frozen into a
    /// capture). Nil without pixels: no Screen Recording, no frame, no loupe
    /// — a magnifier over invented pixels would lie about the edge.
    var loupeFrame: CGImage? {
        didSet { needsDisplay = true }
    }
    /// The drag's pointer in the view's own (bottom-left) coordinates; the
    /// plan converts it into the display's top-left space.
    private var loupePoint: CGPoint?

    /// The loupe plan the drag paints right now: the pure geometry the ⇧S
    /// area drag already trusts (`AreaCaptureLoupe`), fed with this
    /// surface's own spaces — the pointer lifted into the display's
    /// top-left space, the view's bounds as the display, and the surface
    /// frame's own pixels-per-point. nil whenever there is nothing truthful
    /// to magnify: no pixels captured, no drag under way, or no pointer on
    /// the display.
    var loupePlan: AreaCaptureLoupe.Plan? {
        guard phase == .dragging, let point = loupePoint, let base = loupeFrame else { return nil }
        let pixelsPerPoint = CGFloat(base.width) / max(bounds.width, 1)
        return AreaCaptureLoupe.plan(
            at: CGPoint(x: point.x, y: bounds.height - point.y),
            bounds: CGRect(origin: .zero, size: bounds.size),
            framePixelSize: CGSize(width: base.width, height: base.height),
            pixelsPerPoint: pixelsPerPoint)
    }

    private var dragStart: CGPoint?
    private var dragCurrent: CGPoint?

    override init(frame: NSRect) {
        super.init(frame: frame)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("TextSelectionSurfaceView is created in code only")
    }

    override func resetCursorRects() {
        // The gesture's cursor, AppKit's own way: a crosshair rect over the
        // whole surface — the same cursor the area capture drag shows —
        // alive for as long as the gesture is. This is what keeps the
        // crosshair under the pointer once it moves: without a cursor rect
        // AppKit resets any pushed cursor to the arrow on the first event.
        guard phase == .inviting || phase == .dragging else { return }
        addCursorRect(bounds, cursor: .crosshair)
    }

    override func mouseDown(with event: NSEvent) {
        guard phase == .inviting else { return }
        onDragStarted?()
        dragStart = convert(event.locationInWindow, from: nil)
        dragCurrent = dragStart
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        guard dragStart != nil, phase == .dragging else { return }
        dragCurrent = convert(event.locationInWindow, from: nil)
        loupePoint = dragCurrent
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        guard let start = dragStart, phase == .dragging else { return }
        dragStart = nil
        loupePoint = nil
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
            drawLoupe()
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

    /// The area drag's magnifier, over this surface's frame. The pure
    /// geometry is the one the ⇧S drag already trusts (`AreaCaptureLoupe`):
    /// the loupe never covers the pointer's pixel, flips to the other side
    /// near a display edge and clamps inside the display — reused, not
    /// rewritten. The view only paints it.
    private func drawLoupe() {
        guard let plan = loupePlan,
            let base = loupeFrame,
            let crop = base.cropping(to: plan.source),
            let context = NSGraphicsContext.current?.cgContext else { return }
        context.saveGState()
        // The plan speaks the display's top-left space (`AreaCaptureLoupe`
        // was written in the frozen frame's own convention); this view is
        // not flipped, so flip the context once and paint the plan directly.
        context.translateBy(x: 0, y: bounds.height)
        context.scaleBy(x: 1, y: -1)
        // The magnified source, clipped to the loupe: near an edge the source
        // stops at the frame's edge and the rest of the loupe stays empty
        // instead of stretching the pixels.
        context.saveGState()
        context.addPath(CGPath(
            roundedRect: plan.frame,
            cornerWidth: 8,
            cornerHeight: 8,
            transform: nil
        ))
        context.clip()
        context.translateBy(x: plan.destination.minX, y: plan.destination.maxY)
        context.scaleBy(x: 1, y: -1)
        context.draw(crop, in: CGRect(origin: .zero, size: plan.destination.size))
        context.restoreGState()
        // Chrome: a bordered ring and the crosshair through the pointer's
        // pixel, dark-under/bright-on-top so it reads on light and dark
        // content — the same trick the drawn cursors use.
        let ring = CGPath(
            roundedRect: plan.frame.insetBy(dx: 1.5, dy: 1.5),
            cornerWidth: 7,
            cornerHeight: 7,
            transform: nil
        )
        for (colour, width) in [(CGColor(gray: 0, alpha: 0.85), CGFloat(3)), (CGColor(gray: 1, alpha: 0.95), CGFloat(1))] {
            context.setStrokeColor(colour)
            context.setLineWidth(width)
            context.addPath(ring)
            context.strokePath()
            context.move(to: CGPoint(x: plan.frame.minX, y: plan.crosshair.y))
            context.addLine(to: CGPoint(x: plan.frame.maxX, y: plan.crosshair.y))
            context.move(to: CGPoint(x: plan.crosshair.x, y: plan.frame.minY))
            context.addLine(to: CGPoint(x: plan.crosshair.x, y: plan.frame.maxY))
            context.strokePath()
        }
        context.restoreGState()
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
        window.orderFrontRegardless()
        // The dismissal channel: a key-capable nonactivating panel holds key
        // focus without activating the app, so Escape reaches an accessory
        // app that is never frontmost — with no new permission (S9).
        window.makeKey()
        scheduleIdleDismiss()
        // The loupe's frame: one capture of the pointer display, taken in the
        // background the moment the surface opens (the same off-main ask the
        // area drag's stock frame uses), so by the time a drag is under way
        // there is something truthful for it to magnify. The surface's own
        // windows — the veil, a pill — are excluded from the capture by the
        // capture service's own-window filter, so the loupe never magnifies
        // the gesture itself.
        fetchSurfaceFrame(for: window, pointerFrame: pointerFrame)
    }

    /// Asks for the frame the loupe magnifies and drops it on the surface
    /// when it lands. A failed capture (or no display under the pointer —
    /// already refused above) leaves the frame nil and the drag loupe-less,
    /// exactly the no-permission contract the area drag keeps.
    private func fetchSurfaceFrame(for window: TextSelectionWindow, pointerFrame: CGRect) {
        guard let screen = NSScreen.screens.first(where: { $0.frame == pointerFrame }),
            let displayID = TextRecognitionClient.displayID(of: screen) else { return }
        let captureService = client.captureService
        let view = window.surfaceView
        Task.detached(priority: .userInitiated) {
            let image = try? captureService.captureDisplay(displayID)
            DispatchQueue.main.async {
                view?.loupeFrame = image
            }
        }
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
        window?.closeWithoutCallbacks()
        window = nil
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
