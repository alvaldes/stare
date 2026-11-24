import AppKit
import StareCore

/// One pinned capture image (T4/S6): a borderless always-on-top window that
/// floats the captured pixels over any app — draggable, resizable by scroll,
/// opacity-steppable by ⌥-scroll, and lockable so every click passes through
/// it. Its lifecycle is its own: several coexist, each closes itself, and
/// none of them belongs to a drawing session, so they outlive the overlay.
/// Local only — nothing here touches disk.
final class PinnedImageWindow: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    /// The click-through lock, applied on the window surface.
    private(set) var lockState: PinnedImageLockState = .floating

    /// Fired when this window closes itself, so its owner takes it off the
    /// list — the same hand-off the capture card's onDismiss does.
    var onClosed: (() -> Void)?

    init(image: CGImage, placement: CGRect) {
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
        hasShadow = true
        // An accessory app loses activation whenever the user clicks another
        // one; the pinned image must stay exactly where it is.
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        isMovableByWindowBackground = true
        animationBehavior = .none
        becomesKeyOnlyIfNeeded = true

        let view = PinnedImageView(frame: CGRect(origin: .zero, size: placement.size), image: image)
        view.onLock = { [weak self] in self?.toggleLock() }
        view.onClose = { [weak self] in self?.closeSelf() }
        contentView = view
        Diag.log("pin image shown \(image.width)x\(image.height)")
    }

    /// Test helper with production parity: the view draws and routes, and the
    /// test needs the same view a pin produces.
    var pinnedView: PinnedImageView? { contentView as? PinnedImageView }

    /// Locks or unlocks: locked, the surface passes every mouse event
    /// through to the app underneath except the three controls, which keep
    /// answering — a lock that covered the ✕ would be a trap the pointer
    /// could not leave. The same toggle unlocks it.
    func toggleLock() {
        lockState = lockState.toggled
        pinnedView?.needsDisplay = true
        Diag.log("pin image lock \(lockState == .locked ? "on" : "off")")
    }

    /// Closes itself and tells its owner, so the coordinator's list never
    /// holds a window that is gone.
    func closeSelf() {
        let handler = onClosed
        onClosed = nil
        close()
        handler?()
    }

    override func close() {
        super.close()
        Diag.log("pin image closed")
    }
}

/// The pinned window's surface: the capture at the window's size, with the
/// pinned badge (the indicator that this is a pin, and the unpin affordance),
/// a lock and a close control — all drawn always, never only on hover (T4
/// pin fix): a pin that hides its way out until the pointer arrives reads as
/// uncloseable, exactly what the human reported. Flipped like the capture
/// card, because the controls are laid out from the top.
final class PinnedImageView: NSView {
    var onLock: (() -> Void)?
    var onClose: (() -> Void)?

    private let image: CGImage

    init(frame: NSRect, image: CGImage) {
        self.image = image
        super.init(frame: frame)
        wantsLayer = true
        layer?.cornerRadius = 6
        layer?.masksToBounds = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("PinnedImageView is created in code only")
    }

    override var isFlipped: Bool { true }

    /// The surface gives its background drags to the window's own moving, so
    /// any part of the image drags the window (the path a custom borderless
    /// view has to open itself).
    override var mouseDownCanMoveWindow: Bool { true }

    /// The lock's surface rule (T4 closing fix): locked, every point except
    /// the three controls is declined — a declined hit test is what makes the
    /// click fall through to the app underneath — while the 📌, the ✕ and the
    /// 🔒 keep answering, so the lock stays escapable with the pointer. The
    /// window itself never sets `ignoresMouseEvents`: the per-point decision
    /// is made here, where the controls live.
    override func hitTest(_ point: NSPoint) -> NSView? {
        // `point` arrives in the superview's (bottom-up) space; `convert`
    // returns it in this view's own space, which is top-down — this view
    // is flipped.
        let topDown: NSPoint
        if let superview {
            topDown = convert(point, from: superview)
        } else {
            topDown = point
        }
        let window = self.window as? PinnedImageWindow
        let lock = window?.lockState ?? .floating
        guard lock.acceptsMouseEvents(at: topDown, in: CGRect(origin: .zero, size: bounds.size)) else {
            return nil
        }
        return super.hitTest(point)
    }

    // MARK: - Actions

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        // The pinned badge is the unpin affordance: it shows this floating
        // thing is a pin, and pressing it closes the pin.
        if PinnedImageControls.rect(for: .pin, in: bounds).contains(point) {
            onClose?()
            return
        }
        if PinnedImageControls.rect(for: .close, in: bounds).contains(point) {
            onClose?()
            return
        }
        if PinnedImageControls.rect(for: .lock, in: bounds).contains(point) {
            onLock?()
            return
        }
        // Everything else belongs to the window drag.
    }

    override func mouseUp(with event: NSEvent) {}

    override func scrollWheel(with event: NSEvent) {
        handleScroll(
            deltaY: event.scrollingDeltaY,
            optionDown: event.modifierFlags.contains(.option)
        )
    }

    /// Scroll resizes, ⌥-scroll steps opacity. Split out of the event so the
    /// resize and opacity rules are drivable in a test without synthesizing a
    /// scroll event.
    func handleScroll(deltaY: CGFloat, optionDown: Bool) {
        guard deltaY != 0, let window else { return }
        if optionDown {
            window.alphaValue = PinnedImageGeometry.steppedOpacity(window.alphaValue, direction: deltaY)
            Diag.log("pin image opacity \(window.alphaValue)")
            return
        }
        guard let screen = window.screen ?? NSScreen.main else { return }
        let steps: CGFloat = deltaY > 0 ? 1 : -1
        let frame = PinnedImageGeometry.resizedFrame(window.frame, steps: steps, in: screen.visibleFrame)
        window.setFrame(frame, display: true)
        Diag.log("pin image resize \(frame.width)x\(frame.height)")
    }

    // MARK: - Drawing

    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }

        // The window's frame carries the image's aspect exactly, so the
        // surface is the image.
        context.saveGState()
        context.translateBy(x: 0, y: bounds.midY)
        context.scaleBy(x: 1, y: -1)
        context.translateBy(x: 0, y: -bounds.midY)
        context.draw(image, in: bounds)
        context.restoreGState()

        drawControl(.pin, symbol: "pin.fill", in: context)
        drawControl(.close, symbol: "xmark", in: context)
        drawControl(.lock, symbol: "lock.fill", in: context)
    }

    /// One round control: a translucent dark circle with the glyph, readable
    /// over anything the capture might show.
    private func drawControl(_ kind: PinnedImageControls.Kind, symbol: String, in context: CGContext) {
        let rect = PinnedImageControls.rect(for: kind, in: bounds)
        let circle = CGPath(ellipseIn: rect, transform: nil)
        context.setFillColor(CGColor(gray: 0.05, alpha: 0.78))
        context.addPath(circle)
        context.fillPath()
        guard let glyph = NSImage(systemSymbolName: symbol, accessibilityDescription: kind.rawValue) else { return }
        let point = NSPoint(x: rect.midX - glyph.size.width / 2, y: rect.midY - glyph.size.height / 2)
        let tinted = NSImage(size: glyph.size, flipped: false) { _ in
            glyph.draw(in: NSRect(origin: .zero, size: glyph.size))
            NSColor.white.set()
            NSRect(origin: .zero, size: glyph.size).fill(using: .sourceAtop)
            return true
        }
        tinted.draw(at: point, from: .zero, operation: .sourceOver, fraction: 1)
    }
}

/// Owns every pinned image of the app: the coordinator outlives the overlay's
/// branches and the drawing sessions, so a pinned capture keeps floating no
/// matter what modes open and close around it. Shared, because the capture
/// card, the menu and the global shortcuts must all float into the same set.
final class PinnedImageCoordinator {
    /// The one coordinator the production paths share. Detached instances
    /// (tests) exist alongside it and never mix with it.
    static let shared = PinnedImageCoordinator()

    /// Every window that is pinned right now, oldest first — the last entry
    /// is the frontmost, which is what a lock toggle hits. Detached instances
    /// keep this list to themselves.
    private(set) var windows: [PinnedImageWindow] = []

    /// What the pin shortcuts say when they cannot act (T4 closing fix):
    /// the coordinator reports, the app layer shows the pill on the display
    /// under the pointer. Nil default, so detached test instances never
    /// open a window of their own.
    var onFeedback: ((PinnedImageFeedback) -> Void)?

    deinit {
        for window in windows { window.onClosed = nil }
    }

    /// Floats one capture. `nil` screen means "where the user is": the screen
    /// under the pointer, falling back to the main screen. The placement is
    /// decided by `PinnedImageGeometry`: the window opens fitted, beside the
    /// capture card's corner — never centred on the display — and wholly
    /// inside its screen.
    func pin(_ image: CGImage, on screen: NSScreen?) {
        guard let bounds = screen?.visibleFrame ?? Self.screenAtPointer()?.visibleFrame, !bounds.isEmpty else {
            Diag.log("pin image skipped: no screen to place it on")
            return
        }
        let size = PinnedImageGeometry.initialSize(
            imageSize: CGSize(width: image.width, height: image.height),
            bounds: bounds.size
        )
        let placement = CGRect(
            origin: PinnedImageGeometry.initialOrigin(size: size, in: bounds),
            size: size
        )
        let window = PinnedImageWindow(image: image, placement: placement)
        window.onClosed = { [weak self, weak window] in
            self?.windows.removeAll { $0 === window }
        }
        windows.append(window)
        window.orderFrontRegardless()
    }

    /// The latest capture of the session, from the history the overlay
    /// records into. The always-pin primitive the overlay's card path and
    /// `OverlayController.pinLatestCapture` use — the ⌥⇧I toggle is
    /// `togglePin(from:)`. Nothing delivered yet is a logged no-op: the
    /// shortcut pressed before any capture changes nothing on screen.
    func pinLatestCapture(from history: CaptureHistory) {
        guard let entry = history.entries.first else {
            Diag.log("pin image skipped: no capture in the session yet")
            return
        }
        pin(entry.image, on: nil)
    }

    /// The keyboard pin (⌥⇧I), per `PinnedImagePinRule` (T4 closing fix):
    /// with pins on screen the press takes the frontmost one down — locked
    /// or not, the keyboard reaches a click-through window where the pointer
    /// cannot; only a clear screen pins the session's latest capture, and
    /// nothing captured yet is a reportable no-op instead of a silent key.
    /// The card's pin button (`pin`) is the deliberate multi-pin path.
    func togglePin(from history: CaptureHistory) {
        switch PinnedImagePinRule.keyboardPin(hasPinnedImages: !windows.isEmpty, hasCaptures: !history.entries.isEmpty) {
        case .dismissTopmost:
            let topmost = windows.last
            Diag.log("pin image dismissed by the keyboard, \(windows.count) was floating")
            topmost?.closeSelf()
        case .pin:
            pin(history.entries.first!.image, on: nil)
        case .nothingToPin:
            Diag.log("pin image skipped: no capture in the session yet")
            onFeedback?(.nothingCapturedYet)
        }
    }

    /// The windows count right now, what the tests observe and the statuses
    /// report.
    var windowCount: Int { windows.count }

    /// Closes everything this coordinator owns.
    func closeAll() {
        for window in windows {
            window.onClosed = nil
            window.close()
        }
        windows.removeAll()
    }

    /// The screen the pointer is on, the fallback a `nil` screen resolves to.
    private static func screenAtPointer() -> NSScreen? {
        let location = NSEvent.mouseLocation
        return NSScreen.screens.first { $0.frame.contains(location) } ?? NSScreen.main
    }
}
