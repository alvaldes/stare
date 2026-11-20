import AppKit
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

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    init(
        state: EditorState,
        onUndo: @escaping () -> Void,
        onClear: @escaping () -> Void,
        onDone: @escaping () -> Void
    ) {
        let hosting = ToolbarHostingView(
            rootView: ToolbarView(
                state: state,
                onUndo: onUndo,
                onClear: onClear,
                onDone: onDone
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
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    /// Places the palette on the display that has the pointer, at the relative
    /// spot the user last chose. Moving it between displays keeps the offset,
    /// so it lands near the same place on whichever screen you are working.
    func positionNearPointerDisplay(placement: String) {
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
    private func targetScreen(for placement: String) -> NSScreen? {
        switch placement {
        case "frontWindow":
            return frontWindowScreen() ?? screenUnderPointer()
        case "fixed":
            return savedScreen() ?? screenUnderPointer()
        default:
            return screenUnderPointer()
        }
    }

    /// The screen holding the frontmost application's frontmost normal window.
    /// Read from the window list, so it needs no Accessibility permission.
    private func frontWindowScreen() -> NSScreen? {
        guard let front = NSWorkspace.shared.frontmostApplication else { return nil }
        let windows = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements],
            kCGNullWindowID
        ) as? [[String: Any]] ?? []

        for window in windows {
            guard (window[kCGWindowOwnerPID as String] as? Int32) == front.processIdentifier,
                  (window[kCGWindowLayer as String] as? Int) == 0,
                  let raw = window[kCGWindowBounds as String] as? [String: Any],
                  let rect = CGRect(dictionaryRepresentation: raw as CFDictionary),
                  rect.width > 200, rect.height > 200 else { continue }

            // Window list bounds are top-left based; screens are bottom-left.
            let primaryHeight = NSScreen.screens.first?.frame.maxY ?? 0
            let centre = CGPoint(x: rect.midX, y: primaryHeight - rect.midY)
            return NSScreen.screens.first { $0.frame.contains(centre) }
        }
        return nil
    }

    private static let screenKey = "toolbarScreen"

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
