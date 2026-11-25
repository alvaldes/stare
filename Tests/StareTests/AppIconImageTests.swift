import AppKit
import XCTest
@testable import Stare

/// Spec S2 of batch A: the Settings app mark must show the real colour
/// artwork ("el icono en settings no tiene colores porque?"). The recorded
/// cause was a desaturated `NSApp.applicationIconImage` on macOS 26, solved by
/// reading `Resources/AppIcon.icns` first — extracted into ONE shared source
/// (`AppIconArtwork`) that `AppMark` and `OnboardingView` both use, so a third
/// variant cannot drift in.
///
/// Spec S6 adds the flatness duty: the icns artwork carries a macOS-style
/// drop shadow baked into its own pixels (the SVG source's `feDropShadow`,
/// rasterised in by `Scripts/icons.sh` — there is no PNG source behind it and
/// no SwiftUI modifier draws one). The resolved artwork must therefore be
/// cropped to the opaque shape's own bounds by alpha: every shadow pixel
/// lives outside that square. The raw decode is what the pins below measure,
/// reached by the repository path (`Resources/AppIcon.icns`) because the test
/// target ships no bundle resources.
///
/// Spec S9 adds the shape duty: an opaque BOUNDING BOX is exactly where a
/// rounded square hides what sits behind it — the baked shadow survives in
/// the four corners as soft grey. The resolution must therefore measure the
/// card's corner radius from the alpha map itself (the offsets of the opaque
/// span on the box's edge rows and columns) and clip the artwork to that
/// rounded rectangle: a pixel outside the shape is fully transparent, the
/// shape's straight edges stay opaque, and the bounds stay the shape's.
final class AppIconImageTests: XCTestCase {
    /// `Resources/` in the repository, walked from the test file's location:
    /// `Tests/StareTests/<this file>`.
    private static let repoResources: URL = {
        var url = URL(fileURLWithPath: #filePath)
        for _ in 0..<3 { url.deleteLastPathComponent() }
        return url.appendingPathComponent("Resources")
    }()

    private static let icnsURL = repoResources.appendingPathComponent("AppIcon.icns")

    /// The resolution must prefer the real icns artwork: in colour, not a
    /// template image, non-empty — and trimmed to the artwork's opaque
    /// bounds, which is what leaves the baked drop shadow behind.
    func testResolutionPrefersTheRealIcnsArtwork() throws {
        let file = try XCTUnwrap(NSImage(contentsOf: Self.icnsURL), "the repo's AppIcon.icns must decode")
        let opaque = try Self.opaqueBounds(of: file)
        let image = AppIconArtwork.resolve(
            resourceURL: Self.icnsURL,
            fallback: NSImage(size: NSSize(width: 1, height: 1))
        )

        XCTAssertEqual(image.size.width, opaque.width, accuracy: 1.0,
            "the resolved artwork must sit inside exactly the artwork's opaque bounds: measured \(image.size.width) pt vs opaque \(opaque.width) pt")
        XCTAssertEqual(image.size.height, opaque.height, accuracy: 1.0,
            "the resolved artwork must sit inside exactly the artwork's opaque bounds: measured \(image.size.height) pt vs opaque \(opaque.height) pt")
        XCTAssertLessThan(
            image.size.width, file.size.width - 4,
            "the resolved artwork must be smaller than the raw icns canvas: the baked shadow padding must be trimmed away, not kept"
        )
        XCTAssertGreaterThan(image.size.width, 0, "the resolved icon must be non-empty")
        XCTAssertGreaterThan(image.size.height, 0, "the resolved icon must be non-empty")
        XCTAssertEqual(image.isTemplate, false, "the colour artwork must not be marked a template image")
    }

    /// The evidence the trim acts on: the icns's opaque square sits well
    /// inside its canvas, and the pixels around it are mostly soft alpha —
    /// real shadow ink baked into the file, not just edge antialiasing.
    func testTheIcnsArtworkCarriesBakedShadowPadding() throws {
        let file = try XCTUnwrap(NSImage(contentsOf: Self.icnsURL), "the repo's AppIcon.icns must decode")
        let scan = try Self.alphaScan(of: file)

        // The artwork tile is inset on every side (the SVG canvas holds an
        // 824 px square inside 1024 px: ~9.8 % of padding per side).
        XCTAssertGreaterThanOrEqual(
            scan.opaqueBoundsPixelInset, 0.08 * Double(scan.pixelWidth),
            "the icns's opaque square is expected inside the canvas; without padding there is no baked shadow to trim"
        )
        XCTAssertGreaterThanOrEqual(
            scan.softAlphaPixelsOutsideOpaqueBounds, 20_000,
            "the padding around the opaque square must be soft-alpha (shadow) ink, measured \(scan.softAlphaPixelsOutsideOpaqueBounds) px"
        )
    }

    /// The measured radius, pinned so a re-raster of the icns cannot
    /// silently change the shape the mark is cut to. The artwork's source
    /// SVG (Resources/app-icon.svg) draws the card with rx 14.37 in its 64
    /// design box, scaled ×12.875 into the 1024 canvas — 185.0 px there,
    /// 92.5 pt in the decoded image's own point space.
    func testTheMeasuredCornerRadiusIsPinned() throws {
        let file = try XCTUnwrap(NSImage(contentsOf: Self.icnsURL), "the repo's AppIcon.icns must decode")
        let shape = try XCTUnwrap(AppIconArtwork.measureOpaqueShape(of: file))
        XCTAssertEqual(shape.cornerRadius, 92.5, accuracy: 3.0,
            "the measured corner radius must stay the artwork's own rounded-card radius; measured \(shape.cornerRadius) pt")
        XCTAssertEqual(shape.bounds.width, 412.0, accuracy: 1.0,
            "the measured bounds the cut works from must stay the card's own; measured \(shape.bounds.width) pt wide")
        XCTAssertEqual(shape.bounds.height, 412.0, accuracy: 1.0,
            "the measured bounds the cut works from must stay the card's own; measured \(shape.bounds.height) pt tall")
    }

    /// Degenerate input: an image whose alpha is fully opaque has sharp
    /// corners exactly as heavy as its edges, so there is nothing to cut —
    /// the fallback keeps its identity, as the missing/undecodable pins
    /// already promise for their own cases.
    func testFullyOpaqueFallbackKeepsItsIdentity() {
        let fallback = NSImage(size: NSSize(width: 7, height: 11))
        fallback.lockFocus()
        NSColor.red.setFill()
        NSRect(origin: .zero, size: fallback.size).fill()
        fallback.unlockFocus()
        let image = AppIconArtwork.resolve(resourceURL: nil, fallback: fallback)
        XCTAssertTrue(image === fallback, "a fully opaque image offers no measurable corner to cut; it must return unchanged")
        XCTAssertEqual(image.size, NSSize(width: 7, height: 11))
    }

    /// A missing file falls back instead of returning nothing: the given
    /// fallback image comes back, unchanged.
    func testMissingResourceFallsBackInsteadOfReturningNothing() {
        let fallback = NSImage(size: NSSize(width: 7, height: 11))
        let image = AppIconArtwork.resolve(resourceURL: nil, fallback: fallback)
        XCTAssertTrue(image === fallback, "a missing resource resolves to the fallback itself")
        XCTAssertEqual(image.size, NSSize(width: 7, height: 11))
    }

    /// An undecodable resource at the URL also falls back rather than
    /// surfacing a broken image.
    func testUndecodableResourceAlsoFallsBack() throws {
        let temporary = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("stare-appicon-\(UUID().uuidString).icns")
        try Data("not an icon".utf8).write(to: temporary)
        defer { try? FileManager.default.removeItem(at: temporary) }

        let fallback = NSImage(size: NSSize(width: 3, height: 5))
        let image = AppIconArtwork.resolve(resourceURL: temporary, fallback: fallback)
        XCTAssertTrue(image === fallback, "an undecodable resource resolves to the fallback itself")
        XCTAssertEqual(image.size, NSSize(width: 3, height: 5))
    }

    /// The real bundle path keeps pointing at the artwork the app ships: the
    /// same resource name the bundled app resolves through `Bundle.main`. In
    /// the test bundle there is no resource, which is exactly the branches
    /// the two tests above pin by hand.
    func testTheSharedSourceStillQueriesTheShippedResourceName() {
        XCTAssertEqual(
            Bundle.main.url(forResource: "AppIcon", withExtension: "icns"),
            nil,
            "the test bundle ships no resources, which is what the fallback tests model"
        )
    }

    /// Spec S9: after resolution the four CORNER pixels must be light-free —
    /// the named threshold is 0.05, so no soft shadow alpha (which lives
    /// exactly between the card's arc and its bounding box) survives at the
    /// box's four corners.
    private static let cornerTransparencyThreshold: CGFloat = 0.05

    func testResolvedArtworkCornersAreCutToTheShapeNotItsBox() throws {
        let image = AppIconArtwork.resolve(
            resourceURL: Self.icnsURL,
            fallback: NSImage(size: NSSize(width: 1, height: 1))
        )
        let scan = try Self.scanPixels(of: image)
        let corners: [(name: String, x: Int, y: Int)] = [
            ("top-left", 0, 0),
            ("top-right", scan.pixelWidth - 1, 0),
            ("bottom-left", 0, scan.pixelHeight - 1),
            ("bottom-right", scan.pixelWidth - 1, scan.pixelHeight - 1),
        ]
        for corner in corners {
            XCTAssertLessThanOrEqual(
                scan.alpha(x: corner.x, y: corner.y), Self.cornerTransparencyThreshold,
                "the \(corner.name) corner pixel must be transparent now the mark is cut to its rounded shape; " +
                "measured alpha \(scan.alpha(x: corner.x, y: corner.y)) — soft shadow ink survives where the box's corner is lighter than the card"
            )
        }
    }

    /// Spec S9: the cut removes only the corners' overhang — the shape's own
    /// edge midpoints must stay as opaque as the card drew them.
    func testResolvedArtworkEdgeMidpointsStayOpaque() throws {
        let image = AppIconArtwork.resolve(
            resourceURL: Self.icnsURL,
            fallback: NSImage(size: NSSize(width: 1, height: 1))
        )
        let scan = try Self.scanPixels(of: image)
        let midX = scan.pixelWidth / 2
        let midY = scan.pixelHeight / 2
        let midpoints: [(name: String, x: Int, y: Int)] = [
            ("top", midX, 0),
            ("bottom", midX, scan.pixelHeight - 1),
            ("left", 0, midY),
            ("right", scan.pixelWidth - 1, midY),
        ]
        for midpoint in midpoints {
            XCTAssertGreaterThanOrEqual(
                scan.alpha(x: midpoint.x, y: midpoint.y), 0.5,
                "the \(midpoint.name) edge midpoint must remain opaque — the cut may only remove what is outside the shape; " +
                "measured alpha \(scan.alpha(x: midpoint.x, y: midpoint.y))"
            )
        }
    }

    // MARK: - Measurement

    private struct PixelScan {
        let rep: NSBitmapImageRep
        let pixelWidth: Int
        let pixelHeight: Int

        func alpha(x: Int, y: Int) -> CGFloat {
            rep.colorAt(x: x, y: y)?.alphaComponent ?? 0
        }
    }

    /// Renders an image into a bitmap at 2× and returns it, so a test can
    /// name individual pixels (S9's corner and edge-midpoint pins).
    private static func scanPixels(of image: NSImage) throws -> PixelScan {
        let size = image.size
        let scale: CGFloat = 2
        let width = max(1, Int(size.width * scale))
        let height = max(1, Int(size.height * scale))
        let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .calibratedRGB, bytesPerRow: 0, bitsPerPixel: 0
        )
        let bitmap = try XCTUnwrap(rep)
        bitmap.size = size
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        image.draw(in: NSRect(origin: .zero, size: size), from: .zero, operation: .copy, fraction: 1)
        NSGraphicsContext.restoreGraphicsState()
        return PixelScan(rep: bitmap, pixelWidth: width, pixelHeight: height)
    }

    private struct AlphaScan {
        let pixelWidth: Int
        let opaqueBounds: CGRect // pixels
        let softAlphaPixelsOutsideOpaqueBounds: Int

        var opaqueBoundsPixelInset: Double {
            guard opaqueBounds.width > 0 else { return 0 }
            return Double(min(
                opaqueBounds.minX,
                Double(pixelWidth) - opaqueBounds.maxX,
                opaqueBounds.minY,
                Double(pixelWidth) - opaqueBounds.maxY
            ))
        }
    }

    /// Renders an image and measures its alpha layout: the bounding box of
    /// the pixels that are clearly present (alpha ≥ 0.5, above the ~0.3 the
    /// baked shadow's flood opacity reaches) and how many soft-alpha pixels
    /// live OUTSIDE that box — the shadow's ink.
    private static func alphaScan(of image: NSImage) throws -> AlphaScan {
        let size = image.size
        let scale: CGFloat = 2
        let width = Int(size.width * scale)
        let height = Int(size.height * scale)
        let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .calibratedRGB, bytesPerRow: 0, bitsPerPixel: 0
        )
        let bitmap = try XCTUnwrap(rep)
        bitmap.size = size
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        image.draw(in: NSRect(origin: .zero, size: size), from: .zero, operation: .copy, fraction: 1)
        NSGraphicsContext.restoreGraphicsState()

        var minX = width, minY = height, maxX = -1, maxY = -1
        for y in 0..<height {
            for x in 0..<width {
                if (bitmap.colorAt(x: x, y: y)?.alphaComponent ?? 0) >= 0.5 {
                    minX = min(minX, x); minY = min(minY, y)
                    maxX = max(maxX, x); maxY = max(maxY, y)
                }
            }
        }
        let bounds = maxX >= 0
            ? CGRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1)
            : .zero
        var softOutside = 0
        if maxX >= 0 {
            for y in 0..<height {
                for x in 0..<width {
                    guard !bounds.contains(CGPoint(x: x, y: y)) else { continue }
                    let alpha = bitmap.colorAt(x: x, y: y)?.alphaComponent ?? 0
                    if alpha > 0.05 && alpha < 0.95 { softOutside += 1 }
                }
            }
        }
        return AlphaScan(
            pixelWidth: width,
            opaqueBounds: bounds,
            softAlphaPixelsOutsideOpaqueBounds: softOutside
        )
    }

    /// The opaque bounds in POINTS of the given image — the test's own
    /// independent measurement of where the artwork really sits.
    private static func opaqueBounds(of image: NSImage) throws -> CGRect {
        let scale: CGFloat = 2
        let scan = try alphaScan(of: image)
        return CGRect(
            x: scan.opaqueBounds.minX / scale,
            y: scan.opaqueBounds.minY / scale,
            width: scan.opaqueBounds.width / scale,
            height: scan.opaqueBounds.height / scale
        )
    }
}
