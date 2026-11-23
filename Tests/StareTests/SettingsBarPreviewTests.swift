import SwiftUI
import AppKit
import XCTest

@testable import Stare
import StareCore

/// T1/S1 + T2/S2: the Settings bar preview. `syncToolbarPreview()` pins the
/// preview's own orientation to `.horizontal` (S1) and the stage scales the
/// real bar down to `cardsWidth - SettingsMetrics.stageChrome` instead of
/// scrolling it (S2), so a vertical bar or a minimum-width window still shows
/// every item. The assertions render the REAL `BarPane` — through
/// `SettingsView.pane(for:width:model:permission:)`, the same entry the
/// selftest's fixture render uses — into a hosting view in a real borderless
/// window of the fixed appearance and scan the pixels: the bar's band is the
/// rows carrying several saturated ink swatches, so the scan finds one
/// horizontal row of coloured items only when the preview really is the
/// horizontal whole bar.
@MainActor
final class SettingsBarPreviewTests: XCTestCase {

    /// An in-memory `PreferenceStore`, so the probe never touches the user's
    /// real preferences — the same isolation the organiser tests use.
    private final class InMemoryPreferenceStore: PreferenceStore {
        private var values: [String: Any] = [:]
        func object(forKey key: String) -> Any? { values[key] }
        func set(_ value: Any?, forKey key: String) { values[key] = value }
    }

    /// A permission client that answers without touching TCC: the probe is
    /// only there because the pane factory takes one.
    private struct StubScreenRecordingClient: ScreenRecordingClient {
        func preflight() -> Bool { true }
        func request() -> Bool { true }
        func canCapture() -> Bool { true }
        func openPrivacySettings() {}
    }

    // MARK: - The fit factor's chrome (T1/S4)

    /// S4: the stage's label and note sit in a row above the preview, so
    /// nothing stands to the left of the bar any more and the stage's
    /// horizontal chrome is only its own padding — exactly what the fit
    /// factor subtracts from the pane width to get the width available to
    /// the scaled bar. If the stage's tokens and the factor's chrome ever
    /// drift apart, the fit claim the pixel tests below pin silently breaks.
    func testStageChromeIsTheSumOfTheStageOwnTokens() {
        XCTAssertEqual(
            SettingsMetrics.stageChrome,
            SettingsMetrics.stagePadding * 2,
            "S4: the fit factor's chrome must be the stage's own horizontal padding — the label row costs no width"
        )
    }

    /// S4: with the label above the bar, the width the old 140-pt lead
    /// column took goes to the preview: at the minimum window width
    /// (cards 625) the bar's ink span fills the width the fit factor hands
    /// it — `cardsWidth - SettingsMetrics.stageChrome` — up to the same
    /// proportion of the bar's own extent the default width already shows.
    /// A lead column beside the bar (chrome 180 instead of 24) shrinks the
    /// available width and with it the span, so the probe fails if the
    /// label ever moves back beside the bar.
    func testTheMinimumWindowBarUsesTheWidthTheLeadColumnUsedToTake() throws {
        let runsAtDefault = try Self.inkRuns(in: Self.renderPane(cardsWidth: 766, orientation: .horizontal))
        let runsAtMinimum = try Self.inkRuns(in: Self.renderPane(cardsWidth: 625, orientation: .horizontal))

        let spanAtDefault = runsAtDefault.last!.center + runsAtDefault.last!.width / 2
            - (runsAtDefault.first!.center - runsAtDefault.first!.width / 2)
        let spanAtMinimum = runsAtMinimum.last!.center + runsAtMinimum.last!.width / 2
            - (runsAtMinimum.first!.center - runsAtMinimum.first!.width / 2)
        let availableAtDefault = 766.0 - SettingsMetrics.stageChrome
        let availableAtMinimum = 625.0 - SettingsMetrics.stageChrome

        // The bar never grows past its own extent, so the narrow pane's
        // span can at worst match the default span's share of a bigger
        // available width; a small antialias tolerance keeps the edge in.
        XCTAssertGreaterThanOrEqual(
            spanAtMinimum,
            spanAtDefault * availableAtMinimum / availableAtDefault - 2,
            "S4: at the minimum window width the bar must use all the width the stage's chrome leaves"
        )
        // The gain, pinned against the old layout: with the label beside the
        // bar (chrome 180: a 140-pt lead column, 16 pt of spacing and two
        // 12-pt paddings) the same item set rendered 298.5 pt at cards 625.
        // A floor no lead-column geometry can reach, so the label ever
        // moving back beside the bar fails here instead of silently
        // shrinking the preview.
        XCTAssertGreaterThan(
            spanAtMinimum, 330,
            "S4: the bar at the minimum window width must be wider than the 298.5 pt the old lead-column layout gave it"
        )
    }

    // MARK: - The preview stays horizontal (T1/S1)

    /// S1: the bar pane's model is vertical, the preview must still render
    /// the horizontal bar — the same ink-run layout a horizontal model
    /// renders. Pre-fix the model's orientation reached the preview and the
    /// bar rendered as a vertical column, scattering the swatches down the
    /// pane so no row carried several of them.
    func testThePreviewRendersHorizontalWhateverTheBarOrientationIs() throws {
        let horizontal = try Self.renderPane(cardsWidth: 766, orientation: .horizontal)
        let vertical = try Self.renderPane(cardsWidth: 766, orientation: .vertical)

        let horizontalRuns = try Self.inkRuns(in: horizontal)
        let verticalRuns = try Self.inkRuns(in: vertical)

        XCTAssertEqual(
            verticalRuns.count, horizontalRuns.count,
            "S1: a vertical model's preview lays the coloured items out on the same row as a horizontal one")
        for (verticalRun, horizontalRun) in zip(verticalRuns, horizontalRuns) {
            XCTAssertLessThanOrEqual(
                abs(verticalRun.center - horizontalRun.center), 2,
                "S1: the vertical model's preview must sit the coloured items where the horizontal one does")
            XCTAssertLessThanOrEqual(
                abs(verticalRun.width - horizontalRun.width), 2,
                "S1: the vertical model's preview must draw the coloured items at the horizontal one's size")
        }
    }

    // MARK: - The whole bar inside the stage (T2/S2)

    /// S2: at the minimum window width (cards 625) the preview keeps every
    /// item. The rule is what the two widths have in common, not an exact
    /// total: how many runs the marked tool's accent fill splits into depends
    /// on the glyph drawn over it (`+2` was true at one scale, `+3` at the
    /// wider stage S4 produced), so the assertions are that the narrow width
    /// shows exactly what the default width shows, and that neither drops a
    /// saturated ink the bar carries (white and black read as grey, so the
    /// scan cannot see them). Pre-fix the stage scrolled instead of fitting
    /// and cut the bar's right end — the inks — off at the narrow width.
    func testTheMinimumWindowWidthKeepsEveryBarItem() throws {
        let runsAtDefault = try Self.inkRuns(in: Self.renderPane(cardsWidth: 766, orientation: .horizontal))
        let runsAtMinimum = try Self.inkRuns(in: Self.renderPane(cardsWidth: 625, orientation: .horizontal))

        XCTAssertGreaterThanOrEqual(
            runsAtDefault.count, Self.saturatedInks.count + 1,
            "S2: the default width shows every coloured item the bar carries, and the marked tool's accent with them")
        XCTAssertEqual(
            runsAtMinimum.count, runsAtDefault.count,
            "S2: at the minimum window width (cards 625) the preview still shows exactly what the default width does — the bar is fitted, not cut")
    }

    // MARK: - The render the assertions read (T1/S1, T2/S2)

    /// One rendered pane: the pane's pixel buffer and the scale it was drawn
    /// at, so run geometry reads back in points.
    struct RenderedPane {
        let scan: PixelScan
    }

    /// The pane at the given cards width and bar orientation, rendered in the
    /// light appearance through the same offscreen path the existing bar
    /// tests use: a hosting view at the pane's natural surface size
    /// (cards width plus the pane's own horizontal padding) inside a real
    /// on-screen borderless window, then `cacheDisplay`.
    @MainActor
    static func renderPane(cardsWidth: CGFloat, orientation: ToolbarOrientation) throws -> RenderedPane {
        let model = PreferencesModel(store: InMemoryPreferenceStore())
        model.toolbarTools = ToolbarToolLayout.standard
        model.toolbarOrientation = orientation
        let permission = PermissionProbe(
            permission: ScreenRecordingPermission(client: StubScreenRecordingClient())
        )
        let pane = SettingsView.pane(
            for: .bar,
            width: cardsWidth,
            model: model,
            permission: permission
        )
        let hosting = NSHostingView(rootView: pane)
        hosting.appearance = NSAppearance(named: NSAppearance.Name.aqua)
        let size = CGSize(width: cardsWidth + 2 * SettingsMetrics.panePadding, height: 620)
        hosting.frame = CGRect(origin: .zero, size: size)
        hosting.layoutSubtreeIfNeeded()

        let window = NSWindow(
            contentRect: CGRect(origin: .zero, size: size),
            styleMask: [.borderless], backing: .buffered, defer: false
        )
        window.contentView = hosting
        window.appearance = NSAppearance(named: NSAppearance.Name.aqua)
        window.orderFrontRegardless()
        // The preference keys the stage's fit factor reads settle on this
        // run-loop hop, exactly the settle time the other render tests use.
        RunLoop.current.run(until: Date().addingTimeInterval(0.35))
        let representation = try XCTUnwrap(hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds))
        hosting.cacheDisplay(in: hosting.bounds, to: representation)
        window.orderOut(nil)

        let image = try XCTUnwrap(representation.cgImage)
        let width = image.width, height = image.height
        let context = try XCTUnwrap(
            CGContext(
                data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )
        )
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        let buffer = try XCTUnwrap(context.data)
        let pointer = buffer.bindMemory(to: UInt8.self, capacity: width * height * 4)
        let data = Array(UnsafeBufferPointer(start: pointer, count: width * height * 4))
        return RenderedPane(
            scan: PixelScan(
                scale: CGFloat(width) / size.width, width: width, height: height, data: data
            )
        )
    }

    /// The ink swatch widths the assertions compare.
    struct InkRun {
        let center: CGFloat
        let width: CGFloat
    }

    /// The ink colours the scan can see: everything past the saturation
    /// threshold. White and black are unsaturated — they read as grey on the
    /// bar — so only the marked tool's accent fill and the coloured inks
    /// surface as runs.
    static var saturatedInks: [Ink] {
        Ink.allCases.filter { ink in
            let rgb = ink.rgb
            let max = Swift.max(rgb.red, rgb.green, rgb.blue)
            let min = Swift.min(rgb.red, rgb.green, rgb.blue)
            return (max - min) * 255 >= 96
        }
    }

    /// A saturated pixel: opaque and colourful enough to be ink or an accent
    /// fill — the bar's neutral glyphs, material and text all sit below it.
    /// On the pane only the bar carries many of these on one row, which is
    /// what identifies the bar's band.
    static func saturated(_ rgb: (r: UInt8, g: UInt8, b: UInt8, a: UInt8)) -> Bool {
        guard rgb.a > 128 else { return false }
        let max = Swift.max(rgb.r, rgb.g, rgb.b)
        let min = Swift.min(rgb.r, rgb.g, rgb.b)
        return Int(max) - Int(min) >= 96
    }

    /// The coloured runs on the bar's row, in points, left to right.
    ///
    /// The bar's band is found before anything is asserted: the rows whose
    /// horizontal saturated-run count is at least four (the bar's row carries
    /// the marked tool's accent plus the saturated inks; no cards row comes
    /// close). The widest such contiguous band is the bar, and the row in it
    /// with the most saturated pixels is the swatches' full circle, whose
    /// merged runs are the answer. A gap of at most two pixels stays inside
    /// one run (the swatch's antialiased edge), anything wider separates
    /// items.
    static func inkRuns(in render: RenderedPane) throws -> [InkRun] {
        let scan = render.scan
        let minimumRunsPerRow = 4

        // The candidate rows and their runs, one sweep over the pixels.
        var candidates: [(y: Int, runs: [(start: Int, end: Int)], count: Int)] = []
        for y in 0..<scan.height {
            var runs: [(start: Int, end: Int)] = []
            var current: (start: Int, end: Int)?
            var lastSaturatedX = -10
            var x = 0
            while x < scan.width {
                if saturated(scan.rgb(x: x, y: y)) {
                    if var run = current {
                        if x - lastSaturatedX <= 2 {
                            run.end = x
                            current = run
                        } else {
                            runs.append(run)
                            current = (x, x)
                        }
                    } else {
                        current = (x, x)
                    }
                    lastSaturatedX = x
                }
                x += 1
            }
            if let run = current { runs.append(run) }
            let real = runs.filter { $0.end - $0.start >= 2 }
            if real.count >= minimumRunsPerRow {
                candidates.append((y, real, real.reduce(0) { $0 + ($1.end - $1.start + 1) }))
            }
        }

        // No row carries several coloured items: the bar never rendered a
        // horizontal row of inks — the failure S1 pins.
        guard !candidates.isEmpty else {
            XCTFail(
                "no row of the pane carries several coloured items — the bar's band is missing"
            )
            return []
        }

        // The band: contiguous candidate rows, taken as the largest group;
        // inside it the row carrying the most saturated pixels is the
        // swatches' full circle, whose runs are the answer.
        var bands: [[(y: Int, runs: [(start: Int, end: Int)], count: Int)]] = []
        for candidate in candidates {
            if var last = bands.last, last[last.count - 1].y == candidate.y - 1 {
                last.append(candidate)
                bands[bands.count - 1] = last
            } else {
                bands.append([candidate])
            }
        }
        let band = bands.max { $0.count < $1.count } ?? bands[0]
        let row = band.max { $0.count < $1.count } ?? band[0]

        let scale = scan.scale
        return row.runs.map {
            InkRun(
                center: (CGFloat($0.start + $0.end) / 2) / scale,
                width: CGFloat($0.end - $0.start + 1) / scale
            )
        }
    }

}

/// The pane's pixels: an sRGB RGBA8 buffer with the render's scale, so reads
/// do not depend on the bitmap rep's own colour space.
struct PixelScan {
    let scale: CGFloat
    let width: Int
    let height: Int
    let data: [UInt8]

    func rgb(x: Int, y: Int) -> (r: UInt8, g: UInt8, b: UInt8, a: UInt8) {
        let i = (y * width + x) * 4
        return (data[i], data[i + 1], data[i + 2], data[i + 3])
    }
}
