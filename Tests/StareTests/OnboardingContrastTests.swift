import AppKit
import XCTest
@testable import Stare

/// Spec S5 of the Setup Guide redesign asks for WCAG AA contrast, and the copy
/// the guide renders with `OnboardingView.supportingLabel` is small text
/// (12–13 pt), so it needs 4.5:1 against what it sits on: the window background
/// for the header line and "Not now", the card's control background for the
/// status detail.
///
/// This measures the real semantic colour rather than a copy of it. macOS's
/// `secondaryLabelColor` is a 50 % label in light mode — 3.95:1, short of AA —
/// which is exactly the trap this test exists to catch: a colour that looks
/// right in dark mode (5.89:1 there) can still fail in light.
final class OnboardingContrastTests: XCTestCase {
    /// WCAG AA for text under 18 pt (or under 14 pt bold).
    private static let minimumRatio = 4.5

    /// Both appearances, because the guide ships in both and only one of them
    /// used to fall short.
    private static let appearances: [(name: NSAppearance.Name, label: String)] = [
        (.aqua, "light"),
        (.darkAqua, "dark"),
    ]

    /// The backgrounds the supporting copy is drawn on.
    private static let backgrounds: [(color: NSColor, label: String)] = [
        (.windowBackgroundColor, "window"),
        (.controlBackgroundColor, "card"),
    ]

    func testSupportingCopyMeetsWCAGAAContrast() {
        for appearance in Self.appearances {
            for background in Self.backgrounds {
                let ratio = Self.contrastRatio(
                    of: OnboardingView.supportingLabel,
                    on: background.color,
                    in: appearance.name
                )
                XCTAssertGreaterThanOrEqual(
                    ratio,
                    Self.minimumRatio,
                    "supporting copy on the \(background.label) background in \(appearance.label) mode must reach \(Self.minimumRatio):1, measured \(String(format: "%.2f", ratio)):1"
                )
            }
        }
    }

    /// A sanity check on the measurement itself: the label colour the guide's
    /// supporting copy is derived from must clear the bar comfortably, so a
    /// future edit that dims the copy cannot pass by breaking the maths too.
    func testTheMeasurementDistinguishesLabelFromAShortfall() {
        for appearance in Self.appearances {
            let label = Self.contrastRatio(of: .labelColor, on: .windowBackgroundColor, in: appearance.name)
            let secondary = Self.contrastRatio(of: .secondaryLabelColor, on: .windowBackgroundColor, in: appearance.name)
            XCTAssertGreaterThan(label, Self.minimumRatio * 2, "\(appearance.label): the label colour is far above AA")
            XCTAssertLessThan(secondary, label, "\(appearance.label): a dimmer colour measures dimmer")
        }
    }

    // MARK: Measurement

    /// WCAG 2.1 contrast ratio between `foreground` composited over
    /// `background` and `background` itself.
    private static func contrastRatio(
        of foreground: NSColor,
        on background: NSColor,
        in appearance: NSAppearance.Name
    ) -> Double {
        let resolved = NSAppearance(named: appearance) ?? NSAppearance(named: .aqua)!
        var foregroundRGBA = (r: 0.0, g: 0.0, b: 0.0, a: 1.0)
        var backgroundRGB = (r: 0.0, g: 0.0, b: 0.0)
        resolved.performAsCurrentDrawingAppearance {
            let fg = foreground.usingColorSpace(.sRGB) ?? .black
            let bg = background.usingColorSpace(.sRGB) ?? .white
            foregroundRGBA = (
                Double(fg.redComponent),
                Double(fg.greenComponent),
                Double(fg.blueComponent),
                Double(fg.alphaComponent)
            )
            backgroundRGB = (
                Double(bg.redComponent),
                Double(bg.greenComponent),
                Double(bg.blueComponent)
            )
        }

        // A semantic colour carries the label's own alpha, so it only becomes a
        // pixel once composited over what it sits on.
        let composited = (
            r: foregroundRGBA.r * foregroundRGBA.a + backgroundRGB.r * (1 - foregroundRGBA.a),
            g: foregroundRGBA.g * foregroundRGBA.a + backgroundRGB.g * (1 - foregroundRGBA.a),
            b: foregroundRGBA.b * foregroundRGBA.a + backgroundRGB.b * (1 - foregroundRGBA.a)
        )

        let (lighter, darker) = luminance(composited) > luminance(backgroundRGB)
            ? (luminance(composited), luminance(backgroundRGB))
            : (luminance(backgroundRGB), luminance(composited))
        return (lighter + 0.05) / (darker + 0.05)
    }

    private static func luminance(_ rgb: (r: Double, g: Double, b: Double)) -> Double {
        func linear(_ channel: Double) -> Double {
            channel <= 0.03928 ? channel / 12.92 : pow((channel + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * linear(rgb.r) + 0.7152 * linear(rgb.g) + 0.0722 * linear(rgb.b)
    }
}
