import AppKit
import Combine
import StareCore
import SwiftUI

/// Palette content view that turns a drag on any non-control area into a window
/// drag, which is what makes a borderless panel movable.
final class ToolbarHostingView: NSHostingView<ToolbarView> {
    override func mouseDown(with event: NSEvent) {
        window?.performDrag(with: event)
    }

    /// Set by `ToolbarPanel`. Called whenever the hosted SwiftUI content has
    /// reached a fitting size the window is not showing yet, while attached
    /// to a window, so the panel can take the content's new size.
    var onFittingSizeChange: (() -> Void)?

    // MARK: Toolbar cursor (T2/S3)

    /// Over any part of the bar that is not the gripper the cursor is the
    /// arrow: the whole content is one arrow cursor rect, and the gripper's
    /// own deeper rect (open hand, closed hand while dragging) wins over its
    /// slot. `.activeAlways` mirrors the overlay's tracking area: the bar
    /// floats above other apps, so its pointer must hold while Stare is not
    /// the active one, which cursor rectangles alone do not allow.
    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .arrow)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        // Only the areas this class installs: the hosting view's SwiftUI
        // content keeps its own.
        for area in trackingAreas where area.owner === self { removeTrackingArea(area) }
        addTrackingArea(
            NSTrackingArea(
                rect: bounds,
                options: [.cursorUpdate, .activeAlways, .inVisibleRect],
                owner: self,
                userInfo: nil
            )
        )
    }

    /// The gripper's own tracking area speaks for its rect, so the arrow here
    /// never fights the hand: when the pointer is inside the gripper's frame
    /// this handler stands down whatever order AppKit delivers in.
    override func cursorUpdate(with event: NSEvent) {
        if let gripper = gripperView, gripper.frameInWindow.contains(event.locationInWindow) { return }
        NSCursor.arrow.set()
    }

    /// The gripper subview, if present: the representable nests it below
    /// SwiftUI's intermediate views, so the lookup walks the tree — shallow,
    /// and only ever runs on a cursor boundary crossing.
    private var gripperView: ToolbarGripperView? {
        var stack: [NSView] = [self]
        while let view = stack.popLast() {
            if let gripper = view as? ToolbarGripperView { return gripper }
            stack.append(contentsOf: view.subviews)
        }
        return nil
    }


    private var lastReportedFittingSize: NSSize = .zero
    private var intrinsicSizeObservation: NSKeyValueObservation?

    /// Why these hooks and not re-fitting at each state change: every path
    /// that redraws the bar — an orientation flip, a tool-set change, page
    /// controls joining, extra actions appearing — ends here, so no change
    /// site can be missed; re-fitting in each site would have to track every
    /// `@Published` field and still miss the next one.
    /// The signal the `.intrinsicContentSize` sizing option rests on is the
    /// hosting view's own `intrinsicContentSize`: when the SwiftUI content's
    /// fitting size changes, `NSHostingView` publishes a new value, and
    /// `NSView.intrinsicContentSize` is KVO-observable, so observing it reads
    /// the change directly. `layout()` covers a size change that reaches a
    /// layout pass through any other route; both dedupe against the last
    /// reported size.
    private func observeIntrinsicSize() {
        intrinsicSizeObservation = observe(
            \.intrinsicContentSize,
            options: [.initial]
        ) { [weak self] _, _ in
            guard let self else { return }
            // NSView property observations deliver on the main thread.
            MainActor.assumeIsolated { self.reportFittingSizeIfChanged() }
        }
    }

    override func layout() {
        super.layout()
        reportFittingSizeIfChanged()
    }

    private func reportFittingSizeIfChanged() {
        guard let onFittingSizeChange, window != nil else { return }
        let fit = fittingSize
        guard fit != lastReportedFittingSize else { return }
        lastReportedFittingSize = fit
        onFittingSizeChange()
    }

    required init(rootView: ToolbarView) {
        super.init(rootView: rootView)
        observeIntrinsicSize()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("ToolbarHostingView is created in code only")
    }
}

/// Floating, draggable tool palette. Non-activating so that picking a tool
/// never steals focus from the app underneath.
final class ToolbarPanel: NSPanel {
    /// The keys the panel persists its anchor and screen under. Shared with
    /// `SelfTest`, which builds a live palette to pin the resize behaviour
    /// and therefore saves and restores anything this writes.
    static let anchorKey = "toolbarAnchor"
    static let screenKey = "toolbarScreen"

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

        // From here on the window follows the content: the hooks on the
        // hosting view fire whenever the bar's fitting size changes while it
        // is on screen.
        hosting.onFittingSizeChange = { [weak self] in
            self?.requestContentFit()
        }

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
        // T9/S12: a Settings change to the orientation or the border re-docks
        // the bar at once. The saved drag anchor belonged to the previous
        // choice, so the same reset path the gripper's right-click uses
        // clears it and lands the bar on the new border's default spot.
        state.$toolbarOrientation
            .dropFirst()
            .sink { _ in
                Self.requestPositionReset()
                // Flipping the stacking direction also changes the panel's
                // size; re-dock once the window has taken the new size.
                DispatchQueue.main.async { Self.requestPositionReset() }
            }
            .store(in: &settingCancellables)
        state.$toolbarBorder
            .dropFirst()
            .sink { _ in Self.requestPositionReset() }
            .store(in: &settingCancellables)
    }

    private var settingCancellables: Set<AnyCancellable> = []

    /// Schedules a resize to the content's fitting size off the current
    /// update: the hooks fire while SwiftUI is still settling, and changing
    /// the window frame mid-pass would re-enter the layout it answers.
    private func requestContentFit() {
        DispatchQueue.main.async { [weak self] in
            guard let self, self.isVisible else { return }
            self.refitToContentFittingSize()
        }
    }

    /// Resizes the window to the hosted content's fitting size while the bar
    /// is on screen (T8/S10, T9/S12 live): a Settings change to the
    /// orientation or the tool set changes the CONTENT, and the window must
    /// follow. One anchor path drives both placing and resizing — the same
    /// relative centre anchor that placed the bar (the persisted one if the
    /// user dragged it, the border's default otherwise) feeds
    /// `ToolbarGripperSpec.barRect`, so a dragged bar keeps its anchor
    /// through a resize and the rect's clamp alone re-docks a bar the resize
    /// would push off-screen. No second positioning model.
    private func refitToContentFittingSize() {
        guard let hosting = contentView as? ToolbarHostingView else { return }
        let newSize = hosting.fittingSize
        guard newSize != frame.size else { return }
        guard let screen = screen ?? NSScreen.main ?? NSScreen.screens.first else { return }
        let anchor = savedAnchor()
            ?? ToolbarGripperSpec.defaultAnchor(border: state.toolbarBorder, screenFrame: screen.frame)
        let rect = ToolbarGripperSpec.barRect(
            barSize: newSize,
            anchor: anchor,
            screenFrame: screen.frame,
            visibleFrame: screen.visibleFrame
        )
        setFrame(rect, display: true)
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
    /// With nothing saved the bar rests at the default anchor of the chosen
    /// border (T9/S12) — the same centre-and-clamp math
    /// `ToolbarGripperSpec.barRect` pins for the tests.
    func positionNearPointerDisplay(placement: PalettePlacement) {
        guard let target = targetScreen(for: placement) else { return }

        let anchor = savedAnchor()
            ?? ToolbarGripperSpec.defaultAnchor(border: state.toolbarBorder, screenFrame: target.frame)
        let rect = ToolbarGripperSpec.barRect(
            barSize: frame.size,
            anchor: anchor,
            screenFrame: target.frame,
            visibleFrame: target.visibleFrame
        )
        setFrameOrigin(rect.origin)
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
