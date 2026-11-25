import Foundation

/// How the bar groups its inks (L29, S10). A vertical bar is a column, and one
/// ink per row made the palette the tallest thing in the pill — eight rows of
/// 28 pt, 220 pt, 30 % of the column. Folding them two per row halves that. A
/// horizontal bar keeps its single row: there is room along the top and one row
/// is what the palette reads as.
///
/// The grouping is order-preserving on purpose. The inks are the digits 1
/// through 8, so a user who knows "the fourth is green" must keep finding green
/// in the same place after the fold: rows are taken from `Ink.allCases` in
/// order, and nothing is reordered, duplicated or dropped.
public enum InkGrid {
    /// The rows the inks are drawn in, `columns` inks per row, in the order they
    /// arrive. A count that does not divide evenly leaves its remainder in the
    /// last row rather than padding the palette with a hole.
    public static func rows(_ inks: [Ink] = Ink.allCases, columns: Int) -> [[Ink]] {
        let width = max(1, columns)
        return stride(from: 0, to: inks.count, by: width).map { start in
            Array(inks[start ..< min(start + width, inks.count)])
        }
    }
}
