import CoreGraphics
import Foundation

/// A whiteboard page's solid background. Only white and black by design: the
/// user picks per page and flips with ⌘B while on it; inks are never remapped,
/// so a mark colour that vanishes against the background is the user's call.
public enum BoardBackground: String, CaseIterable, Equatable, Sendable {
    case white
    case black

    public var cgColor: CGColor {
        switch self {
        case .white: CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1)
        case .black: CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 1)
        }
    }

    public var displayName: String {
        self == .white ? "White" : "Black"
    }

    public var toggled: BoardBackground {
        self == .white ? .black : .white
    }

    /// A solid, opaque image at display pixel size: the base a page's capture
    /// composes over, so a whiteboard capture is never transparent and never
    /// shows the desktop hidden behind the board.
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

    /// Starts with a single page on the given background.
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

    /// ⌘B — flips only the current page between white and black.
    public func toggleBackground() {
        pages[currentIndex].background = pages[currentIndex].background.toggled
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
