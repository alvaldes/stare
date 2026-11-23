import AppKit
import StareCore

/// Menu bar entry point. Stare has no Dock icon and no main window, so the menu
/// carries only the actions that are not preferences; everything configurable
/// lives in Settings.
final class StatusBarController: NSObject, NSMenuDelegate {
    private let statusItem: NSStatusItem
    private let onDraw: () -> Void
    private let onClear: () -> Void
    private let onPointerToggle: () -> Void
    private let onPinToggle: () -> Void
    private let onBoardToggle: () -> Void
    private let onOpenSettings: () -> Void
    /// The fixed ⌥⇧O gesture (T5/S7): drag an area, recognise its text and
    /// QR payload on device, copy the result. No Settings pane, like the
    /// pinned image's fixed shortcuts.
    private let onRecognizeText: () -> Void
    /// Reopens the setup guide at any time; it must not reset the first-run
    /// flag, which the caller guarantees (S3).
    private let onOpenOnboarding: () -> Void
    /// Asked when the menu opens, so a checkmark never shows a stale pin state.
    private let isPinned: () -> Bool
    /// Whiteboard page state for the page actions' enablement (T12/S9): nil
    /// when the board is closed, otherwise (current, total) of the display the
    /// pointer is on.
    private let isBoardOpen: () -> Bool
    private let boardPageState: () -> (current: Int, total: Int)?
    private let onDeleteBoardPage: () -> Void
    private let onMoveBoardPageLeft: () -> Void
    private let onMoveBoardPageRight: () -> Void
    private let onResetBoardPan: () -> Void
    private let pointerItem = NSMenuItem(title: "Pointer Highlight  ⌥⇧M", action: nil, keyEquivalent: "")
    private let pinItem = NSMenuItem(title: "Pin Drawing  ⌥⇧P", action: nil, keyEquivalent: "")
    // The pinned image (T4/S6): floats the session's latest capture as a
    // borderless always-on-top window. Its own action, never the drawing pin.
    private let pinImageItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
    /// The two fixed global registrations of the pinned image (T4/S6), kept
    /// here so they live and die with the status item: ⌥⇧I pins the latest
    /// capture, ⌥⇧L toggles the lock of the pinned image under the pointer.
    private var pinnedImageHotkeys: [GlobalHotkey] = []
    /// The one fixed global registration of the OCR/QR gesture (T5/S7):
    /// ⌥⇧O opens its own selection surface, never the drawing overlay.
    private var recognitionHotkey: GlobalHotkey?
    // Whiteboard page actions (T12/S9): their shortcuts exist in the board view
    // itself; the menu items carry the same keys and are enabled only when the
    // action can apply.
    private let deletePageItem = NSMenuItem(title: "Delete Page", action: nil, keyEquivalent: "")
    private let movePageLeftItem = NSMenuItem(title: "Move Page Left", action: nil, keyEquivalent: "")
    private let movePageRightItem = NSMenuItem(title: "Move Page Right", action: nil, keyEquivalent: "")
    private let resetPanItem = NSMenuItem(title: "Reset Pan", action: nil, keyEquivalent: "")

    init(
        onDraw: @escaping () -> Void,
        onClear: @escaping () -> Void,
        onPointerToggle: @escaping () -> Void,
        onPinToggle: @escaping () -> Void,
        onBoardToggle: @escaping () -> Void,
        onOpenSettings: @escaping () -> Void,
        onOpenOnboarding: @escaping () -> Void,
        onRecognizeText: @escaping () -> Void = {},
        isPinned: @escaping () -> Bool,
        isBoardOpen: @escaping () -> Bool = { false },
        boardPageState: @escaping () -> (current: Int, total: Int)? = { nil },
        onDeleteBoardPage: @escaping () -> Void = {},
        onMoveBoardPageLeft: @escaping () -> Void = {},
        onMoveBoardPageRight: @escaping () -> Void = {},
        onResetBoardPan: @escaping () -> Void = {}
    ) {
        self.onDraw = onDraw
        self.onClear = onClear
        self.onPointerToggle = onPointerToggle
        self.onPinToggle = onPinToggle
        self.onBoardToggle = onBoardToggle
        self.onOpenSettings = onOpenSettings
        self.onOpenOnboarding = onOpenOnboarding
        self.onRecognizeText = onRecognizeText
        self.isPinned = isPinned
        self.isBoardOpen = isBoardOpen
        self.boardPageState = boardPageState
        self.onDeleteBoardPage = onDeleteBoardPage
        self.onMoveBoardPageLeft = onMoveBoardPageLeft
        self.onMoveBoardPageRight = onMoveBoardPageRight
        self.onResetBoardPan = onResetBoardPan
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()

        if let button = statusItem.button {
            button.image = Self.menuBarGlyph()
            button.image?.isTemplate = true
        }

        let menu = NSMenu()
        menu.addItem(menuItem(title: "Draw Over Screen  ⌥⇧A", action: #selector(draw)))

        pointerItem.action = #selector(togglePointer)
        pointerItem.target = self
        menu.addItem(pointerItem)

        pinItem.action = #selector(togglePin)
        pinItem.target = self
        menu.addItem(pinItem)

        pinImageItem.title = "Pin Image  \(PinnedImageHotkeyDefaults.pinDisplayName)"
        pinImageItem.action = #selector(pinImage)
        pinImageItem.target = self
        menu.addItem(pinImageItem)
        menu.addItem(menuItem(
            title: "Toggle Image Lock  \(PinnedImageHotkeyDefaults.lockDisplayName)",
            action: #selector(toggleImageLock)
        ))

        menu.addItem(menuItem(
            title: "Recognise Text  \(TextRecognitionHotkeyDefaults.displayName)",
            action: #selector(recogniseText)
        ))

        menu.addItem(menuItem(title: "Whiteboard  \(HotkeyDefaults.whiteboardDisplayName)", action: #selector(toggleBoard)))

        // Page actions (T12/S9): the equivalent draws the same shortcut the
        // board view itself answers to. The Delete key press delivers
        // "\u{7F}" (keyCode 51) — a "\u{8}" binding never fires, which the
        // selftest's menu-key probe proves with a synthetic key event.
        menu.addItem(pageItem(deletePageItem, key: "\u{7F}", modifiers: .command, action: #selector(deleteBoardPage)))
        menu.addItem(pageItem(movePageLeftItem, key: "\u{F702}", modifiers: .option, action: #selector(moveBoardPageLeft)))
        menu.addItem(pageItem(movePageRightItem, key: "\u{F703}", modifiers: .option, action: #selector(moveBoardPageRight)))
        menu.addItem(pageItem(resetPanItem, key: "0", modifiers: .command, action: #selector(resetBoardPan)))

        menu.addItem(menuItem(title: "Clear Drawing", action: #selector(clear)))
        menu.addItem(.separator())
        menu.addItem(menuItem(title: "Setup Guide…", action: #selector(openOnboarding)))
        menu.addItem(menuItem(title: "Settings…", action: #selector(openSettings), keyEquivalent: ","))
        menu.addItem(.separator())
        menu.addItem(menuItem(title: "Quit Stare", action: #selector(quit), keyEquivalent: "q"))
        menu.delegate = self
        statusItem.menu = menu

        registerPinnedImageHotkeys()
        registerRecognitionHotkey()

        // T4 closing fix: a pin shortcut that cannot act says so, the same
        // way the capture paths already do with their hint pill. The
        // coordinator only reports; the pill's placement is UI, so it is
        // decided here — on the display the pointer is on.
        PinnedImageCoordinator.shared.onFeedback = { [weak self] feedback in
            self?.showPinnedImageFeedback(feedback)
        }
    }

    /// The pinned-image shortcuts' visible refusal (T4 closing fix): the
    /// same dark pill the OCR gesture reports through, centred on the
    /// display the pointer is on. It closes itself after three and a half
    /// seconds, exactly like that gesture's.
    private func showPinnedImageFeedback(_ feedback: PinnedImageFeedback) {
        // The hotkey path arrives on the main queue (`DispatchQueue.main.async`
        // in `GlobalHotkey`) and the menu path is main by construction, so the
        // hint window creation is main-thread by both routes.
        MainActor.assumeIsolated {
            let frame = NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) }?.frame
                ?? NSScreen.main?.frame
            guard let frame else { return }
            let hint = TextRecognitionHintWindow(screenFrame: frame, message: feedback.title)
            hint.orderFrontRegardless()
            Diag.log("pin image feedback shown \(feedback.title)")
        }
    }

    /// Registers the OCR/QR gesture's one fixed shortcut (T5/S7). It sits
    /// outside the remappable four-action map by decision — no new Settings
    /// pane — registering directly through `GlobalHotkey`, exactly the way
    /// the pinned image's fixed shortcuts do. ⌥⇧O was reserved for this
    /// feature by contract (`PinnedImageHotkeyDefaults`) and is pinned free
    /// against every other shortcut in the collision test. A refused
    /// registration is logged and leaves the app without that shortcut
    /// instead of failing anything else.
    private func registerRecognitionHotkey() {
        recognitionHotkey = GlobalHotkey(binding: TextRecognitionHotkeyDefaults.binding) { [weak self] in
            self?.onRecognizeText()
        }
        Diag.log("text recognition hotkey armed count=\(recognitionHotkey == nil ? 0 : 1)")
    }

    /// Registers the pinned image's two fixed shortcuts (T4/S6). They sit
    /// outside the remappable four-action map by decision — no new Settings
    /// pane — so they register directly, exactly the way the pre-Settings
    /// hotkeys did. A refused registration is logged and leaves the app
    /// without that shortcut instead of failing anything else.
    private func registerPinnedImageHotkeys() {
        pinnedImageHotkeys = [
            GlobalHotkey(binding: PinnedImageHotkeyDefaults.pin) {
                PinnedImageCoordinator.shared.togglePin(from: CaptureHistory.shared)
            },
            GlobalHotkey(binding: PinnedImageHotkeyDefaults.lock) {
                PinnedImageCoordinator.shared.toggleLock(at: NSEvent.mouseLocation)
            },
        ].compactMap { $0 }
        Diag.log(
            "pin image hotkeys armed \(PinnedImageHotkeyDefaults.pinDisplayName) \(PinnedImageHotkeyDefaults.lockDisplayName) count=\(pinnedImageHotkeys.count)"
        )
    }

    /// The pin is toggled by a global hotkey too, so the checkmark is read when
    /// the menu opens instead of being kept in sync by hand.
    func menuWillOpen(_ menu: NSMenu) {
        pinItem.state = isPinned() ? .on : .off
    }

    /// The page actions only make sense while the board is open, and only
    /// where they can apply: delete is refused on the last remaining page and
    /// a move is refused at the ends, so those cases stay disabled.
    /// The pin action only makes sense with something captured this session.
    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        switch menuItem {
        case pinImageItem:
            return !CaptureHistory.shared.entries.isEmpty
        case deletePageItem:
            return isBoardOpen() && (boardPageState()?.total ?? 1) > 1
        case movePageLeftItem:
            return boardPageState().map { $0.current > 1 } ?? false
        case movePageRightItem:
            return boardPageState().map { $0.current < $0.total } ?? false
        case resetPanItem:
            return boardPageState() != nil
        default:
            return true
        }
    }

    /// Wires a page item's key equivalent, target and action once, at build
    /// time. The target is the controller, so `validateMenuItem` sees the
    /// enablement queries.
    private func pageItem(
        _ item: NSMenuItem,
        key: String,
        modifiers: NSEvent.ModifierFlags,
        action: Selector
    ) -> NSMenuItem {
        item.keyEquivalent = key
        item.keyEquivalentModifierMask = modifiers
        item.target = self
        item.action = action
        return item
    }

    @objc private func deleteBoardPage() { onDeleteBoardPage() }
    @objc private func moveBoardPageLeft() { onMoveBoardPageLeft() }
    @objc private func moveBoardPageRight() { onMoveBoardPageRight() }
    @objc private func resetBoardPan() { onResetBoardPan() }

    private func menuItem(
        title: String,
        action: Selector,
        keyEquivalent: String = ""
    ) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: keyEquivalent)
        item.target = self
        return item
    }

    /// Stare's logo: the open nib the app icon and the landing carry, drawn as a
    /// path instead of shipped as a bitmap so it stays sharp at any scale and
    /// needs no bundle resource. It stays a template image, so the menu bar paints
    /// it black or white for the current appearance.
    ///
    /// A PDF from the SVG artwork was the first attempt and does not work: librsvg
    /// drops the mask the holes are cut with, AppKit gets an empty `NSPDFImageRep`
    /// and the status item draws nothing.
    private static func menuBarGlyph() -> NSImage {
        NSImage(size: NSSize(width: 18, height: 18), flipped: false) { rect in
            guard let context = NSGraphicsContext.current?.cgContext else { return false }
            let scale = min(rect.width, rect.height) / nibDesignSize
            context.scaleBy(x: scale, y: scale)
            // The slit runs past the tip so the tines stay apart, and even-odd fill
            // alone would fill that overshoot as a spike. Clipping to the outline
            // first keeps the outside of the nib empty.
            context.saveGState()
            context.addPath(nibOutline)
            context.clip()
            context.addPath(nibOutline)
            context.addPath(nibHoles)
            context.setFillColor(NSColor.black.cgColor)
            context.fillPath(using: .evenOdd)
            context.restoreGState()
            return true
        }
    }

    private static let nibDesignSize: CGFloat = 64

    /// The nib in the same 64-unit design box as `Resources/app-icon.svg`, whose
    /// y axis points down like the SVG. Insets to 87% and a 32° rotation are what
    /// keep it reading as a nib instead of a leaf at menu bar size.
    private static let nibOutline: CGPath = {
        let path = CGMutablePath()
        path.move(to: CGPoint(x: 32, y: 4))
        path.addCurve(
            to: CGPoint(x: 42, y: 32.5),
            control1: CGPoint(x: 39.5, y: 10.5),
            control2: CGPoint(x: 44, y: 19.5)
        )
        path.addLine(to: CGPoint(x: 32, y: 58))
        path.addLine(to: CGPoint(x: 22, y: 32.5))
        path.addCurve(
            to: CGPoint(x: 32, y: 4),
            control1: CGPoint(x: 20, y: 19.5),
            control2: CGPoint(x: 24.5, y: 10.5)
        )
        path.closeSubpath()
        return place(path)
    }()

    /// Breather hole plus a slit wide enough to split the tip into two tines at 16pt.
    private static let nibHoles: CGPath = {
        let path = CGMutablePath()
        path.addEllipse(in: CGRect(x: 28.8, y: 23.8, width: 6.4, height: 6.4))
        path.addRect(CGRect(x: 30.2, y: 28.5, width: 3.6, height: 31))
        return place(path)
    }()

    /// Takes a path from the SVG's y-down design box into AppKit's y-up space.
    private static func place(_ path: CGPath) -> CGPath {
        let rotate = CGAffineTransform(translationX: 32, y: 32)
            .rotated(by: 32 * .pi / 180)
            .translatedBy(x: -32, y: -32)
        let placement = CGAffineTransform(translationX: 4.2, y: 4.2)
            .scaledBy(x: 0.87, y: 0.87)
            .concatenating(rotate)
        var transform = placement.concatenating(
            CGAffineTransform(translationX: 0, y: nibDesignSize).scaledBy(x: 1, y: -1)
        )
        return path.copy(using: &transform) ?? path
    }

    @objc private func draw() { onDraw() }
    @objc private func clear() { onClear() }
    @objc private func togglePointer() { onPointerToggle() }
    @objc private func togglePin() { onPinToggle() }
    /// T4/S6: pins the session's latest capture as a floating image — and
    /// takes the frontmost pin down again on the next press, so the
    /// keyboard can never stack what it cannot dismiss. The menu and the
    /// ⌥⇧I hotkey run the same path.
    @objc private func pinImage() {
        PinnedImageCoordinator.shared.togglePin(from: CaptureHistory.shared)
    }

    /// T4/S6: toggles the click-through lock of the pinned image the pointer
    /// is over — the one the user is looking at and working underneath.
    @objc private func toggleImageLock() {
        PinnedImageCoordinator.shared.toggleLock(at: NSEvent.mouseLocation)
    }

    /// T5/S7: the menu entry runs the same gesture the ⌥⇧O hotkey does.
    @objc private func recogniseText() {
        onRecognizeText()
    }
    @objc private func toggleBoard() { onBoardToggle() }
    @objc private func openSettings() { onOpenSettings() }
    @objc private func openOnboarding() { onOpenOnboarding() }
    @objc private func quit() { NSApp.terminate(nil) }
}
