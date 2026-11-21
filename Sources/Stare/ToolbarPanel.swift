import AppKit
import StareCore
import SwiftUI

/// Palette content view that turns a drag on any non-control area into a window
/// drag, which is what makes a borderless panel movable.
final class ToolbarHostingView: NSHostingView<ToolbarView> {
    override func mouseDown(with event: NSEvent) {
        window?.performDrag(with: event)
    }

    required init(rootView: ToolbarView) {
        super.init(rootView: rootView)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("ToolbarHostingView is created in code only")
    }
}

/// Floating, draggable tool palette. Non-activating so that picking a tool
/// never steals focus from the app underneath.
final class ToolbarPanel: NSPanel {
    private static let anchorKey = "toolbarAnchor"

    /// Posted by `requestPositionReset` (T8/S6): the palette forgets where the
    /// user dragged it and opens where a fresh install opens it.
    static let resetPositionNotification = Notification.Name("stare.toolbar.resetPosition")

    /// Clears the saved palette anchor and screen, so the palette lands where
    /// a fresh install places it, and repositions a visible palette at once.
    static func requestPositionReset() {
        UserDefaults.standard.removeObject(forKey: anchorKey)
        UserDefaults.standard.removeObject(forKey: screenKey)
        NotificationCenter.default.post(name: resetPositionNotification, object: nil)
    }

    private let state: EditorState

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    init(
        state: EditorState,
        onUndo: @escaping () -> Void,
        onRedo: @escaping () -> Void,
        onClear: @escaping () -> Void,
        onDone: @escaping () -> Void,
        onPreviousPage: (() -> Void)? = nil,
        onNextPage: (() -> Void)? = nil,
        onDeletePage: (() -> Void)? = nil
    ) {
        self.state = state
        let hosting = ToolbarHostingView(
            rootView: ToolbarView(
                state: state,
                onUndo: onUndo,
                onRedo: onRedo,
                onClear: onClear,
                onDone: onDone,
                onPreviousPage: onPreviousPage,
                onNextPage: onNextPage,
                onDeletePage: onDeletePage
            )
        )
        hosting.sizingOptions = [.intrinsicContentSize]
        let size = hosting.fittingSize

        super.init(
            contentRect: CGRect(origin: .zero, size: size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        // Above the drawing layer: the palette must stay clickable while the
        // overlay covers the whole display.
        level = NSWindow.Level(rawValue: NSWindow.Level.screenSaver.rawValue + 1)
        // Associated with the Space where drawing started, instead of following
        // the user across Spaces.
        collectionBehavior = [
            .fullScreenAuxiliary,
            .stationary,
            .ignoresCycle,
        ]
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        animationBehavior = .none
        becomesKeyOnlyIfNeeded = true

        contentView = hosting
        setContentSize(size)

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(persistAnchor),
            name: NSWindow.didMoveNotification,
            object: self
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handlePositionReset),
            name: Self.resetPositionNotification,
            object: nil
        )
    }

    /// Re-anchors a visible palette at the fresh-install spot immediately, so
    /// the Settings action is seen and not just stored for next time.
    @objc private func handlePositionReset() {
        guard isVisible else { return }
        positionNearPointerDisplay(placement: state.palettePlacementValue)
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    /// Places the palette on the display that has the pointer, at the relative
    /// spot the user last chose. Moving it between displays keeps the offset,
    /// so it lands near the same place on whichever screen you are working.
    func positionNearPointerDisplay(placement: PalettePlacement) {
        guard let target = targetScreen(for: placement) else { return }

        let anchor = savedAnchor() ?? CGPoint(x: 0.5, y: 0.08)
        let center = CGPoint(
            x: target.frame.minX + anchor.x * target.frame.width,
            y: target.frame.minY + anchor.y * target.frame.height
        )
        var origin = CGPoint(
            x: (center.x - frame.width / 2).rounded(),
            y: (center.y - frame.height / 2).rounded()
        )

        let visible = target.visibleFrame
        let margin: CGFloat = 8
        origin.x = min(max(origin.x, visible.minX + margin), visible.maxX - frame.width - margin)
        origin.y = min(max(origin.y, visible.minY + margin), visible.maxY - frame.height - margin)

        setFrameOrigin(origin)
    }

    /// Resolves the display the palette should open on.
    private func targetScreen(for placement: PalettePlacement) -> NSScreen? {
        switch placement {
        case .frontWindow:
            return frontWindowScreen() ?? screenUnderPointer()
        case .fixed:
            return savedScreen() ?? screenUnderPointer()
        case .cursor:
            return screenUnderPointer()
        }
    }

    /// The screen of the frontmost normal window, taken from the actual
    /// window server list: the front-most layer-0 window that is on screen,
    /// visible and not Stare's own. The previous frontmost-application
    /// heuristic stays as the fallback for when the list has no such window.
    /// Reading the list needs no Accessibility permission.
    private func frontWindowScreen() -> NSScreen? {
        FrontWindowLocator.frontmostNormalWindowScreen()
            ?? FrontWindowLocator.frontmostWindowScreen(
                ownerPID: NSWorkspace.shared.frontmostApplication?.processIdentifier ?? -1
            )
    }

    private static let screenKey = "toolbarScreen"

    /// The display the palette was last parked on, if it still exists.
    private func savedScreen() -> NSScreen? {
        guard let name = UserDefaults.standard.string(forKey: Self.screenKey) else { return nil }
        return NSScreen.screens.first { $0.localizedName == name }
    }

    private func screenUnderPointer() -> NSScreen? {
        let pointer = NSEvent.mouseLocation
        return NSScreen.screens.first { $0.frame.contains(pointer) }
            ?? NSScreen.main
            ?? NSScreen.screens.first
    }

    /// Stored as a fraction of the screen frame so it survives resolution and
    /// display changes.
    @objc private func persistAnchor() {
        guard let screen = screen ?? NSScreen.main else { return }
        UserDefaults.standard.set(screen.localizedName, forKey: Self.screenKey)
        let anchor = CGPoint(
            x: (frame.midX - screen.frame.minX) / screen.frame.width,
            y: (frame.midY - screen.frame.minY) / screen.frame.height
        )
        UserDefaults.standard.set([anchor.x, anchor.y], forKey: Self.anchorKey)
    }

    private func savedAnchor() -> CGPoint? {
        guard let values = UserDefaults.standard.array(forKey: Self.anchorKey) as? [Double],
              values.count == 2 else { return nil }
        return CGPoint(x: values[0], y: values[1])
    }
}
