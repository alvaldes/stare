import CoreGraphics

/// Where the pointer keeps the arrow over a capture card (B9).
///
/// The drawing layer sets a crosshair for a whole display, and a card's own
/// tracking area never wins against that: the pointer over a card kept the
/// crosshair and the card read as part of the surface to draw on. The rule is
/// one comparison over the cards that are on screen, so it lives here — pure,
/// and pinned — instead of inline in the controller where nothing can test it.
///
/// Frames are screen coordinates, the same space `NSEvent.mouseLocation` uses.
public enum CardCursor {
    /// Whether `pointer` sits inside any of the cards on screen.
    public static func isOverCard(_ pointer: CGPoint, cardFrames: [CGRect]) -> Bool {
        cardFrames.contains { $0.contains(pointer) }
    }
}
