import Foundation
import XCTest
@testable import StareCore

final class PointerStyleTests: XCTestCase {
    // MARK: Defaults

    func testStandardMatchesTodayDefaults() {
        XCTAssertEqual(
            PointerStyle.standard,
            PointerStyle(
                preset: .squircle,
                size: 72,
                colorSource: .ink,
                bandWidth: 0.26,
                glowIntensity: 1,
                fadeWhenIdle: true
            )
        )
    }

    // MARK: Clamping

    func testInitClampsSizeBandWidthAndGlowIntensityFromAbove() {
        let style = PointerStyle(size: 200, bandWidth: 2, glowIntensity: -3)
        XCTAssertEqual(style.size, 80)
        XCTAssertEqual(style.bandWidth, 0.5)
        XCTAssertEqual(style.glowIntensity, 0)
    }

    func testInitClampsSizeBandWidthAndGlowIntensityFromBelow() {
        let style = PointerStyle(size: 10, bandWidth: 0.01, glowIntensity: 5)
        XCTAssertEqual(style.size, 32)
        XCTAssertEqual(style.bandWidth, 0.08)
        XCTAssertEqual(style.glowIntensity, 1)
    }

    func testDirectMutationClampsToo() {
        var style = PointerStyle.standard
        style.size = 500
        style.bandWidth = -1
        style.glowIntensity = 42
        XCTAssertEqual(style.size, 80)
        XCTAssertEqual(style.bandWidth, 0.08)
        XCTAssertEqual(style.glowIntensity, 1)
    }

    // MARK: Lenient decoding

    func testUnknownPresetStringDecodesToRing() throws {
        let data = Data(#"{"preset":"banana"}"#.utf8)
        let style = try JSONDecoder().decode(PointerStyle.self, from: data)
        XCTAssertEqual(style.preset, .ring)
    }

    func testMissingKeysTakeDefaults() throws {
        let style = try JSONDecoder().decode(PointerStyle.self, from: Data("{}".utf8))
        // Preset falls back to ring per the lenient decoding rule; the numeric
        // and boolean defaults match `standard`.
        XCTAssertEqual(style.preset, .ring)
        XCTAssertEqual(style.size, 72)
        XCTAssertEqual(style.bandWidth, 0.26)
        XCTAssertEqual(style.glowIntensity, 1)
        XCTAssertTrue(style.fadeWhenIdle)
        XCTAssertEqual(style.colorSource, .ink)
    }

    func testOutOfRangeNumbersClampWhenDecoded() throws {
        let data = Data(#"{"size":999,"bandWidth":0.001,"glowIntensity":7}"#.utf8)
        let style = try JSONDecoder().decode(PointerStyle.self, from: data)
        XCTAssertEqual(style.size, 80)
        XCTAssertEqual(style.bandWidth, 0.08)
        XCTAssertEqual(style.glowIntensity, 1)
    }

    // MARK: Codable round trip

    func testFixedColorSourceRoundTrips() throws {
        var style = PointerStyle.standard
        style.colorSource = .fixed(.blue)
        let decoded = try JSONDecoder().decode(
            PointerStyle.self, from: JSONEncoder().encode(style)
        )
        XCTAssertEqual(decoded, style)
        XCTAssertEqual(decoded.colorSource, .fixed(.blue))
    }

    func testInkColorSourceRoundTrips() throws {
        let decoded = try JSONDecoder().decode(
            PointerStyle.self, from: JSONEncoder().encode(PointerStyle.standard)
        )
        XCTAssertEqual(decoded, PointerStyle.standard)
    }

    func testEveryPresetRoundTrips() throws {
        for preset in PointerStylePreset.allCases {
            var style = PointerStyle.standard
            style.preset = preset
            let decoded = try JSONDecoder().decode(
                PointerStyle.self, from: JSONEncoder().encode(style)
            )
            XCTAssertEqual(decoded.preset, preset)
        }
    }

    // MARK: Appearance projection

    func testAppearanceResolvesInkSourceToThePassedInk() {
        let appearance = PointerStyle.standard.appearance(ink: .green)
        XCTAssertEqual(appearance.ink, .green)
    }

    func testAppearanceResolvesFixedSourceToItsOwnInk() {
        var style = PointerStyle.standard
        style.colorSource = .fixed(.blue)
        let appearance = style.appearance(ink: .green)
        XCTAssertEqual(appearance.ink, .blue)
    }

    /// Ring with today's values must reproduce the geometry
    /// `OverlayView.drawCursorFrame` draws today, so the current look cannot
    /// drift when the overlay switches to this projection.
    func testRingAppearanceWithTodayDefaultsReproducesTodayGeometry() {
        var style = PointerStyle.standard
        style.preset = .ring
        let appearance = style.appearance(ink: .red)
        XCTAssertEqual(appearance.radius, 36)
        XCTAssertEqual(appearance.bandWidth, 0.26)
        XCTAssertEqual(appearance.edgeWidth, 2)
        XCTAssertNil(appearance.cornerRadiusFactor)
        XCTAssertEqual(appearance.geometry, .ring)
        XCTAssertEqual(appearance.glowExtent, 1.9)
        XCTAssertEqual(appearance.glowStops.count, 3)
        XCTAssertEqual(appearance.glowStops[0].location, 0)
        XCTAssertEqual(appearance.glowStops[0].alpha, 0.26)
        XCTAssertEqual(appearance.glowStops[1].location, 0.55)
        XCTAssertEqual(appearance.glowStops[1].alpha, 0.10)
        XCTAssertEqual(appearance.glowStops[2].location, 1)
        XCTAssertEqual(appearance.glowStops[2].alpha, 0)
    }

    func testSquircleAppearanceCarriesTodayCornerFactor() {
        let appearance = PointerStyle.standard.appearance(ink: .red)
        XCTAssertEqual(appearance.cornerRadiusFactor, 0.62)
        XCTAssertEqual(appearance.geometry, .squircle)
        XCTAssertEqual(appearance.edgeWidth, 2)
        XCTAssertEqual(appearance.bandWidth, 0.26)
    }

    func testDotIsAFilledDiscWithNoBandOrEdge() {
        var style = PointerStyle.standard
        style.preset = .dot
        let appearance = style.appearance(ink: .red)
        XCTAssertEqual(appearance.geometry, .dot)
        XCTAssertEqual(appearance.bandWidth, 0)
        XCTAssertEqual(appearance.edgeWidth, 0)
        XCTAssertEqual(appearance.radius, 36)
    }

    func testMarkerTipBandEqualsItsWidth() {
        var style = PointerStyle.standard
        style.preset = .markerTip
        let appearance = style.appearance(ink: .red)
        XCTAssertEqual(appearance.geometry, .markerTip)
        // The chisel tip is filled edge to edge: the band is the full width,
        // i.e. twice the radius.
        XCTAssertEqual(appearance.bandWidth, 2)
        XCTAssertEqual(appearance.edgeWidth, 0)
    }

    func testSpotlightHasNoHardEdge() {
        var style = PointerStyle.standard
        style.preset = .spotlight
        let appearance = style.appearance(ink: .red)
        XCTAssertEqual(appearance.geometry, .spotlight)
        XCTAssertEqual(appearance.bandWidth, 0)
        XCTAssertEqual(appearance.edgeWidth, 0)
        XCTAssertFalse(appearance.glowStops.isEmpty)
    }

    func testGlowIntensityScalesTheStops() {
        var style = PointerStyle.standard
        style.glowIntensity = 0.5
        let appearance = style.appearance(ink: .red)
        XCTAssertEqual(appearance.glowStops[0].alpha, 0.13, accuracy: 0.0001)
        XCTAssertEqual(appearance.glowStops[1].alpha, 0.05, accuracy: 0.0001)
        XCTAssertEqual(appearance.glowStops[2].alpha, 0)
    }

    func testGlowIntensityZeroMeansGlowOff() {
        var style = PointerStyle.standard
        style.glowIntensity = 0
        let appearance = style.appearance(ink: .red)
        XCTAssertTrue(appearance.glowStops.isEmpty)
    }

    // MARK: Preset titles

    func testPresetTitlesAreEnglishAndDistinct() {
        let titles = PointerStylePreset.allCases.map(\.title)
        XCTAssertEqual(Set(titles).count, titles.count)
    }
}
