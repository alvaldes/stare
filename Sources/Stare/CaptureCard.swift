import AppKit

/// A capture, shown as a card in the corner: hover extends its life, click copies
/// again, and it can be dragged straight into another app.
final class CaptureCard: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    init(
        image: CGImage,
        onOpen: @escaping (CGImage) -> Void,
        onDismiss: @escaping () -> Void,
        onPinRequested: @escaping (CGImage, NSScreen?) -> Void
    ) {
        let size = CaptureCardView.preferredSize(for: image)
        super.init(
            contentRect: CGRect(origin: .zero, size: size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        level = NSWindow.Level(rawValue: NSWindow.Level.screenSaver.rawValue + 2)
        collectionBehavior = [.fullScreenAuxiliary, .stationary, .ignoresCycle]
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        animationBehavior = .none
        becomesKeyOnlyIfNeeded = true

        let view = CaptureCardView(
            image: image,
            onOpen: { onOpen(image) },
            onClose: { [weak self] in
                self?.close()
                onDismiss()
            }
        )
        // T4/S6: the pin action carries the image and the card's own screen,
        // resolved where it actually happens — on the card.
        view.onPin = { [weak self] in
            guard let self else { return }
            onPinRequested(image, self.screen)
        }
        contentView = view
        setContentSize(size)
    }
}

final class CaptureCardView: NSView, NSDraggingSource {
    static let thumbnailMaxSize = CGSize(width: 260, height: 170)
    static let dismissDelay: TimeInterval = 5
    static let hoverDismissDelay: TimeInterval = 3

    private let image: CGImage
    private let onOpen: () -> Void
    private let onClose: () -> Void
    private var dismissTimer: Timer?
    private var isHovered = false

    static func preferredSize(for image: CGImage) -> CGSize {
        let imageSize = CGSize(width: image.width, height: image.height)
        let scale = min(
            thumbnailMaxSize.width / imageSize.width,
            thumbnailMaxSize.height / imageSize.height,
            1
        )
        let thumbnail = CGSize(
            width: (imageSize.width * scale).rounded(),
            height: (imageSize.height * scale).rounded()
        )
        return CGSize(width: max(thumbnail.width, 160) + 16, height: thumbnail.height + 16)
    }

    /// The pin button's rect, in the card's own top-down coordinates: a round
    /// 16pt control at the top-right corner of the plate, over the thumbnail.
    /// One truth for the drawing and the hit test.
    static func pinButtonRect(in bounds: NSRect) -> NSRect {
        let size: CGFloat = 16
        let inset: CGFloat = 6
        return NSRect(
            x: bounds.maxX - inset - size,
            y: inset,
            width: size,
            height: size
        )
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("CaptureCardView is created in code only")
    }

    override var isFlipped: Bool { true }

    override func mouseUp(with event: NSEvent) {
        pinButtonPressed = false
    }

    // MARK: - Hover

    /// The card's own pin affordance (T4/S6), wired by the owner: floats the
    /// captured image instead of opening the editor. Untouched by the click
    /// that opens the editor — two actions, two regions of the card.
    var onPin: (() -> Void)?
    /// Whether the press started on the pin button, so a drag begun there
    /// does not drag the card out on the button's own spot.
    private var pinButtonPressed = false

    init(image: CGImage, onOpen: @escaping () -> Void, onClose: @escaping () -> Void) {
        self.image = image
        self.onOpen = onOpen
        self.onClose = onClose
        super.init(frame: CGRect(origin: .zero, size: Self.preferredSize(for: image)))
        wantsLayer = true
        layer?.cornerRadius = 10
        layer?.masksToBounds = true
        scheduleDismiss(after: Self.dismissDelay)
        Diag.log("card shown \(image.width)x\(image.height)")
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for area in trackingAreas { removeTrackingArea(area) }
        addTrackingArea(
            NSTrackingArea(
                rect: bounds,
                options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                owner: self,
                userInfo: nil
            )
        )
    }

    override func mouseEntered(with event: NSEvent) {
        isHovered = true
        dismissTimer?.invalidate()
        dismissTimer = nil
    }

    override func mouseExited(with event: NSEvent) {
        isHovered = false
        scheduleDismiss(after: Self.hoverDismissDelay)
    }

    private func scheduleDismiss(after delay: TimeInterval) {
        dismissTimer?.invalidate()
        dismissTimer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
            guard let self, !self.isHovered else { return }
            self.onClose()
        }
    }

    // MARK: - Drawing

    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }

        let plate = CGPath(
            roundedRect: bounds.insetBy(dx: 1, dy: 1),
            cornerWidth: 10,
            cornerHeight: 10,
            transform: nil
        )
        context.setFillColor(CGColor(gray: 0.08, alpha: 0.92))
        context.addPath(plate)
        context.fillPath()

        let inset: CGFloat = 8
        let target = CGRect(
            x: inset,
            y: inset,
            width: bounds.width - inset * 2,
            height: bounds.height - inset * 2
        )
        context.saveGState()
        // The image comes top-down; this view is flipped, so flip it back.
        context.translateBy(x: 0, y: target.midY)
        context.scaleBy(x: 1, y: -1)
        context.translateBy(x: 0, y: -target.midY)
        context.draw(image, in: target)
        context.restoreGState()

        drawPinButton(in: context)
    }

    /// The pin affordance over the thumbnail's top-right corner (T4/S6): a
    /// translucent round button with a pin glyph, always visible so the card's
    /// second action is discoverable without depending on a hover.
    private func drawPinButton(in context: CGContext) {
        let rect = Self.pinButtonRect(in: bounds)
        let circle = CGPath(ellipseIn: rect, transform: nil)
        context.setFillColor(CGColor(gray: 0.05, alpha: isHovered ? 0.85 : 0.7))
        context.addPath(circle)
        context.fillPath()
        guard let glyph = NSImage(systemSymbolName: "pin.fill", accessibilityDescription: "pin") else { return }
        let point = NSPoint(x: rect.midX - glyph.size.width / 2, y: rect.midY - glyph.size.height / 2)
        let tinted = NSImage(size: glyph.size, flipped: false) { _ in
            glyph.draw(in: NSRect(origin: .zero, size: glyph.size))
            NSColor.white.set()
            NSRect(origin: .zero, size: glyph.size).fill(using: .sourceAtop)
            return true
        }
        tinted.draw(at: point, from: .zero, operation: .sourceOver, fraction: 1)
    }

    // MARK: - Actions

    override func mouseDown(with event: NSEvent) {
        // Clicking opens the editor, like the reference app: the pasteboard
        // already has the image, so copy is not the interesting action here.
        dismissTimer?.invalidate()
        let point = convert(event.locationInWindow, from: nil)
        if Self.pinButtonRect(in: bounds).contains(point) {
            // T4/S6: the pin button floats the image instead of opening the
            // editor — its own entry point, distinct from the click.
            pinButtonPressed = true
            onPin?()
            return
        }
        onOpen()
    }

    override func mouseDragged(with event: NSEvent) {
        // A drag that started on the pin button carries the image out — but
        // the button's action has already floated the image, so the card's
        // own drag stays off the button.
        guard !pinButtonPressed else { return }
        let point = convert(event.locationInWindow, from: nil)
        guard !Self.pinButtonRect(in: bounds).contains(point) else { return }
        let provider = NSImage(cgImage: image, size: bounds.size)
        let item = NSDraggingItem(pasteboardWriter: provider)
        item.setDraggingFrame(bounds, contents: provider)
        beginDraggingSession(with: [item], event: event, source: self)
        Diag.log("card dragged out")
    }

    func draggingSession(
        _ session: NSDraggingSession,
        sourceOperationMaskFor context: NSDraggingContext
    ) -> NSDragOperation {
        .copy
    }

    private func copyToPasteboard() {
        let representation = NSBitmapImageRep(cgImage: image)
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.declareTypes([.png, .tiff], owner: nil)
        if let png = representation.representation(using: .png, properties: [:]) {
            pasteboard.setData(png, forType: .png)
        }
        if let tiff = representation.tiffRepresentation {
            pasteboard.setData(tiff, forType: .tiff)
        }
        Diag.log("card copied again")
    }
}

/// Keeps capture cards stacked in the corner of the display they came from.
final class CaptureCardController {
    var onOpen: ((CGImage) -> Void)?
    /// The pin entry point (T4/S6): arrives with the image the card shows and
    /// the screen the card lives on, so the floating window lands near what
    /// the user pinned.
    var onPin: ((CGImage, NSScreen?) -> Void)?
    private var cards: [CaptureCard] = []
    /// Read by tests, which close the cards they open.
    var openCards: [CaptureCard] { cards }
    private let maximumCards = 4

    func show(_ image: CGImage, on screen: NSScreen?) {
        var card: CaptureCard!
        card = CaptureCard(
            image: image,
            onOpen: { [weak self] image in self?.onOpen?(image) },
            onDismiss: { [weak self] in self?.cards.removeAll { $0 === card } },
            onPinRequested: { [weak self] image, screen in self?.onPin?(image, screen) }
        )
        cards.append(card)

        while cards.count > maximumCards {
            let oldest = cards.removeFirst()
            oldest.close()
        }

        position(card, on: screen)
        card.orderFrontRegardless()
    }

    private func position(_ card: CaptureCard, on screen: NSScreen?) {
        guard let screen = screen ?? NSScreen.main else { return }
        let visible = screen.visibleFrame
        let margin: CGFloat = 20
        let gap: CGFloat = 10

        var bottom = visible.minY + margin
        for existing in cards where existing !== card {
            bottom += existing.frame.height + gap
        }

        card.setFrameOrigin(
            CGPoint(
                x: (visible.maxX - card.frame.width - margin).rounded(),
                y: bottom.rounded()
            )
        )
    }
}
