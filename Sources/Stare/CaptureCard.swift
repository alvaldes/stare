import AppKit

/// A capture, shown as a card in the corner: hover extends its life, click opens
/// the editor, the pin fixes it in place, the close dismisses it, and it can be
/// dragged straight into another app (S1).
final class CaptureCard: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    private let cardView: CaptureCardView

    /// S1: a pinned card stops counting for the stack and ignores its dismiss
    /// timer, so it stays exactly where the user left it.
    var isPinned: Bool {
        get { cardView.isPinned }
        set { cardView.isPinned = newValue }
    }

    init(
        image: CGImage,
        onOpen: @escaping (CGImage) -> Void,
        onDismiss: @escaping () -> Void,
        onPinRequested: @escaping (CGImage, NSScreen?) -> Void
    ) {
        let size = CaptureCardView.preferredSize(for: image)
        let view = CaptureCardView(
            image: image,
            onOpen: { onOpen(image) },
            onClose: {
                onDismiss()
            }
        )
        // T4/S6: the pin action carries the image and the card's own screen,
        // resolved where it actually happens — on the card. The same press also
        // flips the card's own pinned state (S1), so the plate's mark and the
        // cap follow the pin instead of being a second, silent story.
        cardView = view
        super.init(
            contentRect: CGRect(origin: .zero, size: size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        // Above the drawing layer and the palettes: a capture card is a result
        // the user asked for, so nothing Stare draws may cover it (S1).
        level = NSWindow.Level(rawValue: NSWindow.Level.screenSaver.rawValue + 2)
        collectionBehavior = [.fullScreenAuxiliary, .stationary, .ignoresCycle]
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        animationBehavior = .none
        becomesKeyOnlyIfNeeded = true

        contentView = view
        setContentSize(size)

        // Wired after `super.init`: the closure reads the card's own screen, so
        // it cannot exist before the panel does.
        view.onPin = { [weak self] in
            guard let self else { return }
            onPinRequested(image, self.screen)
        }
    }
}

/// The card's plate: the thumbnail with the pin and close controls on its top
/// right corner, all of it one drag source for dragging into another app.
final class CaptureCardView: NSView, NSDraggingSource {
    /// S1: the card shrank. It used to cap the thumbnail at 260×170 with an 8 pt
    /// backdrop, which made a small result look like a window; 190×126 keeps the
    /// capture readable and the card a card.
    static let thumbnailMaxSize = CGSize(width: 190, height: 126)
    /// Backdrop kept around the thumbnail, in points.
    static let plateInset: CGFloat = 6
    /// A tall or small capture never makes the plate narrower than this.
    static let minimumContentWidth: CGFloat = 132

    static let dismissDelay: TimeInterval = 5
    static let hoverDismissDelay: TimeInterval = 3

    static let pinButtonIdentifier = "captureCard.pin"
    static let closeButtonIdentifier = "captureCard.close"

    private let image: CGImage
    private let onOpen: () -> Void
    private let onClose: () -> Void
    private let pinButton: CaptureCardControlButton
    private let closeButton: CaptureCardControlButton
    private var dismissTimer: Timer?
    private var hasBeenHovered = false
    private var isHovered = false

    /// S1: pinned means the timer never takes it away and the controller never
    /// moves it. The pin's symbol and the plate's accent follow the state.
    var isPinned = false {
        didSet {
            guard isPinned != oldValue else { return }
            pinButton.isPinned = isPinned
            needsDisplay = true
            rescheduleDismiss()
            Diag.log("card pinned=\(isPinned)")
        }
    }

    /// When the card may take itself away, and for how long: pinned never, hover
    /// never, and a card the pointer has left gets the shorter grace. A pure
    /// policy so the timer and its tests read the same rule.
    static func autoDismissDelay(
        isPinned: Bool,
        isHovered: Bool,
        hasBeenHovered: Bool
    ) -> TimeInterval? {
        if isPinned || isHovered { return nil }
        return hasBeenHovered ? hoverDismissDelay : dismissDelay
    }

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
        return CGSize(
            width: max(thumbnail.width, minimumContentWidth) + plateInset * 2,
            height: thumbnail.height + plateInset * 2
        )
    }

    init(image: CGImage, onOpen: @escaping () -> Void, onClose: @escaping () -> Void) {
        self.image = image
        self.onOpen = onOpen
        self.onClose = onClose
        pinButton = CaptureCardControlButton(
            symbol: "pin",
            accessibilityLabel: "Pin the card open",
            identifier: Self.pinButtonIdentifier
        )
        closeButton = CaptureCardControlButton(
            symbol: "xmark",
            accessibilityLabel: "Close the card",
            identifier: Self.closeButtonIdentifier
        )
        super.init(frame: CGRect(origin: .zero, size: Self.preferredSize(for: image)))
        wantsLayer = true
        layer?.cornerRadius = 10
        layer?.masksToBounds = true

        pinButton.target = self
        pinButton.action = #selector(togglePin)
        closeButton.target = self
        closeButton.action = #selector(closeTapped)
        addSubview(pinButton)
        addSubview(closeButton)

        rescheduleDismiss()
        Diag.log("card shown \(image.width)x\(image.height)")
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("CaptureCardView is created in code only")
    }

    override var isFlipped: Bool { true }

    // MARK: - Controls

    /// The controls ride the plate's top-right corner, the close last so the
    /// destructive one is not the one under a stray click.
    override func layout() {
        super.layout()
        let side = CaptureCardControlButton.side
        let inset = Self.plateInset
        closeButton.frame = CGRect(
            x: bounds.width - inset - side,
            y: inset,
            width: side,
            height: side
        )
        pinButton.frame = CGRect(
            x: closeButton.frame.minX - 4 - side,
            y: inset,
            width: side,
            height: side
        )
    }

    /// T4/S6: what the pin target does beyond its own state — the owner floats
    /// the captured image as a window of its own from here.
    var onPin: (() -> Void)?

    @objc private func togglePin() {
        isPinned.toggle()
        onPin?()
    }

    @objc private func closeTapped() {
        dismissTimer?.invalidate()
        dismissTimer = nil
        onClose()
    }

    // MARK: - Hover

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for area in trackingAreas where area.owner === self { removeTrackingArea(area) }
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
        hasBeenHovered = true
        rescheduleDismiss()
    }

    override func mouseExited(with event: NSEvent) {
        isHovered = false
        rescheduleDismiss()
    }

    /// Arms the dismiss timer from `autoDismissDelay`, which owns the policy:
    /// pinned and hovered cards get no timer at all.
    private func rescheduleDismiss() {
        dismissTimer?.invalidate()
        dismissTimer = nil
        guard let delay = Self.autoDismissDelay(
            isPinned: isPinned,
            isHovered: isHovered,
            hasBeenHovered: hasBeenHovered
        ) else { return }
        dismissTimer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
            guard let self, !self.isHovered, !self.isPinned else { return }
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

        let inset = Self.plateInset
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

        // A pinned card says so on the plate itself, not only on the pin.
        if isPinned {
            context.setStrokeColor(CGColor(red: 0.36, green: 0.66, blue: 1, alpha: 0.95))
            context.setLineWidth(2)
            context.addPath(plate)
            context.strokePath()
        }
    }

    // MARK: - Actions

    override func mouseDown(with event: NSEvent) {
        // Clicking opens the editor, like the reference app: the pasteboard
        // already has the image, so copy is not the interesting action here.
        dismissTimer?.invalidate()
        onOpen()
    }

    override func mouseDragged(with event: NSEvent) {
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

/// One of the card's corner controls: a template symbol on a dark disc, so it
/// reads over any capture without a bezel that would make the card a window.
final class CaptureCardControlButton: NSButton {
    static let side: CGFloat = 22

    var isPinned = false {
        didSet { image = Self.symbol(isPinned ? "pin.fill" : "pin") }
    }

    init(symbol: String, accessibilityLabel: String, identifier: String) {
        super.init(frame: CGRect(x: 0, y: 0, width: Self.side, height: Self.side))
        image = Self.symbol(symbol)
        imagePosition = .imageOnly
        isBordered = false
        bezelStyle = .shadowlessSquare
        contentTintColor = .white
        toolTip = accessibilityLabel
        setAccessibilityLabel(accessibilityLabel)
        self.identifier = NSUserInterfaceItemIdentifier(identifier)
        wantsLayer = true
        layer?.cornerRadius = Self.side / 2
        layer?.backgroundColor = NSColor(white: 0, alpha: 0.55).cgColor
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("CaptureCardControlButton is created in code only")
    }

    private static func symbol(_ name: String) -> NSImage? {
        let configuration = NSImage.SymbolConfiguration(pointSize: 10, weight: .bold)
        return NSImage(systemSymbolName: name, accessibilityDescription: nil)?
            .withSymbolConfiguration(configuration)
    }
}

/// Where the cards stand on a display: the pure part of the controller, so the
/// stacking rule is pinned without a window.
enum CaptureCardLayout {
    /// Gap the stack keeps from the visible frame's corner.
    static let margin: CGFloat = 20
    /// Gap between stacked cards.
    static let gap: CGFloat = 10

    /// The origin for a card of `cardSize` in the bottom-right corner, above
    /// `stackedSizes` — the cards already stacked there, oldest first. Pinned
    /// cards are not stacked: they keep the frame the user left them in, so a
    /// later capture lands on the unpinned ones only (S1).
    static func nextOrigin(
        visibleFrame: CGRect,
        cardSize: CGSize,
        stackedSizes: [CGSize]
    ) -> CGPoint {
        let stackedHeight = stackedSizes.reduce(0) { $0 + $1.height + gap }
        return CGPoint(
            x: (visibleFrame.maxX - cardSize.width - margin).rounded(),
            y: (visibleFrame.minY + margin + stackedHeight).rounded()
        )
    }
}

/// Keeps capture cards stacked in the corner of the display they came from, and
/// keeps every pinned one exactly where it is (S1).
final class CaptureCardController {
    var onOpen: ((CGImage) -> Void)?
    /// T4/S6: arrives with the image the card shows and the screen the card
    /// lives on, so the floating window lands near what the user pinned.
    var onPin: ((CGImage, NSScreen?) -> Void)?

    /// S1: the cap counts the cards that may still go away by themselves. A
    /// pinned card never counts and is never closed, so pinning one is a way to
    /// keep a result on screen while more captures arrive.
    static let maximumUnpinnedCards = 4

    private(set) var cards: [CaptureCard] = []

    func show(_ image: CGImage, on screen: NSScreen?) {
        var card: CaptureCard!
        card = CaptureCard(
            image: image,
            onOpen: { [weak self] image in self?.onOpen?(image) },
            onDismiss: { [weak self] in
                self?.cards.removeAll { $0 === card }
                card.close()
            },
            onPinRequested: { [weak self] image, screen in self?.onPin?(image, screen) }
        )
        cards.append(card)
        evictOverflow()
        position(card, on: screen)
        card.orderFrontRegardless()
    }

    /// Closes the oldest unpinned cards past the cap. Pinned ones are skipped
    /// over, never closed, so the cap can only shrink the part of the stack that
    /// was going to disappear on its own anyway.
    private func evictOverflow() {
        var unpinned = cards.reduce(0) { $0 + ($1.isPinned ? 0 : 1) }
        var index = 0
        while unpinned > Self.maximumUnpinnedCards, index < cards.count {
            let candidate = cards[index]
            guard !candidate.isPinned else {
                index += 1
                continue
            }
            cards.remove(at: index)
            candidate.close()
            unpinned -= 1
        }
    }

    private func position(_ card: CaptureCard, on screen: NSScreen?) {
        guard let screen = screen ?? NSScreen.main else { return }
        let stacked = cards
            .filter { $0 !== card && !$0.isPinned }
            .map(\.frame.size)
        card.setFrameOrigin(
            CaptureCardLayout.nextOrigin(
                visibleFrame: screen.visibleFrame,
                cardSize: card.frame.size,
                stackedSizes: stacked
            )
        )
    }
}
