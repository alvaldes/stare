import Foundation
import XCTest
@testable import StareCore

final class PointerStyleTests: XCTestCase {
    /// The 72 pt / 0.26 band geometry the renderer's projection was verified
    /// against. Explicit, so the geometry tests pin the maths rather than the
    /// factory default — which v0.4/S9 moved to the owner's own look.
    private static func geometryStyle(_ preset: PointerStylePreset) -> PointerStyle {
        PointerStyle(preset: preset, size: 72, colorSource: .ink, bandWidth: 0.26)
    }

    // MARK: Defaults

    /// v0.4/S9: the factory look is the owner's own Pointer Highlight setup,
    /// so a fresh install opens on it. Changing any of these is a product
    /// decision, not a refactor.
    func testStandardIsTheOwnersLook() {
        XCTAssertEqual(
            PointerStyle.standard,
            PointerStyle(
                preset: .rhombus,
                size: 100,
                colorSource: .fixed(.purple),
                bandWidth: 0.1,
                glowIntensity: 1,
                fadeWhenIdle: true,
                borderStyle: .dashed
            )
        )
        XCTAssertEqual(PointerStyle.standard.borderStyle, .dashed)
        XCTAssertEqual(PointerStyle.standard.size, PointerStyle.defaultSize)
        XCTAssertEqual(PointerStyle.standard.bandWidth, PointerStyle.defaultBandWidth)
    }

    // MARK: Clamping

    func testInitClampsSizeBandWidthAndGlowIntensityFromAbove() {
        let style = PointerStyle(size: 300, bandWidth: 2, glowIntensity: -3)
        XCTAssertEqual(style.size, 240)
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
        XCTAssertEqual(style.size, 240)
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
        XCTAssertEqual(style.size, 100)
        XCTAssertEqual(style.bandWidth, 0.1)
        XCTAssertEqual(style.glowIntensity, 1)
        XCTAssertTrue(style.fadeWhenIdle)
        XCTAssertEqual(style.colorSource, .ink, "decoding falls back to ink, not to the factory look")
    }

    func testOutOfRangeNumbersClampWhenDecoded() throws {
        let data = Data(#"{"size":999,"bandWidth":0.001,"glowIntensity":7}"#.utf8)
        let style = try JSONDecoder().decode(PointerStyle.self, from: data)
        XCTAssertEqual(style.size, 240)
        XCTAssertEqual(style.bandWidth, 0.08)
        XCTAssertEqual(style.glowIntensity, 1)
    }

    // MARK: Size ceiling (T14 rework)

    func testSizeRangeStretchesTo240AndKeepsTheDefault() {
        XCTAssertEqual(PointerStyle.sizeRange, 32...240)
        XCTAssertEqual(PointerStyle.defaultSize, 100)
        XCTAssertEqual(PointerStyle(size: 240).size, 240)
    }

    /// Legacy values above the old 80 pt ceiling survive both paths that
    /// produce a style instead of being clamped down.
    func testLegacySizesAboveTheOldCeilingSurvive() {
        XCTAssertEqual(PointerStyle(size: 120).size, 120)
        var style = PointerStyle.standard
        style.size = 120
        XCTAssertEqual(style.size, 120)
    }

    func testALegacyEncodedSizeOf120SurvivesDecoding() throws {
        let data = Data(#"{"preset":"ring","size":120}"#.utf8)
        let style = try JSONDecoder().decode(PointerStyle.self, from: data)
        XCTAssertEqual(style.size, 120)
    }

    // MARK: Codable round trip

    func testFixedColorSourceRoundTrips() throws {
        var style = PointerStyle(colorSource: .ink)
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

    // MARK: - New fields (T14/S9)

    func testNewFieldsDefaultToDashedScaleAndFullOpacity() {
        XCTAssertEqual(PointerStyle.standard.borderStyle, .dashed)
        XCTAssertEqual(PointerStyle.standard.clickAnimation, .scale)
        XCTAssertEqual(PointerStyle.standard.opacity, 1)
        let style = PointerStyle(preset: .dot, size: 50, opacity: 0.6)
        XCTAssertEqual(style.borderStyle, .dashed)
        XCTAssertEqual(style.clickAnimation, .scale)
        XCTAssertEqual(style.opacity, 0.6)
        XCTAssertEqual(style.preset, .dot)
    }

    func testOpacityClampsIntoItsRangeInitAndMutation() {
        XCTAssertEqual(PointerStyle(opacity: 0).opacity, PointerStyle.opacityRange.lowerBound)
        XCTAssertEqual(PointerStyle(opacity: 2).opacity, PointerStyle.opacityRange.upperBound)
        var style = PointerStyle.standard
        style.opacity = 0.1
        XCTAssertEqual(style.opacity, PointerStyle.opacityRange.lowerBound)
        style.opacity = 5
        XCTAssertEqual(style.opacity, 1)
    }

    func testDashedAndRotateRoundTripThroughTheBlob() throws {
        var style = PointerStyle.standard
        style.borderStyle = .dashed
        style.clickAnimation = .rotate
        style.opacity = 0.6
        let decoded = try JSONDecoder().decode(
            PointerStyle.self, from: JSONEncoder().encode(style)
        )
        XCTAssertEqual(decoded, style)
    }

    func testUnknownBorderAndClickValuesFallBackToTheDefaults() throws {
        let data = Data(
            (#"{"preset":"ring","size":72,"colorSource":{"ink":true},"bandWidth":0.26,"glowIntensity":1,"fadeWhenIdle":true,"borderStyle":"wavy","clickAnimation":"spin","opacity":0.5}"#).utf8
        )
        let style = try JSONDecoder().decode(PointerStyle.self, from: data)
        XCTAssertEqual(style.preset, .ring)
        XCTAssertEqual(style.borderStyle, .solid)
        XCTAssertEqual(style.clickAnimation, .scale)
        XCTAssertEqual(style.opacity, 0.5)
    }

    func testBlobWrittenBeforeThisTaskStillDecodesWithTheNewDefaults() throws {
        let blob = (#"{"preset":"squircle","size":64,"colorSource":{"ink":true},"bandWidth":0.3,"glowIntensity":0.5,"fadeWhenIdle":false}"#)
        let style = try JSONDecoder().decode(PointerStyle.self, from: Data(blob.utf8))
        XCTAssertEqual(style.preset, .squircle)
        XCTAssertEqual(style.size, 64)
        XCTAssertEqual(style.bandWidth, 0.3)
        XCTAssertEqual(style.glowIntensity, 0.5)
        XCTAssertFalse(style.fadeWhenIdle)
        XCTAssertEqual(style.borderStyle, .solid)
        XCTAssertEqual(style.clickAnimation, .scale)
        XCTAssertEqual(style.opacity, 1)
    }

    // MARK: - Presets (T14 rework)

    /// The owner dropped the marker tip: the list ends up as ring, squircle,
    /// rhombus, dot and spotlight — five presets, no marker.
    func testPresetListEndsUpWithFivePresetsWithoutTheMarkerTip() {
        XCTAssertEqual(
            PointerStylePreset.allCases.map(\.title),
            ["Ring", "Squircle", "Rhombus", "Dot", "Spotlight"]
        )
    }

    /// A stored `"markerTip"` — written by an older build — decodes like any
    /// unknown preset: back to the ring.
    func testStoredMarkerTipDecodesToRing() throws {
        let data = Data(#"{"preset":"markerTip"}"#.utf8)
        let style = try JSONDecoder().decode(PointerStyle.self, from: data)
        XCTAssertEqual(style.preset, .ring)
    }

    // MARK: Rhombus

    func testRhombusIsABandedEdgeShapeLikeTheSquircle() {
        let appearance = Self.geometryStyle(.rhombus).appearance(ink: .red)
        XCTAssertEqual(appearance.geometry, .rhombus)
        XCTAssertEqual(appearance.bandWidth, 0.26)
        XCTAssertEqual(appearance.edgeWidth, 2)
        XCTAssertEqual(appearance.cornerRadiusFactor, PointerAppearance.squircleCornerFactor)
    }

    func testRhombusRoundTrips() throws {
        var style = PointerStyle.standard
        style.preset = .rhombus
        let decoded = try JSONDecoder().decode(
            PointerStyle.self, from: JSONEncoder().encode(style)
        )
        XCTAssertEqual(decoded, style)
        XCTAssertEqual(decoded.preset, .rhombus)
    }

    func testNewPresetAndBorderTitlesAreEnglishAndDistinct() {
        XCTAssertTrue(PointerStylePreset.allCases.contains(.rhombus))
        XCTAssertEqual(PointerStylePreset.rhombus.title, "Rhombus")
        XCTAssertEqual(PointerBorderStyle.allCases.map(\.title), ["Solid", "Dashed"])
        XCTAssertEqual(PointerClickAnimation.allCases.map(\.title), ["Scale", "Rotate"])
    }

    // MARK: Appearance projection

    func testAppearanceResolvesInkSourceToThePassedInk() {
        let appearance = PointerStyle(colorSource: .ink).appearance(ink: .green)
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
    func testRingAppearanceWithTheVerifiedGeometryReproducesIt() {
        let appearance = Self.geometryStyle(.ring).appearance(ink: .red)
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
        let appearance = Self.geometryStyle(.squircle).appearance(ink: .red)
        XCTAssertEqual(appearance.cornerRadiusFactor, 0.62)
        XCTAssertEqual(appearance.geometry, .squircle)
        XCTAssertEqual(appearance.edgeWidth, 2)
        XCTAssertEqual(appearance.bandWidth, 0.26)
    }

    func testDotIsAFilledDiscWithNoBandOrEdge() {
        let appearance = Self.geometryStyle(.dot).appearance(ink: .red)
        XCTAssertEqual(appearance.geometry, .dot)
        XCTAssertEqual(appearance.bandWidth, 0)
        XCTAssertEqual(appearance.edgeWidth, 0)
        XCTAssertEqual(appearance.radius, 36)
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
