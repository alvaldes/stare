import AppKit
import StareCore
import UniformTypeIdentifiers

/// A capture, shown as a card in the corner: hover extends its life, the click
/// on the picture opens the editor, one control per corner carries the copy,
/// save, pin and discard commands, and the capture can be dragged out as a
/// file promise (C3/S4). The card is the picture itself — no backdrop plate,
/// no action row.
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
        onPinRequested: @escaping (CGImage, NSScreen?) -> Void,
        onCopy: @escaping (CGImage) -> Void,
        onSave: @escaping (CGImage) -> Void
    ) {
        let size = CaptureCardView.preferredSize(for: image)
        let view = CaptureCardView(
            image: image,
            onOpen: { onOpen(image) },
            onClose: {
                onDismiss()
            },
            onCopy: { onCopy(image) },
            onSave: { onSave(image) }
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

        // The card TAKES the pointer's moves (B9): a non-activating panel does
        // not get them by default, so a move over a card was delivered to the
        // canvas underneath, which re-asserted its tool cursor. Dropping that
        // move from a monitor never won on the board, because the canvas also
        // re-asserts outside the monitored path. Taking the moves is the other
        // direction: the canvas never hears about a move over the card at all.
        acceptsMouseMovedEvents = true

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

/// The card is the picture itself: one control per corner — copy, save, pin,
/// discard (C3/S4) — and the whole thing a drag source for dragging into
/// another app as a file promise. The click on the picture is the annotate
/// entry: it opens the editor exactly the way the old action row's annotate
/// button did.
final class CaptureCardView: NSView, NSDraggingSource, NSFilePromiseProviderDelegate {
    /// S1: the card shrank. It used to cap the thumbnail at 260×170 with an 8 pt
    /// backdrop, which made a small result look like a window; 190×126 keeps the
    /// capture readable and the card a card.
    static let thumbnailMaxSize = CGSize(width: 190, height: 126)
    /// Inset the corner controls keep from the card's edges, in points.
    static let plateInset: CGFloat = 6
    /// A small capture never makes the card narrower (or shorter) than this:
    /// one control per corner still has to keep its own click area on it.
    static let minimumContentWidth: CGFloat = 132
    static let minimumContentHeight: CGFloat = 56

    static let copyButtonIdentifier = "captureCard.copy"
    static let saveButtonIdentifier = "captureCard.save"
    static let pinButtonIdentifier = "captureCard.pin"
    static let closeButtonIdentifier = "captureCard.close"

    // The borders (C3/S4), where they were drawn: both strokes lived in
    // `draw(_:)` below. The card's un-pinned BLACK border was not a stroke at
    // all — it was the dark plate itself, `CGColor(gray: 0.08, alpha: 0.92)`
    // filling the card inset by 1 pt behind a thumbnail inset 6 pt further,
    // so the card read as a capture inside a black frame; it is gone with the
    // plate. The PINNED border was a 2 pt stroke of
    // `CGColor(red: 0.36, green: 0.66, blue: 1, alpha: 0.95)`; the owner asked
    // it subtler, so it is now 1 pt at alpha 0.45, same hue.
    static let pinBorderWidth: CGFloat = 1
    static let pinBorderColor = CGColor(red: 0.36, green: 0.66, blue: 1, alpha: 0.45)

    static let dismissDelay: TimeInterval = 5
    static let hoverDismissDelay: TimeInterval = 3

    private let image: CGImage
    /// The picture the card shows, read by the tests (S3): the promised file,
    /// the pasteboard write and the saved file all carry THESE pixels, not a
    /// rendition of them.
    var shownImage: CGImage { image }
    private let onOpen: () -> Void
    private let onClose: () -> Void
    private let onCopy: () -> Void
    private let onSave: () -> Void
    private let copyButton: CaptureCardControlButton
    private let saveButton: CaptureCardControlButton
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
        // The card IS the picture, so nothing is added around the thumbnail
        // any more: the plate is the thumbnail itself, widened only far enough
        // for the corner controls to keep their click areas (C3/S4).
        return CGSize(
            width: max(thumbnail.width, minimumContentWidth),
            height: max(thumbnail.height, minimumContentHeight)
        )
    }

    init(
        image: CGImage,
        onOpen: @escaping () -> Void,
        onClose: @escaping () -> Void,
        onCopy: @escaping () -> Void = {},
        onSave: @escaping () -> Void = {}
    ) {
        self.image = image
        self.onOpen = onOpen
        self.onClose = onClose
        self.onCopy = onCopy
        self.onSave = onSave
        copyButton = CaptureCardControlButton(
            symbol: "doc.on.doc",
            accessibilityLabel: "Copy the capture to the clipboard",
            identifier: Self.copyButtonIdentifier
        )
        saveButton = CaptureCardControlButton(
            symbol: "square.and.arrow.down",
            accessibilityLabel: "Save the capture to a file",
            identifier: Self.saveButtonIdentifier
        )
        pinButton = CaptureCardControlButton(
            symbol: "pin",
            accessibilityLabel: "Pin the card open",
            identifier: Self.pinButtonIdentifier
        )
        closeButton = CaptureCardControlButton(
            symbol: "xmark",
            accessibilityLabel: "Discard the capture",
            identifier: Self.closeButtonIdentifier
        )
        super.init(frame: CGRect(origin: .zero, size: Self.preferredSize(for: image)))
        wantsLayer = true
        layer?.cornerRadius = 10
        layer?.masksToBounds = true

        // The four corner commands answer through the card, each routed through
        // the closure the card was created with — the same path the app's own
        // delivery answers — so every command still arrives by its existing
        // road: the pasteboard write, the capture-file write, the shared pin
        // path and the one dismiss path (C3/S4).
        for (button, action) in [
            (copyButton, #selector(copyTapped)),
            (saveButton, #selector(saveTapped)),
            (pinButton, #selector(togglePin)),
            (closeButton, #selector(closeTapped))
        ] {
            button.target = self
            button.action = action
            addSubview(button)
        }

        rescheduleDismiss()
        Diag.log("card shown \(image.width)x\(image.height)")
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("CaptureCardView is created in code only")
    }

    override var isFlipped: Bool { true }

    // MARK: - Controls

    /// The controls sit one per corner (C3/S4): copy top-left, save
    /// bottom-left, pin top-right and discard bottom-right — the owner's four
    /// commands as mirrored columns, the destructive one down at the right's
    /// bottom corner away from where the hands start. The pin keeps the
    /// top-right corner it has always held: a test outside this file pins the
    /// corner pin's placement and its uncovered click area to this corner, so
    /// the corner mapping grew around it.
    override func layout() {
        super.layout()
        let side = CaptureCardControlButton.side
        let inset = Self.plateInset
        closeButton.frame = CGRect(
            x: bounds.width - inset - side,
            y: bounds.height - inset - side,
            width: side,
            height: side
        )
        pinButton.frame = CGRect(
            x: closeButton.frame.minX,
            y: inset,
            width: side,
            height: side
        )
        saveButton.frame = CGRect(
            x: inset,
            y: closeButton.frame.minY,
            width: side,
            height: side
        )
        copyButton.frame = CGRect(x: inset, y: inset, width: side, height: side)
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

    /// The corner commands (C3/S4): each hands the picture to the path the
    /// card was created with — the controller's pasteboard write, its file
    /// write or, from the click on the picture, the editor handoff. The card
    /// itself commits nothing: the capture was already delivered before the
    /// card existed.
    @objc private func copyTapped() {
        dismissTimer?.invalidate()
        onCopy()
    }

    @objc private func saveTapped() {
        dismissTimer?.invalidate()
        onSave()
    }

    // MARK: - Hover

    /// The card is a result you click, not a canvas: the pointer over it is the
    /// arrow even while the overlay or the board holds a crosshair, which is a
    /// global `NSCursor.set()` the card's own tracking area has to answer.
    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .arrow)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for area in trackingAreas where area.owner === self { removeTrackingArea(area) }
        addTrackingArea(
            NSTrackingArea(
                rect: bounds,
                options: [.cursorUpdate, .mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                owner: self,
                userInfo: nil
            )
        )
    }

    override func cursorUpdate(with event: NSEvent) {
        NSCursor.arrow.set()
    }

    /// The card answers the pointer's own moves too, now that it takes them
    /// (B9): the canvas re-asserts its tool cursor outside the cursor-rect path,
    /// and a card that only answers `cursorUpdate` lets the crosshair come back
    /// on the next move.
    override func mouseMoved(with event: NSEvent) {
        NSCursor.arrow.set()
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

        // C3/S4: the black border is GONE — the dark plate fill this view
        // painted behind the 6 pt inset thumbnail was the black border the
        // owner asked out, so nothing is laid under the picture any more. The
        // card IS the capture, clipped to the plate's own rounding.
        let plate = CGPath(
            roundedRect: bounds,
            cornerWidth: 10,
            cornerHeight: 10,
            transform: nil
        )
        context.saveGState()
        context.addPath(plate)
        context.clip()
        // The image comes top-down; this view is flipped, so flip it back.
        context.translateBy(x: 0, y: bounds.midY)
        context.scaleBy(x: 1, y: -1)
        context.translateBy(x: 0, y: -bounds.midY)
        context.draw(image, in: bounds)
        context.restoreGState()

        // A pinned card says so on the card itself, not only on the pin — and
        // subtly now (C3/S4): the old 2 pt stroke at alpha 0.95 was described
        // in the constants above; this is 1 pt at alpha 0.45. The stroke path
        // is inset half a width so the whole line sits inside the layer's own
        // rounded clip.
        if isPinned {
            let half = Self.pinBorderWidth / 2
            let border = CGPath(
                roundedRect: bounds.insetBy(dx: half, dy: half),
                cornerWidth: 10,
                cornerHeight: 10,
                transform: nil
            )
            context.setStrokeColor(Self.pinBorderColor)
            context.setLineWidth(Self.pinBorderWidth)
            context.addPath(border)
            context.strokePath()
        }
    }

    // MARK: - Actions

    override func mouseDown(with event: NSEvent) {
        // The click on the picture IS the annotate entry (C3/S4): the press
        // opens the editor on mouse-down, exactly as the old annotate button
        // did — the mouse-down rule a test outside this file pins — and the
        // drag that begins from the same press-and-hold still starts in
        // `mouseDragged` below, unchanged.
        dismissTimer?.invalidate()
        onOpen()
    }

    /// Read by the tests (S3): the drag session the last drag-off began, so
    /// the payload the card PROMISES can be asserted without a receiver
    /// taking it, and the receiving app's contract is pinned in test conditions.
    private(set) var lastDragSession: NSDraggingSession?

    /// Read by the tests (S3), beside `lastDragSession`: the promise provider
    /// the last drag-out built — the card's own file promise — so the promised
    /// name and its bytes are asserted without a receiver taking them.
    private(set) var lastPromiseProvider: NSFilePromiseProvider?

    override func mouseDragged(with event: NSEvent) {
        let item = self.dragItem()
        lastDragSession = beginDraggingSession(with: [item], event: event, source: self)
        Diag.log("card dragged out as a file promise")
    }

    /// The drag item the card drags out (S3): a FILE promise of the capture in
    /// PNG — the file drag other apps accept, replacing the bare image the
    /// pasteboard used to carry.
    /// The bytes stay unwritten until the receiver actually takes the promise:
    /// `writePromiseTo` encodes them through the capture file path's own
    /// encoder, `CaptureFile.data(for:format:)`, so the promised file lands
    /// byte for byte like a saved capture, in the same format the app saves
    /// everything in. The promise's file name follows the app's own default
    /// naming idiom ("Stare-<date>-at-<time>.png").
    func dragItem() -> NSDraggingItem {
        let provider = NSFilePromiseProvider(
            fileType: UTType.png.identifier,
            delegate: self
        )
        lastPromiseProvider = provider
        let visual = NSImage(cgImage: image, size: bounds.size)
        let item = NSDraggingItem(pasteboardWriter: provider)
        item.setDraggingFrame(bounds, contents: visual)
        return item
    }

    /// The promised file's name, in the app's own naming idiom (the same
    /// date/at/time shape the default file name template renders).
    func filePromiseProvider(
        _ filePromiseProvider: NSFilePromiseProvider,
        fileNameForType fileType: String
    ) -> String {
        let stamp = Self.promiseDateFormatter.string(from: Date())
        return "Stare-\(stamp).png"
    }

    func filePromiseProvider(
        _ filePromiseProvider: NSFilePromiseProvider,
        writePromiseTo url: URL,
        completionHandler: @escaping (Error?) -> Void
    ) {
        guard let data = CaptureFile.data(for: image, format: .png) else {
            completionHandler(NSError(domain: NSCocoaErrorDomain, code: CocoaError.Code.coderReadCorrupt.rawValue))
            return
        }
        do {
            try data.write(to: url)
            Diag.log("card drag promise wrote \(url.lastPathComponent)")
            completionHandler(nil)
        } catch {
            completionHandler(error)
        }
    }

    /// The promise's write runs off the main thread, serially: an image encode
    /// has no reason to sit under the pointer.
    func operationQueue(for filePromiseProvider: NSFilePromiseProvider) -> OperationQueue {
        let queue = OperationQueue()
        queue.maxConcurrentOperationCount = 1
        queue.qualityOfService = .userInitiated
        return queue
    }

    static let promiseDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd-at-HH-mm-ss"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter
    }()

    func draggingSession(
        _ session: NSDraggingSession,
        sourceOperationMaskFor context: NSDraggingContext
    ) -> NSDragOperation {
        .copy
    }
}

/// One of the card's corner controls: a template symbol on a dark disc, so it
/// reads over any capture without a bezel that would make the card a window.
/// The class default's square is the corner controls' only square now (C3/S4:
/// the row's smaller buttons are gone with the row).
final class CaptureCardControlButton: NSButton {
    static let side: CGFloat = 22

    var isPinned = false {
        didSet { image = Self.symbol(isPinned ? "pin.fill" : "pin") }
    }

    init(
        symbol: String,
        accessibilityLabel: String,
        identifier: String
    ) {
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

    /// The origin for a card of `cardSize` in the bottom-right corner of
    /// `visibleFrame`, above `stackedHeight` points of cards already stacked
    /// there. The stack is packed: pinned cards keep their slot in it (they only
    /// stop counting for the cap and never dismiss themselves), so a card that
    /// outlives the ones under it drops into the free slot instead of hanging
    /// where the stack had grown to (S1, owner's second pass).
    static func nextOrigin(
        visibleFrame: CGRect,
        cardSize: CGSize,
        stackedHeight: CGFloat
    ) -> CGPoint {
        CGPoint(
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
    /// The action row's copy and save (C3/S3), routing through the overlay:
    /// the pasteboard write and the file write the capture tail itself owns.
    /// The card never re-commits — these paths never touch the histories,
    /// whose entries were written when the capture was delivered.
    var onCopy: ((CGImage) -> Void)?
    var onSave: ((CGImage) -> Void)?

    /// S1: the cap counts the cards that may still go away by themselves. A
    /// pinned card never counts and is never closed, so pinning one is a way to
    /// keep a result on screen while more captures arrive.
    static let maximumUnpinnedCards = 4

    private(set) var cards: [CaptureCard] = []
    /// Read by tests, which close the cards they open.
    var openCards: [CaptureCard] { cards }

    /// The cards on screen, in screen coordinates: the overlay's cursor path
    /// consults them so a card keeps the arrow while the drawing layer holds a
    /// crosshair over the rest of the display (B9).
    var visibleCardFrames: [CGRect] { cards.filter(\.isVisible).map(\.frame) }

    func show(_ image: CGImage, on screen: NSScreen?) {
        var card: CaptureCard!
        card = CaptureCard(
            image: image,
            onOpen: { [weak self] image in self?.onOpen?(image) },
            onDismiss: { [weak self] in self?.dismiss(card) },
            onPinRequested: { [weak self] image, screen in self?.onPin?(image, screen) },
            onCopy: { [weak self] image in self?.onCopy?(image) },
            onSave: { [weak self] image in self?.onSave?(image) }
        )
        cards.append(card)
        evictOverflow()
        repack(preferredScreen: screen)
        card.orderFrontRegardless()
    }

    /// Takes a card off the stack: the card's own close button, its dismiss
    /// timer and the cap all land here, so the stack is repacked exactly once
    /// per disappearance and the remaining cards close the gap (S1).
    func dismiss(_ card: CaptureCard) {
        cards.removeAll { $0 === card }
        card.close()
        repack(preferredScreen: nil)
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

    /// Lays the whole stack out again, oldest at the bottom: each display gets
    /// its own column, so a card on a second screen never counts for the stack
    /// on the first. `preferredScreen` only decides where a card that is not on
    /// a display yet belongs.
    private func repack(preferredScreen: NSScreen?) {
        var stackedHeight: [ObjectIdentifier: CGFloat] = [:]
        for card in cards {
            let screen = card.screen ?? preferredScreen ?? NSScreen.main
            guard let screen else { continue }
            let key = ObjectIdentifier(screen)
            let height = stackedHeight[key] ?? 0
            card.setFrameOrigin(
                CaptureCardLayout.nextOrigin(
                    visibleFrame: screen.visibleFrame,
                    cardSize: card.frame.size,
                    stackedHeight: height
                )
            )
            stackedHeight[key] = height + card.frame.size.height + CaptureCardLayout.gap
        }
    }
}
