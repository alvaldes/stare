import AppKit

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
    /// Reopens the setup guide at any time; it must not reset the first-run
    /// flag, which the caller guarantees (S3).
    private let onOpenOnboarding: () -> Void
    /// Asked when the menu opens, so a checkmark never shows a stale pin state.
    private let isPinned: () -> Bool
    private let pointerItem = NSMenuItem(title: "Pointer Highlight  ⌥⇧M", action: nil, keyEquivalent: "")
    private let pinItem = NSMenuItem(title: "Pin Drawing  ⌥⇧P", action: nil, keyEquivalent: "")

    init(
        onDraw: @escaping () -> Void,
        onClear: @escaping () -> Void,
        onPointerToggle: @escaping () -> Void,
        onPinToggle: @escaping () -> Void,
        onBoardToggle: @escaping () -> Void,
        onOpenSettings: @escaping () -> Void,
        onOpenOnboarding: @escaping () -> Void,
        isPinned: @escaping () -> Bool
    ) {
        self.onDraw = onDraw
        self.onClear = onClear
        self.onPointerToggle = onPointerToggle
        self.onPinToggle = onPinToggle
        self.onBoardToggle = onBoardToggle
        self.onOpenSettings = onOpenSettings
        self.onOpenOnboarding = onOpenOnboarding
        self.isPinned = isPinned
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

        menu.addItem(menuItem(title: "Whiteboard  \(HotkeyDefaults.whiteboardDisplayName)", action: #selector(toggleBoard)))

        menu.addItem(menuItem(title: "Clear Drawing", action: #selector(clear)))
        menu.addItem(.separator())
        menu.addItem(menuItem(title: "Setup Guide…", action: #selector(openOnboarding)))
        menu.addItem(menuItem(title: "Settings…", action: #selector(openSettings), keyEquivalent: ","))
        menu.addItem(.separator())
        menu.addItem(menuItem(title: "Quit Stare", action: #selector(quit), keyEquivalent: "q"))
        menu.delegate = self
        statusItem.menu = menu
    }

    /// The pin is toggled by a global hotkey too, so the checkmark is read when
    /// the menu opens instead of being kept in sync by hand.
    func menuWillOpen(_ menu: NSMenu) {
        pinItem.state = isPinned() ? .on : .off
    }

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
    @objc private func toggleBoard() { onBoardToggle() }
    @objc private func openSettings() { onOpenSettings() }
    @objc private func openOnboarding() { onOpenOnboarding() }
    @objc private func quit() { NSApp.terminate(nil) }
}
