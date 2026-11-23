import CoreGraphics
import Foundation

/// The single place that actually pixelates pixels. Sibling of `BlurEffect`
/// and, like it, a pure function over images: no windows, no marks, no state.
///
/// # Block size is a redaction parameter, not a style parameter
///
/// The S23 blur audit measured that 12 pt was the smallest blur radius that
/// stayed safe against 11 pt text — the radius has to stay on the order of
/// the glyph. The same pressure point here is the block-to-glyph ratio: a
/// plain pixelate publishes each block's mean on a regular, guessable grid
/// and becomes weakly invertible once blocks shrink to a few glyph stroke
/// widths (the strokes of 11 pt text are only ~2–3 px wide at 1x). Two
/// things guard it:
///
/// 1. `blockSize(for:)` derives the block from the mark itself — half the
///    mark's smaller side, so a text-line mark gets a block on the order of
///    half its line height — with `minimumBlockSize` as the floor. `crop`
///    clamps any caller-requested block up to that floor, so there is no way
///    to shrink it unknowingly.
/// 2. Each block's sample window moves inside its own cell by a deterministic
///    pseudo-random amount, so the grid alignment an inversion attack needs
///    is not published even at the floor.
///
/// Everything here is CoreGraphics only, and the same seed reproduces the
/// same output, so preview and saved capture can agree later.
public enum PixelateEffect {
    /// Smallest allowed block, in image pixels. Below this a block covers only
    /// a few glyph stroke widths and pixelation erodes into a weak redaction;
    /// `crop` clamps requested blocks up to it.
    public static let minimumBlockSize: CGFloat = 8

    /// Seed used when the caller does not name one. Any caller that wants
    /// preview and saved capture to pixelate identically passes the same seed.
    public static let defaultSeed: UInt64 = 0x235A_7B10

    /// Block size for a mark: half the mark's smaller side — so a text-line
    /// mark gets a block on the order of half its line height, well above the
    /// ~2–3 px stroke width of 11 pt text — floored at `minimumBlockSize`.
    public static func blockSize(for pixelRect: CGRect) -> CGFloat {
        let content = min(abs(pixelRect.width), abs(pixelRect.height))
        guard content.isFinite, content >= 1 else { return minimumBlockSize }
        return max(ceil(content / 2), minimumBlockSize)
    }

    /// Pixelation of `pixelRect` inside `image`, returned as an image of that
    /// same size, oriented like `image`, ready to be drawn where the rect maps
    /// in view space.
    ///
    /// `pixelRect` is in `image` pixels with a bottom-left origin, the space
    /// shared by bitmap `CGContext`s and `CIImage`. Blocks tile the rect's
    /// pixel bounding box (intersection with the image), and each block is a
    /// constant colour sampled from inside its own cell, so no original detail
    /// survives at block scale. When the rect reaches past the image, the
    /// returned image covers the intersection; callers must draw it at that
    /// intersection. Returns nil when the rect is empty or completely outside
    /// the image instead of crashing: the callers have to fall back.
    ///
    /// A `blockSize` below `minimumBlockSize` is clamped up to the floor; nil
    /// means `blockSize(for:)` derives it from the rect. The same `seed`
    /// always yields the same image.
    public static func crop(
        _ image: CGImage,
        pixelRect: CGRect,
        blockSize requestedBlockSize: CGFloat? = nil,
        seed: UInt64 = defaultSeed
    ) -> CGImage? {
        let fullRect = CGRect(x: 0, y: 0, width: image.width, height: image.height)
        let rect = pixelRect.intersection(fullRect)
        guard !rect.isNull, !rect.isEmpty, rect.width >= 1, rect.height >= 1 else { return nil }

        let x0 = Int(floor(rect.minX)), y0 = Int(floor(rect.minY))
        let outWidth = Int(ceil(rect.maxX)) - x0
        let outHeight = Int(ceil(rect.maxY)) - y0
        let block: CGFloat
        if let requested = requestedBlockSize, requested.isFinite, requested >= 1 {
            block = max(ceil(requested), minimumBlockSize)
        } else {
            block = blockSize(for: rect)
        }
        let blockStep = max(Int(block), 1)

        // Render the source once and work on raw RGBA bytes in both
        // directions: sampling means and writing constant blocks without any
        // second image pass.
        var source = [UInt8](repeating: 0, count: image.width * image.height * 4)
        let sourceContext = CGContext(
            data: &source,
            width: image.width,
            height: image.height,
            bitsPerComponent: 8,
            bytesPerRow: image.width * 4,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        sourceContext.draw(
            image,
            in: CGRect(x: 0, y: 0, width: image.width, height: image.height)
        )

        var output = [UInt8](repeating: 0, count: outWidth * outHeight * 4)

        // CGContext buffers run top-down, but `pixelRect` is in CG
        // bottom-left coordinates: the rect's top edge sits this many rows
        // below the image's top. Indexing source rows from here keeps the
        // returned image oriented like the input, as `BlurEffect.crop` does.
        let sourceRowBase = image.height - Int(ceil(rect.maxY))

        var cellY = 0
        while cellY < outHeight {
            let cellHeight = min(blockStep, outHeight - cellY)
            var cellX = 0
            while cellX < outWidth {
                let cellWidth = min(blockStep, outWidth - cellX)

                // The sample window is half the block on a side and moves
                // inside the cell by a deterministic pseudo-random amount, so
                // the block's colour is not the cell mean published on the
                // guessable grid. A window of half a block can never sit
                // fully inside a stroke thinner than the block, so detail at
                // block scale cannot survive.
                let windowSize = max(1, min(blockStep, min(cellWidth, cellHeight)) / 2)
                let state = cellState(seed: seed, column: cellX / blockStep, row: cellY / blockStep)
                var rng = state
                let offsetFractionX = Double(nextRandom(&rng) >> 32) / Double(UInt32.max)
                let offsetFractionY = Double(nextRandom(&rng) >> 32) / Double(UInt32.max)
                let offsetX = min(Int(offsetFractionX * Double(cellWidth - windowSize + 1)), cellWidth - windowSize)
                let offsetY = min(Int(offsetFractionY * Double(cellHeight - windowSize + 1)), cellHeight - windowSize)

                var sum = [Double](repeating: 0, count: 4)
                for dy in 0..<windowSize {
                    for dx in 0..<windowSize {
                        let sourceIndex = ((sourceRowBase + cellY + offsetY + dy) * image.width + (x0 + cellX + offsetX + dx)) * 4
                        for channel in 0..<4 {
                            sum[channel] += Double(source[sourceIndex + channel])
                        }
                    }
                }
                let sampleCount = Double(windowSize * windowSize)
                let colour = sum.map { UInt8(max(0, min(255, ($0 / sampleCount).rounded()))) }

                for dy in 0..<cellHeight {
                    for dx in 0..<cellWidth {
                        let outputIndex = ((cellY + dy) * outWidth + (cellX + dx)) * 4
                        for channel in 0..<4 {
                            output[outputIndex + channel] = colour[channel]
                        }
                    }
                }

                cellX += blockStep
            }
            cellY += blockStep
        }

        let outputContext = CGContext(
            data: &output,
            width: outWidth,
            height: outHeight,
            bitsPerComponent: 8,
            bytesPerRow: outWidth * 4,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        return outputContext.makeImage()
    }

    /// SplitMix64 step: the stream every cell draws its offsets from.
    private static func nextRandom(_ state: inout UInt64) -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    /// One independent generator per grid cell, keyed by the seed and the
    /// cell's position: the same seed reproduces the same output byte for
    /// byte, a different seed moves every offset.
    private static func cellState(seed: UInt64, column: Int, row: Int) -> UInt64 {
        var state = seed
        state ^= UInt64(truncatingIfNeeded: column) &* 0x9E37_79B9_7F4A_7C15
        state ^= UInt64(truncatingIfNeeded: row) &* 0xC2B2_AE3D_27D4_EB4F
        _ = nextRandom(&state)
        return state
    }
}
