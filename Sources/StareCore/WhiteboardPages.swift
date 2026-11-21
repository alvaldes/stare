import CoreGraphics
import Foundation

/// A whiteboard page's solid background. Three choices: white, black, or
/// follow the system — white in light mode, black in dark mode. The choice is
/// a value of the page itself, so the page keeps its own identity (⌘B knows
/// whether the user picked a colour or the page still follows the theme); the
/// concrete colour is resolved against the appearance wherever one is
/// consumed — paint, capture base, beneath-blur image. Inks are never
/// remapped, so a mark colour that vanishes against the background is the
/// user's call.
public enum BoardBackground: String, CaseIterable, Equatable, Sendable {
    /// Follows the system appearance: light → white, dark → black.
    case system
    case white
    case black

    /// The concrete page colour: a system page resolves against `isDark`, an
    /// explicit choice is itself.
    public func resolved(isDark: Bool) -> BoardBackground {
        switch self {
        case .system: isDark ? .black : .white
        case .white: .white
        case .black: .black
        }
    }

    /// The colour this background paints with `isDark` as the appearance.
    public func cgColor(isDark: Bool) -> CGColor {
        resolved(isDark: isDark).cgColor
    }

    /// The explicit colour of a white or black page. A `.system` page has no
    /// colour of its own: production callers pass the appearance through
    /// `cgColor(isDark:)`; this parameterless form resolves `.system` as white
    /// (light mode) only so explicit-choice call sites keep compiling.
    public var cgColor: CGColor {
        switch self {
        case .system, .white: CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1)
        case .black: CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 1)
        }
    }

    public var displayName: String {
        switch self {
        case .system: "Follow the system"
        case .white: "White"
        case .black: "Black"
        }
    }

    public var toggled: BoardBackground {
        self == .white ? .black : .white
    }

    /// A solid, opaque image at display pixel size: the base a page's capture
    /// composes over, so a whiteboard capture is never transparent and never
    /// shows the desktop hidden behind the board. A `.system` page resolves
    /// against `isDark` at capture time, so the result is always concrete.
    public func captureBase(width: Int, height: Int, isDark: Bool) -> CGImage? {
        resolved(isDark: isDark).captureBase(width: width, height: height)
    }

    /// The explicit-choice form of the capture base; `.system` resolves as
    /// white (light mode). See `cgColor` for why this form exists.
    public func captureBase(width: Int, height: Int) -> CGImage? {
        guard width >= 1, height >= 1,
              let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(
                data: nil,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: 0,
                space: space,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              ) else { return nil }
        context.setFillColor(cgColor)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage()
    }
}

/// One whiteboard page: its own marks (own `DrawingSession`, so undo, redo and
/// the numbered sequence restart per page), its own background colour and its
/// own pan offset over the endless canvas.
///
/// Stroke points are stored in **page space** (top-left origin, the same
/// `CoordinateMapping` conventions the overlay uses): `viewPoint = pagePoint -
/// offset`. Changing the display or the window size never moves existing marks.
public struct BoardPage: Equatable, Sendable {
    public var session: DrawingSession
    public var background: BoardBackground
    /// How far the page origin sits from the display's top-left corner.
    public var offset: CGSize

    public init(
        session: DrawingSession = DrawingSession(),
        background: BoardBackground = .white,
        offset: CGSize = .zero
    ) {
        self.session = session
        self.background = background
        self.offset = offset
    }
}

/// Per display: the ordered pages of one whiteboard, plus which one is
/// presented. A class on purpose — the overlay and the view share the same
/// instance, so every mutation lands in one place and closing the board keeps
/// the pages alive without any write-back sync.
public final class WhiteboardPages {
    public private(set) var pages: [BoardPage]
    public private(set) var currentIndex: Int

    /// Starts with a single page on the given background. The default stays
    /// `.white` here; the controller passes the page-colour preference so a
    /// fresh board starts on the user's choice (system by default).
    public init(background: BoardBackground = .white) {
        pages = [BoardPage(background: background)]
        currentIndex = 0
    }

    public var count: Int { pages.count }
    public var currentPage: BoardPage { pages[currentIndex] }

    /// The live session of the view is authoritative while its page is
    /// presented: the view hands it back here after every change and when the
    /// page or the panel changes, so the page keeps its marks.
    public func adopt(_ session: DrawingSession) {
        pages[currentIndex].session = session
    }

    /// › — moves on, or creates a new page past the last one inheriting the
    /// current page's background. Returns whether a page was created.
    @discardableResult
    public func selectNext() -> Bool {
        if currentIndex == pages.count - 1 {
            let inherited = pages[currentIndex].background
            pages.append(BoardPage(background: inherited))
            currentIndex += 1
            return true
        }
        currentIndex += 1
        return false
    }

    /// ‹ — moves back one page. At the first page it stays put and returns
    /// false: nothing is created behind the user. Returns whether it moved.
    @discardableResult
    public func selectPrevious() -> Bool {
        guard currentIndex > 0 else { return false }
        currentIndex -= 1
        return true
    }

    /// Moves to the page at `index`. A valid index is always accepted (even the
    /// already-presented one) and `currentIndex` then names it; anything out of
    /// range is refused and the board is left exactly as it was. Returns
    /// whether the board presents the requested page.
    @discardableResult
    public func select(index: Int) -> Bool {
        guard index >= 0, index < pages.count else { return false }
        currentIndex = index
        return true
    }

    /// ⌘⌫ — deletes the current page. The board can never go empty, so with a
    /// single page the delete is refused and nothing changes; callers disable
    /// the affordance for that case. Returns whether a page was deleted.
    @discardableResult
    public func deleteCurrentPage() -> Bool {
        guard pages.count > 1 else { return false }
        pages.remove(at: currentIndex)
        // Deleting the last page pulls the index back into range; deleting any
        // other page hands the slot to the page that followed it.
        if currentIndex == pages.count { currentIndex -= 1 }
        return true
    }

    /// ⌥← — swaps the current page with the one before it. At the first page
    /// there is nothing to the left, so it is refused and nothing changes.
    /// Returns whether the page moved. The page itself (marks, background,
    /// offset, identity) stays exactly what it was and remains current.
    @discardableResult
    public func moveCurrentPageLeft() -> Bool {
        guard currentIndex > 0 else { return false }
        pages.swapAt(currentIndex, currentIndex - 1)
        currentIndex -= 1
        return true
    }

    /// ⌥→ — swaps the current page with the one after it. At the last page
    /// there is nothing to the right, so it is refused. Returns whether the
    /// page moved.
    @discardableResult
    public func moveCurrentPageRight() -> Bool {
        guard currentIndex < pages.count - 1 else { return false }
        pages.swapAt(currentIndex, currentIndex + 1)
        currentIndex += 1
        return true
    }

    /// ⌘B — flips only the current page between white and black. A page that
    /// follows the system resolves against `isDark` first, so the flip starts
    /// from the colour the user actually sees and lands on the opposite
    /// explicit choice; an explicit page just flips.
    public func toggleBackground(isDark: Bool = false) {
        pages[currentIndex].background = pages[currentIndex].background.resolved(isDark: isDark).toggled
    }

    /// Shifts the current page's pan offset. `pan` adds to the offset: after
    /// `pan(by: d)` a point drawn on screen moves by `-d`.
    public func pan(by delta: CGSize) {
        let offset = pages[currentIndex].offset
        pages[currentIndex].offset = CGSize(width: offset.width + delta.width, height: offset.height + delta.height)
    }

    /// Sets the current page's pan offset outright, used by tests and panning resets.
    public func setOffset(_ offset: CGSize) {
        pages[currentIndex].offset = offset
    }
}
