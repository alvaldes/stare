import SwiftUI
import StareCore

// The SwiftUI primitives the Settings sidebar and panes are built from. Kept
// deliberately small: no theme system, no design tokens — just the card, row,
// pane and stage shapes every pane shares, styled with the app's existing
// materials.

/// The measurements the settings shell and its panes share, so the sidebar,
/// the pane padding and the column break stay one decision instead of three.
enum SettingsMetrics {
    /// The sidebar's fixed width; the pane area takes everything else. Wide
    /// enough for the longest row title in SEMIBOLD — the weight the selected
    /// row uses — because a row that fits regular and wraps when selected
    /// jumps the whole list. `SettingsSidebarWidthTests` measures it.
    static let sidebarWidth: CGFloat = 214
    /// The pane area's horizontal padding, per side.
    static let panePadding: CGFloat = 22
    /// Below this card width a pane shows one column instead of two: a
    /// three-way segmented control and its label stop fitting side by side.
    static let twoColumnMinimum: CGFloat = 660
    /// Cards never grow past this in a single-column pane, so a row's label
    /// and its control stay within one glance on a wide window.
    static let singleColumnMaximum: CGFloat = 700
    /// The sidebar's own inset, around the whole column.
    static let sidebarPadding: CGFloat = 10
    /// A sidebar row: its inner horizontal padding, the symbol column and the
    /// gap between the symbol and the title. Shared with the guard that proves
    /// a title never wraps, so the measurement cannot drift from the row it
    /// measures (review R2-002/R3-003).
    static let sidebarRowPadding: CGFloat = 10
    static let sidebarRowSymbolWidth: CGFloat = 18
    static let sidebarRowSpacing: CGFloat = 10
    /// Between two cards, and between the cards and the stage.
    static let cardSpacing: CGFloat = 14
    /// Between the stage's label and its note, on the top row above the
    /// preview.
    static let stageLabelSpacing: CGFloat = 4
    /// Between the stage's label row and the preview beneath it.
    static let stageHeaderSpacing: CGFloat = 8
    /// The stage's padding around its content, on every side.
    static let stagePadding: CGFloat = 12
    /// What the stage's own chrome takes from a pane's width, so a stage
    /// that scales its content down to fit knows the width it really has.
    /// The label row stands above the preview (S4), so the only horizontal
    /// chrome is the stage's padding — nothing stands to the left of the
    /// bar any more.
    /// The tallest the previewed bar may be drawn inside the stage: a vertical
    /// column is 700+ pt tall at full size and would push the pane apart.
    static let stageMaxPreviewHeight: CGFloat = 360

    static var stageChrome: CGFloat {
        stagePadding * 2
    }
}

/// A pane that is its own scroll container: the header stays put and the cards
/// move under it. Every pane except the ones with a stage uses this, and the
/// selftest renders a pane whole because the pane owns its scrolling.
struct SettingsPane<Cards: View>: View {
    let title: String
    let subtitle: String
    @ViewBuilder let cards: Cards

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            PaneHeader(title: title, subtitle: subtitle)
                .padding(.horizontal, SettingsMetrics.panePadding)
                .padding(.top, 18)
                .padding(.bottom, 14)

            ScrollView {
                cards
                    .toggleStyle(.switch)
                    .padding(.horizontal, SettingsMetrics.panePadding)
                    .padding(.bottom, 22)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

/// A pane with a live stage: the header and the stage never scroll, so what
/// the user is changing stays in view while the cards below move. This is the
/// shape the previews take — never a card at the end of a long pane.
struct StageSettingsPane<Stage: View, Cards: View>: View {
    let title: String
    let subtitle: String
    @ViewBuilder let stage: Stage
    @ViewBuilder let cards: Cards

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            PaneHeader(title: title, subtitle: subtitle)
                .padding(.horizontal, SettingsMetrics.panePadding)
                .padding(.top, 18)
                .padding(.bottom, 12)

            stage
                .padding(.horizontal, SettingsMetrics.panePadding)
                .padding(.bottom, 16)

            ScrollView {
                cards
                    .toggleStyle(.switch)
                    .padding(.horizontal, SettingsMetrics.panePadding)
                    .padding(.bottom, 22)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

/// The pinned region a preview lives in: a label that says what the stage is
/// showing, and the live view beneath it. The label and the note stand on a
/// top row of their own (S4), so the preview gets the pane's whole width
/// underneath instead of the width a lead column left it.
struct SettingsStage<Content: View>: View {
    let label: String
    let note: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: SettingsMetrics.stageHeaderSpacing) {
            VStack(alignment: .leading, spacing: SettingsMetrics.stageLabelSpacing) {
                Text(label.uppercased())
                    .font(.system(size: 10, weight: .bold))
                    .tracking(0.8)
                    .foregroundStyle(.secondary)
                Text(note)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            content
                .frame(maxWidth: .infinity, alignment: .center)
        }
        .padding(SettingsMetrics.stagePadding)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor).opacity(0.6))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color(nsColor: .separatorColor).opacity(0.8))
        )
    }
}

/// One or two columns of cards, laid out as ROWS: every row holds one card
/// from each column, and the row is as tall as the taller of the two, so both
/// cards in a row end on the same line (B8, the owner's own first clause: "en
/// una fila ambas card tengan la misma altura").
///
/// Rows, not columns, because a `Grid` equalises a row natively — its height is
/// the tallest cell's, and both cells fill it — while equalising two COLUMNS
/// needs them measured and re-laid out, which inside the pane's `ScrollView`
/// feeds the previous stretch straight back into the measurement (L24: the
/// shorter column reported the whole viewport as its ideal). Nothing is measured
/// here that the layout system does not already measure for its own purposes.
///
/// A column with fewer cards simply has no cell in the later rows, and the card
/// beside it keeps its own side by holding the slot with a clear filler.
///
/// The width of a column is fixed from the width the shell hands down, so the
/// two columns are always the same width regardless of what the cards contain.
///
/// Only Pointer Highlight uses this today (a genuine two-vs-two: Shape/Stroke
/// beside Motion/Colour). Overlay, Capture and Whiteboard pass their cards as a
/// plain `VStack` with `.settingsSingleColumn()` because their cards pair
/// unevenly — a lone card beside a pair, or a short card beside one carrying a
/// paragraph — and a row that equalises those leaves the short one mostly
/// empty. Two columns are a pairing decision, not a default.
struct SettingsColumns: View {
    let width: CGFloat
    let left: [AnyView]
    let right: [AnyView]

    init(width: CGFloat, left: [AnyView], right: [AnyView]) {
        self.width = width
        self.left = left
        self.right = right
    }

    /// One row per card of the longer column.
    var rows: Int { max(left.count, right.count) }

    private var gap: CGFloat { SettingsMetrics.cardSpacing }

    private var columnWidth: CGFloat {
        max(0, (width - gap) / 2)
    }

    var body: some View {
        if width >= SettingsMetrics.twoColumnMinimum {
            Grid(alignment: .topLeading, horizontalSpacing: gap, verticalSpacing: gap) {
                ForEach(0..<rows, id: \.self) { row in
                    GridRow {
                        cell(left, row)
                        cell(right, row)
                    }
                }
            }
        } else {
            VStack(spacing: gap) {
                ForEach(Array((left + right).enumerated()), id: \.offset) { _, card in
                    card
                }
            }
            .settingsSingleColumn()
        }
    }

    /// One card in its column. Both cells of a row are the same width and both
    /// fill the row's height, which is what makes a short card match the tall
    /// one beside it. A row on the shorter side holds its place with a clear
    /// filler, so the other card never slides into the wrong column.
    private func cell(_ cards: [AnyView], _ row: Int) -> some View {
        Group {
            if row < cards.count {
                cards[row]
            } else {
                Color.clear
            }
        }
        .frame(width: columnWidth, alignment: .topLeading)
        .frame(maxHeight: .infinity, alignment: .topLeading)
    }
}

extension View {
    /// Caps a pane's cards so a wide window does not stretch every row into a
    /// label on the far left and its control on the far right.
    func settingsSingleColumn() -> some View {
        frame(maxWidth: SettingsMetrics.singleColumnMaximum, alignment: .topLeading)
    }
}

/// A titled card with a divider and the content stacked beneath: the one
/// container a pane uses, with the same `.ultraThinMaterial` and rounded
/// corners as the toolbar's cards.
struct SettingsCard<Content: View>: View {
    let title: String
    let symbol: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: symbol)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 24, height: 24)
                    .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 7))
                    .overlay(
                        RoundedRectangle(cornerRadius: 7)
                            .strokeBorder(Color(nsColor: .separatorColor))
                    )
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                Spacer(minLength: 0)
            }
            Divider()
            content
        }
        .padding(14)
        // The card FILLS the space it is given, not just its content: the two
        // columns are rows of a `Grid`, and a row is as tall as its taller card
        // — so the shorter card has to grow into the row for the two to end on
        // the same line. In a single column nothing offers extra height, so the
        // card stays exactly as tall as its content.
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 13))
        .overlay(
            RoundedRectangle(cornerRadius: 13)
                .strokeBorder(Color(nsColor: .separatorColor))
        )
    }
}

/// One setting: title and optional detail on the left, the control on the
/// right, on a single line.
///
/// The control owns the row's trailing edge, and a fixed-width control inside
/// `content` anchors there with `alignment: .trailing`: a menu picker draws its
/// own box inside the width it is given, so a centred frame leaves that box
/// short of the column the toggles, the segmented controls and the slider
/// values already share.
struct SettingRow<Control: View>: View {
    let title: String
    var detail: String?
    let content: Control

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .fixedSize(horizontal: false, vertical: true)
                if let detail {
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 8)
            content
        }
    }
}

/// The title every pane opens with.
struct PaneHeader: View {
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.system(size: 17, weight: .semibold))
            Text(subtitle)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// A small status dot colouring the Screen Recording permission state: green
/// when capturing works, amber when a decision is still pending.
struct StatusDot: View {
    let state: ScreenRecordingAccess

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: 9, height: 9)
    }

    private var color: Color {
        switch state {
        case .granted: .green
        case .denied, .grantedPendingRestart: .orange
        }
    }
}

/// The app icon, at the size the caller wants (the About pane shows it at 56
/// points).
struct AppMark: View {
    var size: CGFloat = 36

    var body: some View {
        Image(nsImage: AppIconArtwork.main)
            .resizable()
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}

/// The app's icon in full colour, resolved in ONE place: the real artwork from
/// `Resources/AppIcon.icns` first — `NSApp.applicationIconImage` returns a
/// desaturated variant on macOS 26 — falling back to `applicationIconImage`
/// when the resource is absent (for example under `swift run`, which ships no
/// bundle resources). `AppMark` and the setup guide share this single source
/// so a third variant cannot drift in (T2/S2 of batch A).
///
/// Everything that resolves is also held FLAT (T6/S6): the icns artwork
/// carries a macOS-style drop shadow baked into its own pixels — the SVG's
/// `feDropShadow` (`filter id="shadow"`, dx 0 dy 8, σ 10, opacity .3),
/// rasterised in by `Scripts/icons.sh`; there is no shadow-free PNG behind it
/// and no SwiftUI modifier draws one (nothing in the app uses `.shadow()`).
/// Measured in the decoded icns: a 512 pt canvas whose opaque 412 pt square
/// sits inside it with ~50 pt of padding per side, and the padding around the
/// square is soft-alpha shadow ink (hundreds of thousands of pixels at the
/// 2× probe render, capped at the flood opacity's 30 %). So the resolved
/// image is cropped to the opaque shape's own bounds by alpha: every shadow
/// pixel lives outside that square. The cost of the crop, stated: the mark
/// now draws the tile edge to edge of its `size` frame, so the visible square
/// is ~24 % larger in side than the padding-padded canvas made it (512/412)
/// — the identity behaviour (colour, no tint, not a template,
/// `accessibilityHidden`, both call sites, the `size` parameter) is untouched.
enum AppIconArtwork {
    /// The cached result for the real bundle, so neither caller re-decodes
    /// the 612 KB icon file on every render tick.
    static var main: NSImage { Cached.main }

    /// The named resolution: `AppIcon.icns` from the given bundle first, the
    /// given fallback only when the resource is missing or undecodable — a
    /// missing file must never resolve to nothing. Either branch is trimmed
    /// to its opaque bounds so the baked shadow never reaches the mark.
    static func resolve(in bundle: Bundle) -> NSImage {
        resolve(
            resourceURL: bundle.url(forResource: "AppIcon", withExtension: "icns"),
            fallback: NSApp.applicationIconImage
        )
    }

    /// The head-testable core of the resolution above: read the artwork at
    /// `resourceURL` when it decodes, otherwise return the fallback itself,
    /// and trim the result to its opaque bounds. A fallback may keep its
    /// identity when it carries no opaque region to trim — a missing file
    /// must never resolve to nothing.
    static func resolve(resourceURL: URL?, fallback: NSImage) -> NSImage {
        let resolved = resolveArtwork(resourceURL: resourceURL, fallback: fallback)
        return trimToOpaqueBounds(resolved)
    }

    private static func resolveArtwork(resourceURL: URL?, fallback: NSImage) -> NSImage {
        if let resourceURL, let icon = NSImage(contentsOf: resourceURL) {
            return icon
        }
        return fallback
    }

    /// The opaque bounds of `image`, in points: the bounding box of the pixels
    /// at alpha ≥ 0.5 — above the baked shadow's ~30 % flood-opacity ceiling,
    /// below the artwork's own edges, so the box is the shape the icon paints
    /// and not one pixel of its shadow. Rendered and measured at 2× for a
    /// clean edge estimate on a soft-alpha boundary.
    private static func opaqueBounds(of image: NSImage) -> CGRect? {
        let size = image.size
        guard size.width > 0, size.height > 0 else { return nil }
        let scale: CGFloat = 2
        let pixelsWide = max(1, Int(size.width * scale))
        let pixelsHigh = max(1, Int(size.height * scale))
        guard let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: pixelsWide, pixelsHigh: pixelsHigh,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .calibratedRGB, bytesPerRow: 0, bitsPerPixel: 0
        ) else { return nil }
        bitmap.size = size
        guard let context = NSGraphicsContext(bitmapImageRep: bitmap) else { return nil }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        image.draw(in: NSRect(origin: .zero, size: size), from: .zero, operation: .copy, fraction: 1)
        NSGraphicsContext.restoreGraphicsState()

        var minX = pixelsWide, minY = pixelsHigh, maxX = -1, maxY = -1
        for y in 0..<pixelsHigh {
            for x in 0..<pixelsWide {
                if (bitmap.colorAt(x: x, y: y)?.alphaComponent ?? 0) >= 0.5 {
                    minX = min(minX, x); minY = min(minY, y)
                    maxX = max(maxX, x); maxY = max(maxY, y)
                }
            }
        }
        guard maxX >= 0 else { return nil }
        return CGRect(
            x: CGFloat(minX) / scale,
            y: CGFloat(minY) / scale,
            width: CGFloat(maxX - minX + 1) / scale,
            height: CGFloat(maxY - minY + 1) / scale
        )
    }

    /// Crops `image` to its own opaque bounds — where the icns's baked drop
    /// shadow dies. An image that is already tight (no padding), fully
    /// transparent, or unrenderable comes back unchanged, so the fallback
    /// path's identity guarantee and degenerate inputs stay safe.
    static func trimToOpaqueBounds(_ image: NSImage) -> NSImage {
        guard let bounds = opaqueBounds(of: image) else { return image }
        let paddedWidth = abs(bounds.minX) < 0.5 && abs(image.size.width - bounds.maxX) < 0.5
        let paddedHeight = abs(bounds.minY) < 0.5 && abs(image.size.height - bounds.maxY) < 0.5
        if paddedWidth && paddedHeight { return image }

        let scale: CGFloat = 2
        guard let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: max(1, Int((bounds.width * scale).rounded(.up))),
            pixelsHigh: max(1, Int((bounds.height * scale).rounded(.up))),
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .calibratedRGB, bytesPerRow: 0, bitsPerPixel: 0
        ) else { return image }
        bitmap.size = bounds.size
        guard let context = NSGraphicsContext(bitmapImageRep: bitmap) else { return image }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        image.draw(
            in: NSRect(origin: .zero, size: bounds.size),
            from: bounds,
            operation: .copy,
            fraction: 1
        )
        NSGraphicsContext.restoreGraphicsState()
        let cropped = NSImage(size: bounds.size)
        cropped.addRepresentation(bitmap)
        return cropped
    }

    private enum Cached {
        static let main = resolve(in: .main)
    }
}

/// App version from the bundle, with the dev-runner fallback: `swift run` has
/// no Info.plist, and "0.2.0" is the version the changelog continues.
enum AppVersion {
    static let short = Bundle.main.object(
        forInfoDictionaryKey: "CFBundleShortVersionString"
    ) as? String ?? "0.2.0"
}
