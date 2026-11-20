import CoreGraphics
import Foundation

/// Device-independent colour components, so the drawing model never depends on
/// a window, screen or colour space.
public struct RGB: Equatable, Sendable {
    public var red: CGFloat
    public var green: CGFloat
    public var blue: CGFloat

    public init(red: CGFloat, green: CGFloat, blue: CGFloat) {
        self.red = red
        self.green = green
        self.blue = blue
    }
}

public enum Ink: String, CaseIterable, Identifiable, Sendable {
    case red
    case orange
    case yellow
    case green
    case blue
    case purple
    case white
    case black

    public var id: String { rawValue }

    /// Digit that selects this ink while drawing, 1 through 8.
    public var number: Int {
        switch self {
        case .red: 1
        case .orange: 2
        case .yellow: 3
        case .green: 4
        case .blue: 5
        case .purple: 6
        case .white: 7
        case .black: 8
        }
    }

    public var displayName: String {
        switch self {
        case .red: "Red"
        case .orange: "Orange"
        case .yellow: "Yellow"
        case .green: "Green"
        case .blue: "Blue"
        case .purple: "Purple"
        case .white: "White"
        case .black: "Black"
        }
    }

    public var rgb: RGB {
        switch self {
        case .red: RGB(red: 1.00, green: 0.23, blue: 0.19)
        case .orange: RGB(red: 1.00, green: 0.58, blue: 0.00)
        case .yellow: RGB(red: 1.00, green: 0.80, blue: 0.00)
        case .green: RGB(red: 0.20, green: 0.78, blue: 0.35)
        case .blue: RGB(red: 0.00, green: 0.48, blue: 1.00)
        case .purple: RGB(red: 0.69, green: 0.32, blue: 0.87)
        case .white: RGB(red: 1.00, green: 1.00, blue: 1.00)
        case .black: RGB(red: 0.00, green: 0.00, blue: 0.00)
        }
    }

    public func cgColor(alpha: CGFloat = 1) -> CGColor {
        let components = rgb
        return CGColor(
            srgbRed: components.red,
            green: components.green,
            blue: components.blue,
            alpha: alpha
        )
    }

    public static func ink(forNumber number: Int) -> Ink? {
        allCases.first { $0.number == number }
    }
}
