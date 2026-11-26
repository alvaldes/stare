import AppKit
import Combine
import SwiftUI
import StareCore
import UniformTypeIdentifiers

/// The capture's {app}/{display} naming identity (S5), one value pair one
/// capture was resolved with: the capture tail resolves it once at
/// delivery — exactly where a folder save resolves it — and the editor's
/// save panel renders and writes through the same pair, so a template can
/// never be previewed under one name and written under another. The type
/// lives with the editor because the editor is where the pair is honoured.
/// `.unknown` is the honest absent case: an identity no capture exists
/// for — this editor's own composed variant, a capture evicted from the
/// bounded ledger or reopened from a previous session — and both paths
/// then agree on the same refusal into the prefix-name fallback the
/// Settings preview documents.
struct CaptureEditorIdentity: Equatable {
    var app: String?
    var displayName: String?

    static let unknown = CaptureEditorIdentity(app: nil, displayName: nil)
}

/// Editing a capture: the image with the tools on top, crop, copy and save.
/// The capture arrives with its marks already composed, so this is a second layer
/// over a real picture. The save panel's default name and format come from the
/// persisted capture preference (T11/S6), handed in by the overlay — the
/// editor never loads the blob itself, staying detached from app state.
final class CaptureEditorController {
    private var windows: [CaptureEditorWindow] = []

    /// Fires with the composed image every time the user takes one out of the
    /// editor — a copy or a completed save (L7). The overlay wires it to the
    /// same recording its own captures go through, so an edited variant lands
    /// in the history like any other capture instead of vanishing with the
    /// window.
    var onDeliver: ((CGImage) -> Void)?

    /// The windows this controller opened, open or closed on screen — the seam
    /// a test needs to reach the content it built.
    var windowsForTesting: [CaptureEditorWindow] { windows }

    /// Round four S6: opening an editor and closing the last one moves the
    /// app's Dock presence with the truth of the editor windows. Stare keeps
    /// launching as the accessory menu-bar app (main.swift's policy, LSUIElement
    /// untouched); only an editor ON SCREEN brings the Dock icon, so the open
    /// editor "se queda la ventana abierta" behind every other app no more —
    /// while it exists, the Dock shows Stare like another app, and the last
    /// window's close returns the accessory contract atomically.
    static func dockActivationPolicy(forEditorCount count: Int) -> NSApplication.ActivationPolicy {
        count == 0 ? .accessory : .regular
    }

    private func reflectDockPresence() {
        NSApp?.setActivationPolicy(Self.dockActivationPolicy(forEditorCount: windows.count))
    }

    func open(
        image: CGImage, capture: CapturePreference = .standard, redactionStyle: RedactionStyle = .blur,
        app: String? = nil, displayName: String? = nil
    ) {
        let window = CaptureEditorWindow(
            image: image,
            capture: capture,
            redactionStyle: redactionStyle,
            app: app,
            displayName: displayName,
            onDeliver: onDeliver
        ) { [weak self] closing in
            self?.editorWindowDidClose(closing)
        }
        windows.append(window)
        reflectDockPresence()
        window.center()
        window.makeFirstResponder(window.contentView?.subviews.first { $0 is CaptureEditorCanvas })
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
        // The user may have come from an inactive accessory app: raise the editor
        // above the frontmost application's windows, not just above our own.
        window.orderFrontRegardless()
        Diag.log("editor opened \(image.width)x\(image.height)")
    }

    /// The close tail (round four S6): the reflection runs after the removal,
    /// so the last editor closing returns the accessory policy as the window
    /// leaves.
    private func editorWindowDidClose(_ window: CaptureEditorWindow) {
        windows.removeAll { $0 === window }
        reflectDockPresence()
    }
}

final class CaptureEditorWindow: NSWindow {
    override var canBecomeKey: Bool { true }

    init(
        image: CGImage,
        capture: CapturePreference,
        redactionStyle: RedactionStyle = .blur,
        app: String? = nil,
        displayName: String? = nil,
        onDeliver: ((CGImage) -> Void)? = nil,
        onClose: @escaping (CaptureEditorWindow) -> Void
    ) {
        let content = CaptureEditorContent(
            image: image, capture: capture, redactionStyle: redactionStyle,
            app: app, displayName: displayName)
        content.onDeliver = onDeliver
        super.init(
            contentRect: CGRect(origin: .zero, size: content.preferredSize),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )

        title = "Edit Capture"
        isReleasedWhenClosed = false
        // Windows do not accept mouse-moved events by default; the canvas's
        // per-move cursor re-assertion (S7) needs them, the same opt-in the
        // toolbar monitor relies on for its moves.
        acceptsMouseMovedEvents = true
        self.onClose = { onClose($0) }
        contentView = content
        self.editorContent = content
        setContentSize(content.preferredSize)
    }

    /// The content this window was built around — the seam the key route
    /// reads the canvas through.
    private(set) var editorContent: CaptureEditorContent?

    /// S4: the armed-item keys ('b', 'v', the ink digits) belong to the
    /// editor, not to whichever control happens to hold the focus. When the
    /// canvas IS the first responder its own keyDown consumes them first and
    /// this route is never reached; when a chrome control took the focus —
    /// the background fields, a click on the palette — the responder chain
    /// declines and the window routes the press to the same resolver the
    /// canvas uses, so the key works exactly as it does on the drawing
    /// overlay, where the floating bar never takes the keyboard.
    override func keyDown(with event: NSEvent) {
        if case let canvas? = editorContent?.canvas,
            canvas.handlesArmedItemKey(with: event) {
            return
        }
        super.keyDown(with: event)
    }

    private var onClose: ((CaptureEditorWindow) -> Void)?

    override func close() {
        onClose?(self)
        onClose = nil
        super.close()
    }
}

/// Toolbar, canvas and the few actions an edit needs.
final class CaptureEditorContent: NSView {
    let canvas: CaptureEditorCanvas
    /// The chrome, exposed (not private) as the test seam the layout pins
    /// assert chrome geometry through, the same way `canvas` already is.
    let chrome: NSHostingView<EditorChrome>
    /// The editor's own state — one instance, seeded here, shared by the
    /// canvas, the chrome and every handler. Created `.detached` from the
    /// app's model (T1/S1's read-only contract stands even though the
    /// orientation snapshot does not, L4): no model is injected, so nothing
    /// the editor picks persists, and nothing stored is read — the chrome is
    /// ALWAYS the horizontal row at the top (S4).
    let state: EditorState
    /// The preference the save panel defaults from (T11/S6). Its stored
    /// backdrop values are only seeds: the editor's own background control
    /// edits per-capture values, never the stored one (T2/S2).
    private let capture: CapturePreference
    /// Where a composed variant goes once the user copies or saves it (L7).
    var onDeliver: ((CGImage) -> Void)?
    /// The edge the chrome docks at inside this window (S4): ALWAYS the top.
    /// The orientation snapshot is withdrawn and the editor reads nothing
    /// stored — the palette is one horizontal row at the top of the editor
    /// in every configuration.
    var chromeBorder: ToolbarBorder { .top }
    var preferredSize: CGSize {
        let image = canvas.image
        let width = min(max(CGFloat(image.width) / 2, 480), 1100)
        let scale = width / CGFloat(image.width)
        let height = CGFloat(image.height) * scale
        // One bar, one case (S4): a horizontal row on top, so the row's
        // height joins the canvas height and the width answers to the wider
        // of the canvas and the bar — the bar's fitting size, never a
        // squeezed bar, wins.
        let chromeSize = chrome.fittingSize
        let canvasHeight = min(max(height, 260), 760)
        return CGSize(width: max(width, chromeSize.width), height: canvasHeight + chromeSize.height)
    }

    init(
        image: CGImage, capture: CapturePreference, redactionStyle: RedactionStyle,
        app: String? = nil, displayName: String? = nil
    ) {
        self.capture = capture
        // The state is created once, detached (T1/S1's read-only contract):
        // never the model, so no editor pick persists. The per-capture
        // background controls (T2/S2) seed from the stored default.
        let seeded = EditorState()
        seeded.seedBackdrop(from: capture)
        state = seeded
        canvas = CaptureEditorCanvas(image: image)
        // The capture's naming identity (S5): the {app}/{display} the
        // overlay resolved for THIS capture, threaded through the handoff.
        // The save panel renders and writes through it — see the canvas's
        // `fileNameContext`, the one place both paths keep agreeing on.
        canvas.fileNameContext = CaptureEditorIdentity(app: app, displayName: displayName)
        chrome = NSHostingView(
            rootView: EditorChrome(
                state: state,
                onUndo: {},
                onRedo: {},
                onClear: {},
                onCrop: {},
                onCopy: {},
                onSave: {},
                onClose: {}
            )
        )
        super.init(frame: .zero)
        chrome.sizingOptions = [.intrinsicContentSize]
        canvas.state = state
        // The editor's own mark creation follows the same preference (T6b/S13):
        // the redaction choice rides in from the overlay, so a mark drawn here
        // redacts with the same style a mark drawn over the live screen does.
        state.redactionStyle = redactionStyle
        rebuildChrome()
        addSubview(canvas)
        addSubview(chrome)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("CaptureEditorContent is created in code only")
    }

    private func rebuildChrome() {
        chrome.rootView = EditorChrome(
            state: state,
            onUndo: { [weak self] in self?.canvas.undo() },
            onRedo: { [weak self] in self?.canvas.redo() },
            onClear: { [weak self] in self?.canvas.clearMarks() },
            onCrop: { [weak self] in self?.canvas.beginCrop() },
            onCopy: { [weak self] in
                guard let self else { return }
                self.canvas.copyToPasteboard()
                self.deliverComposed()
            },
            onSave: { [weak self] in
                guard let self else { return }
                let preference = self.capture
                // Delivery waits for the write: a cancelled save panel produced
                // nothing, so it records nothing.
                self.canvas.savePanel(preference: preference) { [weak self] in
                    self?.deliverComposed()
                }
            },
            onClose: { [weak self] in self?.window?.close() }
        )
    }

    /// Hands the composed image to `onDeliver`, if any: one call site for both
    /// paths (copy, saved) so the edited variant reaches the history the same
    /// way whichever one produced it.
    func deliverComposed() {
        guard let composed = canvas.composedImage() else { return }
        onDeliver?(composed)
    }

    // MARK: - The editor window's cursor (round four S5)

    /// The ONE decision of the editor's window (round four S5): the
    /// canvas-backed answer — the armed tool's own glyph while the pointer is
    /// over the picture, the arrow over the palette row, the title bar and
    /// the window buttons. The content routes every crossing of the whole
    /// content row through it; the canvas's own exit answers through it too,
    /// so no cursor in this window is set anywhere else.
    func cursor(atWindowPoint point: CGPoint) -> NSCursor {
        canvas.cursor(atWindowPoint: point)
    }

    /// Applies the decision at `point` to the live pointer (the crossing
    /// handlers' single call).
    func applyEditorCursor(atWindowPoint point: CGPoint) {
        cursor(atWindowPoint: point).set()
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        // Only the areas this class installs: the canvas keeps its own.
        for area in trackingAreas where area.owner === self { removeTrackingArea(area) }
        // Round four S5's delivery half: nothing in the chrome ever answered
        // a cursor update, because no tracking area covered the chrome —
        // AppKit delivers the crossing and cursor-update events through an
        // area or not at all (the same limitation the canvas's own delivery
        // half documents, S7/3b). The content owns exactly the areas every
        // other cursor surface installs, covering the chrome row and the
        // canvas alike, and its handlers route through the one decision.
        addTrackingArea(
            NSTrackingArea(
                rect: bounds,
                options: [.cursorUpdate, .mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                owner: self,
                userInfo: nil
            )
        )
    }

    override func cursorUpdate(with event: NSEvent) {
        applyEditorCursor(atWindowPoint: event.locationInWindow)
    }

    override func mouseEntered(with event: NSEvent) {
        applyEditorCursor(atWindowPoint: event.locationInWindow)
    }

    override func mouseExited(with event: NSEvent) {
        // Leaving the content row — onto the title bar, the window buttons or
        // another app: the point is off this content's visible rect, so the
        // one decision answers the arrow (the same answer the standard
        // window chrome serves while the app is active).
        applyEditorCursor(atWindowPoint: event.locationInWindow)
    }

    override func layout() {
        super.layout()
        // S4: the chrome is ALWAYS one horizontal row at the top, whatever
        // the user's own bar stores — the snapshot is withdrawn, so this is
        // the single case `preferredSize` and `layout()` both answer to.
        // The chrome keeps its real fitting height and spans the width; the
        // canvas takes the rest.
        let chromeSize = chrome.fittingSize
        let height = chromeSize.height
        chrome.frame = CGRect(x: 0, y: bounds.height - height, width: bounds.width, height: height)
        canvas.frame = CGRect(x: 0, y: 0, width: bounds.width, height: bounds.height - height)
    }
}

/// One bar: the same pill the outside bar draws — the same materials and
/// geometry rules — always as one horizontal row at the top of the editor
/// (S4: the orientation snapshot is withdrawn), with the capture's own
/// actions added to it (S3: the editor's item list is not the outside bar's
/// list) and without the outside bar's window chrome — no close button, no
/// gripper; the editor window's own traffic light and Escape close it.
struct EditorChrome: View {
    @ObservedObject var state: EditorState
    let onUndo: () -> Void
    let onRedo: () -> Void
    let onClear: () -> Void
    let onCrop: () -> Void
    let onCopy: () -> Void
    let onSave: () -> Void
    let onClose: () -> Void

    /// Whether the background control's popover is open (T2/S2). The editor's
    /// window IS a normal key window — unlike the overlay's screen bar — so a
    /// real popover is allowed here: it anchors to this pill and keeps the
    /// bar itself free of a second panel surface.
    @State private var showsBackgroundControl = false

    /// The bar the chrome draws (S4). Exposed for the tests, which pin the
    /// editor's own item list — the select tool present, the close button
    /// and the gripper absent — through the same construction the body
    /// renders.
    var chromeToolbar: ToolbarView {
        ToolbarView(
            state: state,
            onUndo: onUndo,
            onRedo: onRedo,
            onClear: onClear,
            onDone: onClose,
            extraActions: [
                // Crop behaves as a tool of the editor's palette (S6): it is
                // marked from the same single armed-selection state the tools
                // mark from — picking it unmarks the active tool and picking
                // any tool unmarks it.
                ToolbarAction(symbolName: "crop", help: "Crop", isSelected: state.isCropMarked, handler: onCrop),
                // The capture's background (T2/S2): the per-capture backdrop
                // control, where the image is. It opens the control beside
                // this pill; Settings keeps only the stored default, so the
                // editor edit is per capture and never persists.
                ToolbarAction(
                    symbolName: "rectangle.on.rectangle",
                    help: "Background",
                    isSelected: showsBackgroundControl,
                    handler: { showsBackgroundControl = true }
                ),
                // Copy and save are plain actions.
                ToolbarAction(symbolName: "doc.on.doc", help: "Copy", handler: onCopy),
                ToolbarAction(symbolName: "square.and.arrow.down", help: "Save", handler: onSave),
            ],
            showsWindowChrome: false,
            // The editor draws over a static captured image: tools that need a
            // live session are not offered here (advisory B). The select tool
            // belongs (S4) — it mints no mark over a still image.
            toolGroups: Tool.captureEditorGroups
        )
    }

    var body: some View {
        chromeToolbar
            .padding(.vertical, 6)
            .popover(isPresented: $showsBackgroundControl, arrowEdge: .bottom) {
                EditorBackgroundControl(state: state)
            }
    }
}

/// The capture's background control (T2/S2): padding, corner radius and the
/// fixed shadow, the same backdrop knobs Settings' card edits — but they edit
/// the PER-CAPTURE values here, seeded from the stored default. Nothing here
/// writes into the stored preference: the choice lives and dies with this
/// editor window, and Settings keeps only the default (S2).
private struct EditorBackgroundControl: View {
    @ObservedObject var state: EditorState

    /// One row in the voice the Settings card speaks: the name, the small
    /// helper sentence, then the control.
    private func row(_ title: String, _ detail: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 12, weight: .medium))
            content()
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(detail)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Background")
                .font(.system(size: 13, weight: .semibold))
            row("Padding", "A transparent margin around the capture, in pixels. 0 keeps it as captured.") {
                TextField("", value: Binding(
                    get: { state.backdropPadding },
                    set: { state.backdropPadding = $0 }
                ), format: .number)
                .frame(width: 100)
            }
            row("Corner radius", "Rounds the capture's corners. 0 keeps them square.") {
                TextField("", value: Binding(
                    get: { state.backdropCornerRadius },
                    set: { state.backdropCornerRadius = $0 }
                ), format: .number)
                .frame(width: 100)
            }
            row("Shadow", "Draws a fixed soft shadow behind the capture.") {
                Toggle("", isOn: Binding(
                    get: { state.backdropShadow },
                    set: { state.backdropShadow = $0 }
                ))
                .labelsHidden()
            }
            Text("Composed onto what this editor copies and saves. Applies to this capture only; Settings keeps the default.")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(16)
        .frame(width: 300)
    }
}

// MARK: - Re-editable crop (S7/T11)

/// One of the eight grips of an applied crop region: four corners and four
/// edge lines. Dragging one adjusts that side of the region; dragging the
/// interior moves the region without resizing it.
enum CropHandle: Equatable {
    case topLeft, topRight, bottomLeft, bottomRight
    case top, bottom, left, right
}

/// The mapping between the canvas view and the original capture's pixels.
/// `display` is the view rect the canvas shows and `coverage` the rect of the
/// original — in pixel space — that it draws. Both axes are top-left origin:
/// pixel space because `CGImage.cropping(to:)` crops that way, and view space
/// because the canvas is flipped. Marks are never rewritten when the crop or
/// the window changes: each mark records the space it was drawn in and the
/// canvas converts it at draw, hit-test and save time through `coverage`, so
/// a mark stays glued to the pixels it annotates (S7).
struct EditorCropSpace: Equatable {
    var display: CGRect
    var coverage: CGRect

    /// Image pixels per view point.
    var pixelsPerPoint: CGFloat {
        guard display.width > 0, display.height > 0 else { return 1 }
        return coverage.width / display.width
    }

    /// Fits `coverage`'s aspect ratio into the canvas' bounds, centred.
    static func fitted(coverage: CGRect, inCanvas canvas: CGRect) -> EditorCropSpace {
        guard coverage.width > 0, coverage.height > 0, canvas.width > 0, canvas.height > 0 else {
            return EditorCropSpace(display: canvas, coverage: coverage)
        }
        let scale = min(canvas.width / coverage.width, canvas.height / coverage.height)
        let size = CGSize(width: coverage.width * scale, height: coverage.height * scale)
        let display = CGRect(
            x: canvas.midX - size.width / 2,
            y: canvas.midY - size.height / 2,
            width: size.width,
            height: size.height
        )
        return EditorCropSpace(display: display, coverage: coverage)
    }

    func pixelPoint(fromView point: CGPoint) -> CGPoint {
        let scale = pixelsPerPoint
        return CGPoint(
            x: coverage.minX + (point.x - display.minX) * scale,
            y: coverage.minY + (point.y - display.minY) * scale
        )
    }

    func viewPoint(fromPixel point: CGPoint) -> CGPoint {
        let scale = pixelsPerPoint
        guard scale > 0 else { return point }
        return CGPoint(
            x: display.minX + (point.x - coverage.minX) / scale,
            y: display.minY + (point.y - coverage.minY) / scale
        )
    }

    func pixelRect(fromView rect: CGRect) -> CGRect {
        let first = pixelPoint(fromView: rect.origin)
        let second = pixelPoint(fromView: CGPoint(x: rect.maxX, y: rect.maxY))
        return CGRect(
            x: min(first.x, second.x),
            y: min(first.y, second.y),
            width: abs(second.x - first.x),
            height: abs(second.y - first.y)
        )
    }

    func viewRect(fromPixel rect: CGRect) -> CGRect {
        let first = viewPoint(fromPixel: rect.origin)
        let second = viewPoint(fromPixel: CGPoint(x: rect.maxX, y: rect.maxY))
        return CGRect(
            x: min(first.x, second.x),
            y: min(first.y, second.y),
            width: abs(second.x - first.x),
            height: abs(second.y - first.y)
        )
    }

    /// Re-expresses a mark drawn in `other`'s space into this space. The
    /// conversion is exact going through the original pixels; the text box
    /// and the numbered badge scale with the geometry, rotation stays
    /// metadata, and the mark's identity is never touched.
    func convert(_ stroke: Stroke, from other: EditorCropSpace) -> Stroke {
        let factor = other.pixelsPerPoint / pixelsPerPoint
        var result = stroke
        result.points = stroke.points.map { viewPoint(fromPixel: other.pixelPoint(fromView: $0)) }
        if let size = result.textSize {
            result.textSize = CGSize(width: size.width * factor, height: size.height * factor)
        }
        if let badge = result.badgeSize {
            result.badgeSize = badge * factor
        }
        return result
    }

    /// The space the editor shows for a capture at a given viewport (S16/T9):
    /// the fitted mapping with the viewport composed on top — the fitted
    /// display re-placed inside the canvas by the zoom and pan, the coverage
    /// (which pixels it draws) unchanged. Everything that reads pixels
    /// through a space — drawing, hit-testing, crops, the save — keeps its
    /// exactness, because the mapping keeps going through the same pixel
    /// route.
    static func fitted(coverage: CGRect, viewport: EditorViewport, inCanvas canvas: CGRect) -> EditorCropSpace {
        let base = fitted(coverage: coverage, inCanvas: canvas)
        guard viewport != .identity, canvas.width > 0, canvas.height > 0,
            base.display.width > 0, base.display.height > 0
        else { return base }
        return EditorCropSpace(
            display: viewport.displayRect(fit: base.display, canvas: canvas),
            coverage: coverage
        )
    }
}

/// The crop frame's pure geometry (S1): what the owner's replacement of the
/// dotted treatment is made of — four L brackets at the corners and four
/// short handles centred on the edge midpoints, in the app's selection accent
/// (the same blue the overlay's selection chrome draws). No segment runs
/// along an edge between a bracket and a handle: the dim marks the boundary
/// there instead. Segments are in view space, so the sizes stay what the
/// pointer sees at any zoom.
struct CropFrame {
    /// The bracket arm's length and the frame's stroke weight, view points.
    static let bracketLength: CGFloat = 18
    static let edgeHandleLength: CGFloat = 16
    static let bandWidth: CGFloat = 2.5
    /// The app's selection accent, the same value the board's and overlay's
    /// chrome paint with.
    static let accent = CGColor(srgbRed: 0.25, green: 0.55, blue: 1, alpha: 1)

    /// The eight bracket segments: at each corner two arms running inward
    /// along the edges.
    static func brackets(of rect: CGRect) -> [(from: CGPoint, to: CGPoint)] {
        let corners: [(CGPoint, CGVector)] = [
            (CGPoint(x: rect.minX, y: rect.minY), CGVector(dx: 1, dy: 1)),
            (CGPoint(x: rect.maxX, y: rect.minY), CGVector(dx: -1, dy: 1)),
            (CGPoint(x: rect.minX, y: rect.maxY), CGVector(dx: 1, dy: -1)),
            (CGPoint(x: rect.maxX, y: rect.maxY), CGVector(dx: -1, dy: -1)),
        ]
        return corners.flatMap { corner, inward in
            [
                (corner, CGPoint(x: corner.x + inward.dx * bracketLength, y: corner.y)),
                (corner, CGPoint(x: corner.x, y: corner.y + inward.dy * bracketLength)),
            ]
        }
    }

    /// The four edge handles: short bars centred on each edge's midpoint,
    /// running along the edge.
    static func handles(of rect: CGRect) -> [(from: CGPoint, to: CGPoint)] {
        let half = edgeHandleLength / 2
        return [
            (CGPoint(x: rect.midX - half, y: rect.minY), CGPoint(x: rect.midX + half, y: rect.minY)),
            (CGPoint(x: rect.midX - half, y: rect.maxY), CGPoint(x: rect.midX + half, y: rect.maxY)),
            (CGPoint(x: rect.minX, y: rect.midY - half), CGPoint(x: rect.minX, y: rect.midY + half)),
            (CGPoint(x: rect.maxX, y: rect.midY - half), CGPoint(x: rect.maxX, y: rect.midY + half)),
        ]
    }
}

/// Pure crop geometry: regions are rects in the original capture's pixel
/// space, so every rule here is testable without AppKit.
struct EditorCropRule {
    /// Smallest side a region can keep, in original-image pixels.
    static let minimumSide: CGFloat = 8
    /// How close to a grip the pointer grabs it, in view points.
    static let defaultHandleReach: CGFloat = 10

    /// The rect the drag spans, direction-independent.
    static func marquee(between first: CGPoint, and second: CGPoint) -> CGRect {
        CGRect(
            x: min(first.x, second.x),
            y: min(first.y, second.y),
            width: abs(first.x - second.x),
            height: abs(first.y - second.y)
        )
    }

    /// Intersects the region back inside the image.
    static func clamped(_ region: CGRect, in bounds: CGRect) -> CGRect {
        region.intersection(bounds)
    }

    /// Commits the drag onto the pixel grid without letting the snap grow
    /// past the image, and keeps the region takeable even when the clamp
    /// squeezed it below the smallest side: the minimum is re-applied here
    /// so a caller cannot commit an unusable region by passing one (S7).
    static func snapped(_ region: CGRect, in bounds: CGRect) -> CGRect {
        var result = clamped(region.integral, in: bounds)
        if result.width < minimumSide, bounds.width >= minimumSide {
            let x = min(max(result.minX, bounds.minX), bounds.maxX - minimumSide)
            result.origin.x = x
            result.size.width = minimumSide
        }
        if result.height < minimumSide, bounds.height >= minimumSide {
            let y = min(max(result.minY, bounds.minY), bounds.maxY - minimumSide)
            result.origin.y = y
            result.size.height = minimumSide
        }
        return result
    }

    /// Whether the region is big enough to apply.
    static func isTakeable(_ region: CGRect) -> Bool {
        region.width >= minimumSide && region.height >= minimumSide
    }

    /// A drag on `handle` moves only the dragged side or sides; the pointer
    /// may overshoot the image or the opposite edge, so each moved edge
    /// clamps between the image border and the minimum distance from its
    /// opposite edge — the region can grow back to the border and shrink to
    /// the minimum, but never inverts (S7).
    static func region(
        from start: CGRect,
        dragging handle: CropHandle,
        to pointer: CGPoint,
        in bounds: CGRect
    ) -> CGRect {
        var result = start
        switch handle {
        case .left, .topLeft, .bottomLeft:
            let newMinX = min(max(pointer.x, bounds.minX), start.maxX - minimumSide)
            result.origin.x = newMinX
            result.size.width = start.maxX - newMinX
        case .right, .topRight, .bottomRight:
            result.size.width = min(max(pointer.x, start.minX + minimumSide), bounds.maxX) - start.minX
        case .top, .bottom: break
        }
        switch handle {
        case .top, .topLeft, .topRight:
            let newMinY = min(max(pointer.y, bounds.minY), start.maxY - minimumSide)
            result.origin.y = newMinY
            result.size.height = start.maxY - newMinY
        case .bottom, .bottomLeft, .bottomRight:
            result.size.height = min(max(pointer.y, start.minY + minimumSide), bounds.maxY) - start.minY
        case .left, .right: break
        }
        return result
    }

    /// Repositions the region by a pixel delta, clamped so it never leaves
    /// the image: the size never changes.
    /// The same corner resize with the START RECT's aspect ratio held: the
    /// pointer drives one axis, the other follows so the shape never
    /// distorts, and the corner opposite the dragged handle stays put.
    ///
    /// This is the Shift rule the board's V tool asks for, kept beside the
    /// free one so every surface that resizes with these handles gets the same
    /// answer instead of each writing its own aspect maths.
    static func lockedRegion(
        from start: CGRect,
        dragging handle: CropHandle,
        to pointer: CGPoint,
        in bounds: CGRect
    ) -> CGRect {
        guard start.width > 0, start.height > 0 else {
            return region(from: start, dragging: handle, to: pointer, in: bounds)
        }
        let free = region(from: start, dragging: handle, to: pointer, in: bounds)
        let ratio = start.width / start.height
        // The axis the pointer moved more drives the other: a vertical drag
        // feels like it is setting the height, and the width follows.
        let horizontal = abs(free.width - start.width) >= abs(free.height - start.height)
        let width = horizontal ? free.width : free.height * ratio
        let height = horizontal ? free.width / ratio : free.height
        // Anchor the corner opposite the handle: right/bottom handles keep the
        // origin, left/top ones keep the far edge.
        // A handle on the leading or top edge moves THAT edge, so the opposite
        // one is what stays put — the same anchor the free rule uses.
        let movesLeading = handle == .left || handle == .topLeft || handle == .bottomLeft
        let movesTop = handle == .top || handle == .topLeft || handle == .topRight
        var locked = CGRect(
            x: movesLeading ? free.maxX - width : free.minX,
            y: movesTop ? free.maxY - height : free.minY,
            width: width,
            height: height
        )
        // Never let the lock push the shape off the canvas the drag began on.
        if locked.maxX > bounds.maxX { locked.origin.x = max(bounds.minX, bounds.maxX - width) }
        if locked.maxY > bounds.maxY { locked.origin.y = max(bounds.minY, bounds.maxY - height) }
        if locked.minX < bounds.minX { locked.origin.x = bounds.minX }
        if locked.minY < bounds.minY { locked.origin.y = bounds.minY }
        return locked
    }

    static func region(from start: CGRect, movedBy delta: CGPoint, in bounds: CGRect) -> CGRect {
        let x = min(max(start.minX + delta.x, bounds.minX), bounds.maxX - start.width)
        let y = min(max(start.minY + delta.y, bounds.minY), bounds.maxY - start.height)
        return CGRect(origin: CGPoint(x: x, y: y), size: start.size)
    }

    /// Which grip the pointer grabs on the region's view rect, if any.
    /// Corners win over edges.
    static func handle(at point: CGPoint, on region: CGRect, reach: CGFloat = defaultHandleReach) -> CropHandle? {
        let grips: [(CGPoint, CropHandle)] = [
            (CGPoint(x: region.minX, y: region.minY), .topLeft),
            (CGPoint(x: region.maxX, y: region.minY), .topRight),
            (CGPoint(x: region.minX, y: region.maxY), .bottomLeft),
            (CGPoint(x: region.maxX, y: region.maxY), .bottomRight),
        ]
        for (anchor, grip) in grips
        where abs(point.x - anchor.x) <= reach && abs(point.y - anchor.y) <= reach {
            return grip
        }
        let alongWidth = point.x >= region.minX - reach && point.x <= region.maxX + reach
        let alongHeight = point.y >= region.minY - reach && point.y <= region.maxY + reach
        if alongWidth {
            if abs(point.y - region.minY) <= reach { return .top }
            if abs(point.y - region.maxY) <= reach { return .bottom }
        }
        if alongHeight {
            if abs(point.x - region.minX) <= reach { return .left }
            if abs(point.x - region.maxX) <= reach { return .right }
        }
        return nil
    }
}

/// The applied crop's own history (S7): which region is live and the steps
/// undo/redo reverse. Crops share ONE journal with the marks (and, T12/S19
/// slice 2, with the canvas layers) so ⌘Z always pops the change that
/// happened last, whatever kind it was.
struct EditorCropRecord: Equatable {
    enum Step: Equatable {
        case marks
        case crop(previous: CGRect?)
        /// One canvas step: `previous` is the layer list before the change —
        /// an append, a remove, a restack or one whole drag. Layers are
        /// values, so the snapshot is the restore.
        case canvas(previous: [CanvasLayer])
    }

    private(set) var region: CGRect?
    /// The newest journal state of the canvas layers, exactly as `region` is
    /// the newest region: every journalled change refreshes it, undo and redo
    /// read the restore from it. ONE journal owns both directions; the canvas
    /// keeps no second undo system.
    private(set) var canvasLayers: [CanvasLayer] = []
    /// Applied steps, newest last. `marks` mirror the drawing session's own
    /// journal one to one, so a popped `.marks` delegates to it.
    private(set) var applied: [Step] = []
    /// Undone steps, newest last; `redo` reapplies these.
    private(set) var undone: [Step] = []

    /// What an undone payload step restores, appended at undo time, aligned
    /// with the payload entries (crops and canvas steps) of `undone` in
    /// order.
    private enum RedoTarget: Equatable {
        case crop(CGRect?)
        case canvas([CanvasLayer])
    }
    private var redoTargets: [RedoTarget] = []

    var canUndo: Bool { !applied.isEmpty }
    var canRedo: Bool { !undone.isEmpty }

    /// Applies a new region as one undoable step.
    mutating func crop(to newRegion: CGRect?) {
        applied.append(.crop(previous: region))
        undone.removeAll()
        redoTargets.removeAll()
        region = newRegion
    }

    /// Journals one canvas change as one undoable step: `previous` is what it
    /// changed from, `current` what it changed to — the journal keeps both
    /// directions' values so ⌘Z and ⇧⌘Z need nothing else.
    mutating func canvas(from previous: [CanvasLayer], to current: [CanvasLayer]) {
        applied.append(.canvas(previous: previous))
        undone.removeAll()
        redoTargets.removeAll()
        canvasLayers = current
    }

    /// Journals a committed mark so the shared journal keeps the true order.
    /// Like the drawing session's own commit, it forks the redo history.
    mutating func noteMark() {
        applied.append(.marks)
        undone.removeAll()
        redoTargets.removeAll()
    }

    /// Reverses the newest step: a crop restores its previous region, a
    /// canvas step restores its previous layers, and a mark is routed to the
    /// drawing session by the caller.
    @discardableResult
    mutating func undo() -> Step? {
        guard let step = applied.popLast() else { return nil }
        undone.append(step)
        switch step {
        case .marks: break
        case let .crop(previous):
            redoTargets.append(.crop(region))
            region = previous
        case let .canvas(previous):
            redoTargets.append(.canvas(canvasLayers))
            canvasLayers = previous
        }
        return step
    }

    /// Reapplies the newest undone step.
    @discardableResult
    mutating func redo() -> Step? {
        guard let step = undone.popLast() else { return nil }
        applied.append(step)
        switch step {
        case .marks: break
        case .crop:
            if case let .crop(target) = redoTargets.last {
                redoTargets.removeLast()
                region = target
            }
        case .canvas:
            if case let .canvas(target) = redoTargets.last {
                redoTargets.removeLast()
                canvasLayers = target
            }
        }
        return step
    }

    /// The drawing session was hard-cleared: its history is gone, so the
    /// mark steps leave the journal. The payload steps (crops and canvas
    /// steps) keep their place, and the redo targets stay aligned with them —
    /// by payload-entry position, never by position in `undone`, which mark
    /// entries shift (S7).
    mutating func clearMarkHistory() {
        var survivingTargets: [RedoTarget] = []
        var targetIndex = 0
        for step in undone {
            guard case .marks = step else {
                // A payload entry holds the alignment slot for its target.
                if targetIndex < redoTargets.count {
                    survivingTargets.append(redoTargets[targetIndex])
                }
                targetIndex += 1
                continue
            }
        }
        redoTargets = survivingTargets
        // `removeAll(where:)` drops what the predicate accepts, so it is the
        // marks that leave, not the crops.
        applied.removeAll {
            if case .marks = $0 { return true }
            return false
        }
        undone.removeAll {
            if case .marks = $0 { return true }
            return false
        }
    }
}

/// The staged crop (T4/S6): dropping the marquee — or finishing a grip drag
/// over an applied region — does NOT cut the pixels. The rectangle waits on
/// screen, grips live, until Return confirms or Escape / picking a tool
/// gives it up. `EditorCropStage` is the pure value of that wait, so the
/// transition rules (staging a drag's preview, keeping or dropping the
/// rectangle at mouseUp, confirming into exactly one journal step,/// cancelling cleanly) are a tested rule instead of flags scattered in the
/// gesture code: the canvas only wires the pointer and the keys into these
/// mutations, and the owner's "hit enter to crop" ask stays a rule, not a
/// sprinkling of booleans.
struct EditorCropStage: Equatable {
    /// The rectangle waiting for Return, in ORIGINAL-pixel space — the same
    /// rect an applied region would be, so all the crop rules read it.
    private(set) var pending: CGRect?
    /// True while a drag is reshaping the rectangle; the hint stays off
    /// during the drag and comes back when it ends.
    private(set) var isDragging = false

    /// Whether a rectangle is staged and waiting for Return.
    var isWaiting: Bool { pending != nil }

    /// Whether the canvas must draw the confirm hint right now.
    var showsHint: Bool { pending != nil && !isDragging }

    /// Adopts the drag's live rectangle as the staged preview.
    mutating func updatePreview(_ rect: CGRect) {
        pending = rect
        isDragging = true
    }

    /// The drag ended: the rectangle keeps waiting — still adjustable
    /// through its grips — unless it is below the minimum side, the old
    /// scratch-drag rule that refused unusable crops (S6).
    mutating func endPreview() {
        isDragging = false
        if let pending, !EditorCropRule.isTakeable(pending) {
            self.pending = nil
        }
    }

    /// Return: hands back the confirmed region — snapped to the pixel grid
    /// inside `bounds` exactly as the old mouseUp apply snapped — or nil
    /// when there is nothing takeable staged (the tool then just disarms).
    @discardableResult
    mutating func confirm(in bounds: CGRect) -> CGRect? {
        isDragging = false
        guard let pending else { return nil }
        self.pending = nil
        return EditorCropRule.isTakeable(pending) ? EditorCropRule.snapped(pending, in: bounds) : nil
    }

    /// Escape — or a tool pick: the rectangle disappears and the staged
    /// state is empty again. Nothing was ever applied, so no caller has to
    /// journal or remember anything.
    mutating func cancel() {
        pending = nil
        isDragging = false
    }
}

/// The picture plus a drawing layer, both in view space. The crop is a live
/// region of the ORIGINAL capture (S7): applying it never rebuilds the
/// bitmap from an already-cropped one, re-entering the crop shows the
/// region's edges again over the whole picture, any grip can be dragged to
/// adjust it, and undo returns to the previous region. The staged flow
/// (T4/S6) sits on top: no drag ever applies the crop, Return does.
final class CaptureEditorCanvas: NSView {
    /// The original capture, never cropped: regions are rects over these
    /// pixels (S7). "Original" here means the capture as arrived, marks
    /// included — new marks compose over it at save and copy time instead of
    /// ever being baked into the region cut.
    private(set) var image: CGImage
    /// Observes the single selection state: picking any tool drops the
    /// staged rectangle together with the crop's marking (T4/S6).
    private var selectionObservation: AnyCancellable?
    /// Observes the per-capture background knobs (T5/S5): a change to any
    /// of the three must invalidate the canvas, or the control is dead —
    /// the defect the owner reported ("cambio las propiedades del bg en el
    /// editor pero no hace nada", L4).
    private var backdropObservations: [AnyCancellable] = []
    var state: EditorState? {
        didSet { observeSelection(); observeBackdrop() }
    }
    private var session = DrawingSession()
    /// The space each mark was recorded in — the display mapping of the
    /// moment it started. Marks are never rewritten; the renderer converts
    /// them below through their own space.
    private var spaces: [UUID: EditorCropSpace] = [:]
    /// The applied crop and its journal (S7): ⌘Z pops crops, marks and
    /// canvas steps in the order they happened.
    private var record = EditorCropRecord()
    /// The composable canvas (S19 slice 2): the original capture as the base
    /// and the layers the editor received. Its placements live in the same
    /// pixel space `EditorCropSpace.coverage` names, so the view maps them
    /// through the ONE crop-space/viewport route — no view coordinates inside
    /// the model, and no second mapping that can drift from the viewport's.
    private(set) var composition: CanvasComposition
    /// The staged rectangle waiting for the user's Return (T4/S6). No drag
    /// applies the crop any more — the pointer only reshapes this through the
    /// stage's rules, and Return is the only route into the journal.
    private var stage = EditorCropStage()
    /// The crop gesture is armed exactly when crop is the editor's selected
    /// item (S6): one state drives the palette's marking and the mouse, never
    /// two flags.
    private var isCropping: Bool {
        state?.isCropMarked ?? false
    }

    // MARK: - Zoom and pan (S16/T9)

    /// The viewport over the current fit: how the capture is zoomed and panned
    /// for precise annotation. The pure rules live in `EditorViewport`
    /// (StareCore); the canvas only feeds it gestures.
    private var viewport = EditorViewport()

    /// Adapts to a new state: sink onto the one selection (S6) so a tool
    /// pick — routed through `EditorState` — also ungates the staged
    /// rectangle, and sink onto the background knobs (S5) so a slider move
    /// repaints the picture the next display pass brings. One selection
    /// state owns the marking; the three knobs own the composed ground.
    private func observeSelection() {
        selectionObservation = state?.$captureSelection.sink { [weak self] selection in
            guard case .tool = selection else { return }
            self?.dropStagedRectangle()
        }
    }

    private func observeBackdrop() {
        guard let state else { return }
        func observe<T>(_ publisher: Published<T>.Publisher) -> AnyCancellable {
            publisher.sink { [weak self] _ in self?.needsDisplay = true }
        }
        backdropObservations = [
            observe(state.$backdropPadding),
            observe(state.$backdropCornerRadius),
            observe(state.$backdropShadow),
        ]
    }

    // MARK: - The composed ground (T5/S5)

    /// The capture composed into its backdrop — the exact pixels the copy,
    /// save and history paths take — or nil when the per-capture background
    /// composes nothing. Memoized on the image and the three values, so the
    /// composition is rebuilt only when a knob moves or the picture changes.
    private var composedGround: (surface: CGImage, margin: Int)? {
        guard let state, state.backdropIsActive else { return nil }
        let padding = CaptureBackdrop.clampedPadding(state.backdropPadding)
        let radius = CaptureBackdrop.clampedCornerRadius(state.backdropCornerRadius)
        if let cached = groundCache,
            cached.source === image,
            cached.padding == padding, cached.radius == radius, cached.shadow == state.backdropShadow {
            return cached.ground
        }
        guard let surface = CaptureBackdrop.composed(
            image,
            padding: padding,
            cornerRadius: radius,
            shadow: state.backdropShadow
        ) else { return nil }
        // The composition pads the capture symmetrically, so the picture's
        // pixel frame inside the surface sits at the uniform margin.
        let margin = (surface.width - image.width) / 2
        let ground = (surface: surface, margin: margin)
        groundCache = (source: image, padding: padding, radius: radius, shadow: state.backdropShadow, ground: ground)
        return ground
    }
    private var groundCache: (source: CGImage, padding: Int, radius: Int, shadow: Bool, ground: (surface: CGImage, margin: Int))?

    /// Grows a pixel coverage to the composed ground's surface: the frame
    /// the editor fits into the canvas when the background composes anything
    /// (S5), so the padded, rounded, shadowed ground is what fits — the
    /// control applies live and the arranged pixels are the delivered ones.
    private func surfaceCoverage(_ coverage: CGRect) -> CGRect {
        guard let ground = composedGround else { return coverage }
        let margin = CGFloat(ground.margin)
        return coverage.insetBy(dx: -margin, dy: -margin)
    }

    /// The drag on the crop. The gesture remembers nothing else: the display
    /// mapping it started with is kept beside it so the geometry stays
    /// stable under the pointer for the whole drag.
    private enum Gesture: Equatable {
        /// A fresh rubber-band selection over the armed view.
        case marquee(start: CGPoint)
        /// A grip of the staged rectangle — or of the applied region while
    /// nothing is staged — is being dragged.
        case adjusting(handle: CropHandle, start: CGRect)
        /// The staged rectangle is being moved by its interior.
        case moving(start: CGRect, grab: CGPoint)
        /// A canvas layer is being moved by its interior: the placement where
        /// the drag began and the pixel the grab took (S19 slice 2).
        case layerMove(id: UUID, start: CGRect, grab: CGPoint)
        /// A canvas layer is being resized across a grip: the placement where
        /// the drag began and the grip itself.
        case layerResize(id: UUID, handle: CropHandle, start: CGRect)
    }
    private var gesture: Gesture?
    private var gestureSpace: EditorCropSpace?
    /// The drawing gesture in flight: the point it started at, whether the
    /// pointer ever moved away, and the committed marks it started with, so
    /// `mouseUp` can tell a genuine edit from a stray click.
    private var drawingStart: CGPoint?
    private var drawingMoved = false
    private var drawingStrokes: [Stroke]?
    /// The live gesture is an eraser drag: it removes marks instead of
    /// starting one, so it commits nothing and journals nothing.
    private var isErasing = false

    init(image: CGImage) {
        self.image = image
        composition = CanvasComposition(base: image)
        super.init(frame: .zero)
        // Drop input (S19 slice 2) and paste input (slice 3): a second capture
        // reaches the editor as a drag session — no capture-history store.
        // The adapter below only converts the drop; the rule is
        // `receiveCapture(atView:)`, which paste shares.
        registerForDraggedTypes([.fileURL, .png, .tiff])
    }

    /// The capture's {app}/{display} naming identity (S5), threaded through
    /// the editor handoff from the ONE resolution the capture tail keeps.
    /// The save panel's default name renders through it and the file the
    /// panel writes carries it, because both come from the one
    /// `savePanelFileName` call with these same values — a preview the save
    /// cannot contradict. `.unknown` is the unknown-identity case: the
    /// tokens refuse and the name falls back to the prefix, exactly as the
    /// Settings preview documents for a pane that cannot know a future
    /// capture. Internal so the tests read what a save panel will show
    /// without running one.
    var fileNameContext = CaptureEditorIdentity.unknown

    /// The canvas's own marks — the read seam the selection tests judge
    /// through (the public surface the composed image already is).
    var marks: [Stroke] { session.strokes }

    /// The selected mark (S3): nil until a select-tool pick arms one.
    private(set) var selectedMarkID: UUID?

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("CaptureEditorCanvas is created in code only")
    }

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }

    // MARK: - Crop geometry

    /// The mapping of the current mode: while the crop is armed the canvas
    /// shows the WHOLE original — the context around the region is what makes
    /// its edges grabbable and growable (S7); otherwise it fits the applied
    /// region, or the whole image while nothing is cropped. The viewport
    /// (S16/T9) composes on top of the fit, so whatever it shows is still the
    /// same one mapping between view and pixels the rest of the editor reads.
    private func displaySpace(armed: Bool) -> EditorCropSpace {
        let full = CGRect(x: 0, y: 0, width: image.width, height: image.height)
        var coverage = full
        if !armed, let region = record.region { coverage = region }
        // S5: the surface the editor fits is the composed ground when the
        // background composes anything — the picture's pixel frame grown by
        // the backdrop's uniform margin — so the control applies live and
        // the view shows the pixels the copy, save and history take.
        coverage = surfaceCoverage(coverage)
        let base = EditorCropSpace.fitted(coverage: coverage, viewport: .identity, inCanvas: bounds)
        reconcileViewport(against: base)
        guard viewport != .identity else { return base }
        return EditorCropSpace(
            display: viewport.displayRect(fit: base.display, canvas: bounds),
            coverage: base.coverage
        )
    }

    /// A fit the viewport was not built for resets it to ⌘0's state: a crop
    /// applied or undone, the window resized, the armed crop's whole-picture
    /// view. The fit is identified by rect AND coverage — two coverages can
    /// share a display rect (a square region fits into the same 200×200 slot
    /// as the whole capture), and only the same rect over the same pixels is
    /// the same ground. A first read adopts the fit without resetting — the
    /// viewport is the identity until a gesture moves it anyway.
    private var lastFit: (display: CGRect, coverage: CGRect)?

    private func reconcileViewport(against base: EditorCropSpace) {
        if let last = lastFit, last != (base.display, base.coverage) {
            viewport = .identity
        }
        lastFit = (base.display, base.coverage)
    }

    /// The viewport's current value, reconciled against the fit — the
    /// reconciled observable state the tests pin and ⌘0 reports.
    var viewportState: EditorViewport {
        _ = displaySpace(armed: isCropping)
        return viewport
    }

    /// The coverage whose fit the current mode's gestures stand on.
    private var currentFitCoverage: CGRect {
        var coverage = fullBounds
        if !isCropping, let region = record.region { coverage = region }
        // The same ground the display fits (S5): zoom and pan clamp against
        // the composed surface's frame, never against a frame the view does
        // not show.
        return surfaceCoverage(coverage)
    }

    /// The fitted display for a coverage, with the viewport reconciled
    /// against it.
    private func fittedBase(for coverage: CGRect) -> CGRect {
        let base = EditorCropSpace.fitted(coverage: coverage, inCanvas: bounds)
        reconcileViewport(against: base)
        return base.display
    }

    /// One multiplicative zoom step (⌘+, ⌘−, ⌘ + scroll, pinch), anchored at
    /// a view point like the board's every zoom: the pixels under the anchor
    /// stay under it (S16).
    func applyZoom(_ factor: CGFloat, anchoredAt anchor: CGPoint? = nil) {
        let fit = fittedBase(for: currentFitCoverage)
        let updated = viewport.zoomed(
            byStep: factor, anchoredAt: anchor ?? pointerAnchor(), fit: fit, canvas: bounds)
        guard updated != viewport else { return }
        viewport = updated
        needsDisplay = true
        Diag.log("editor zoom zoom=\(viewport.zoom) pan=\(viewport.pan)")
    }

    /// Pans by a view-point delta (content follows the pointer), clamped so
    /// the capture stays in sight (S16).
    func pan(byPointerDelta delta: CGSize) {
        let fit = fittedBase(for: currentFitCoverage)
        let updated = viewport.panned(by: delta, fit: fit, canvas: bounds)
        guard updated != viewport else { return }
        viewport = updated
        needsDisplay = true
        Diag.log("editor pan pan=\(viewport.pan)")
    }

    /// ⌘0 — back to the fit: pan and zoom reset together. Marks never move
    /// (they are recorded in the space of the moment they were drawn), so
    /// nothing else changes.
    func resetViewport() {
        guard viewport != .identity else { return }
        viewport = .identity
        needsDisplay = true
        Diag.log("editor viewport reset")
    }

    /// The anchor a keyboard zoom uses: the pointer's view point — keys zoom
    /// where the user is looking — falling back to the canvas centre when the
    /// pointer does not sit on this window. The board's rule, verbatim.
    private func pointerAnchor() -> CGPoint {
        guard let window else { return CGPoint(x: bounds.midX, y: bounds.midY) }
        let location = window.convertPoint(fromScreen: NSEvent.mouseLocation)
        let anchor = convert(location, from: nil)
        return bounds.contains(anchor) ? anchor : CGPoint(x: bounds.midX, y: bounds.midY)
    }

    /// Space is held: drags pan the capture instead of drawing, and a
    /// middle-button drag pans too — the board's gesture, on the editor.
    private var isSpacePanning = false
    private var isMiddlePanning = false
    private var lastPanPoint: CGPoint?
    private var isPanning: Bool { (isSpacePanning || isMiddlePanning) && lastPanPoint != nil }
    /// ⌘ + scroll is zooming: a magnifier cursor shows while the gesture
    /// runs, through the same `ScrollZoom.Gesture` state machine the board
    /// uses, so the direction lock and the momentum rejection come for free.
    private var isZoomScrolling = false
    private var lastZoomScrollDelta: CGFloat = 0
    private var scrollZoomGesture = ScrollZoom.Gesture()

    /// The space strokes are placed in: a live gesture keeps the mapping it
    /// started with, everything else uses the current one.
    private var activeSpace: EditorCropSpace {
        gestureSpace ?? displaySpace(armed: isCropping)
    }

    /// The bounds of the original capture, in its own pixel space.
    private var fullBounds: CGRect {
        CGRect(x: 0, y: 0, width: image.width, height: image.height)
    }

    // MARK: - Drawing

    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        // Adaptive backdrop: the editor has to read in both system appearances.
        context.setFillColor(NSColor.underPageBackgroundColor.cgColor)
        context.fill(bounds)

        let space = activeSpace
        // The pixels the view covers, drawn upright in the flipped view: the
        // full bitmap is placed so `coverage` lands in `display`, and the
        // parts outside the crop are clipped away. When the per-capture
        // background composes anything, the bitmap is the composed GROUND
        // (S5): the exact surface the copy, save and history paths take —
        // the capture inside its padded, rounded, shadowed frame — so the
        // control applies live and the arranged pixels are the delivered
        // ones. The frame math is unchanged: `coverage` already grows to the
        // surface, and the composition pads the capture symmetrically, so
        // the surface is placed at the same margin inside the display.
        let pointsPerPixel = space.pixelsPerPoint > 0 ? 1 / space.pixelsPerPoint : 0
        let ground = composedGround
        let base = ground?.surface ?? image
        let frame = CGRect(
            x: space.display.minX - CGFloat(space.coverage.minX) * pointsPerPixel,
            y: space.display.minY - CGFloat(space.coverage.minY) * pointsPerPixel,
            width: CGFloat(base.width) * pointsPerPixel,
            height: CGFloat(base.height) * pointsPerPixel
        )
        context.saveGState()
        context.clip(to: space.display)
        context.translateBy(x: 0, y: space.display.midY)
        context.scaleBy(x: 1, y: -1)
        context.translateBy(x: 0, y: -space.display.midY)
        context.draw(base, in: frame)
        // The layers ride the same flip and the same mapping (S19 slice 2):
        // z-order bottom to top, each drawn into the view rect its placement
        // maps to through the space — what the save flattens is what shows.
        // They never reach the backdrop's padding: the compositor composes
        // them over the CAPTURE before the backdrop wraps it, so the clip
        // is the picture's own rect (the display's when the background is
        // off — today's exact behaviour).
        let pictureRect = space.display.intersection(space.viewRect(fromPixel: fullBounds))
        context.clip(to: pictureRect)
        for layer in composition.layers {
            context.draw(layer.image, in: space.viewRect(fromPixel: layer.placement))
        }
        context.restoreGState()

        // Every mark is placed through the space it was recorded in, so the
        // crop refitting or the window moving never dislocates it (S7). The
        // marks never reach the backdrop's padding either: the compositor
        // draws them over the capture before the backdrop wraps it (S5).
        // Round four S2: a selection drag replaces its committed mark with
        // the ONE preview on the drawn set, so the dashed chrome (which
        // already tracked the preview) and the ink land together — the frame
        // used to travel alone and the ink dropped in only at mouseUp.
        // Round four S3: blur marks never go through `MarkRenderer.draw`'s
        // geometry stroke here (that path drew only the 0-width outline, while
        // the committed capture was the patch): they paint their redaction
        // live through the ONE dispatch (`drawLiveMark` below, whose blur
        // branch is `drawLiveBlur` — the compositor's own crop rule).
        context.saveGState()
        context.clip(to: space.display.intersection(space.viewRect(fromPixel: fullBounds)))
        let livePreview = selectionPreview
        var marks = session.visibleStrokes
        if let livePreview { marks.removeAll { $0.id == livePreview.id } }
        for mark in marks {
            drawLiveMark(space.convert(mark, from: spaces[mark.id] ?? space), space: space, in: context)
        }
        if let livePreview {
            drawLiveMark(
                space.convert(livePreview, from: spaces[livePreview.id] ?? space),
                space: space, in: context)
        }
        context.restoreGState()

        if isCropping {
            drawCropOverlay(space: space, region: stage.pending ?? record.region, in: context)
            if stage.showsHint {
                drawCropHint(space: space, region: stage.pending, in: context)
            }
        } else {
            // The selected layer's outline, the ⌥-selection made visible —
            // the same white-square vocabulary the crop's grips draw.
            if let id = selectedLayerID, let layer = composition.layer(withID: id) {
                let rect = space.viewRect(fromPixel: layer.placement)
                context.setStrokeColor(CGColor(gray: 1, alpha: 0.9))
                context.setLineWidth(1.5)
                context.addRect(rect)
                context.strokePath()
                let side: CGFloat = 8
                context.setFillColor(CGColor(gray: 1, alpha: 1))
                context.setStrokeColor(CGColor(gray: 0, alpha: 0.5))
                context.setLineWidth(1)
                for grip in [CGPoint(x: rect.minX, y: rect.minY), CGPoint(x: rect.maxX, y: rect.minY),
                             CGPoint(x: rect.minX, y: rect.maxY), CGPoint(x: rect.maxX, y: rect.maxY)] {
                    let square = CGRect(x: grip.x - side / 2, y: grip.y - side / 2, width: side, height: side)
                    context.addRect(square)
                    context.drawPath(using: .fillStroke)
                }
            }
            // S3: the mark selection's chrome, the overlay's own vocabulary —
            // a dashed box, four corner squares and the rotation knob — drawn
            // in view points so the handles keep their on-screen size at any
            // zoom, over the mark converted through its own recorded space.
            drawMarkSelectionChrome(space: space, in: context)
        }
    }

    /// The mark selection's chrome (S3): the overlay's `drawSelectedMarkChrome`
    /// vocabulary over the mark as it now looks (preview included), drawn in
    /// the current view space — the mark is converted from its own recorded
    /// space first, so the box and the handles sit where the mark really is.
    private func drawMarkSelectionChrome(space: EditorCropSpace, in context: CGContext) {
        guard let id = selectedMarkID,
            let stroke = selectionPreview ?? session.strokes.first(where: { $0.id == id })
        else { return }
        let markSpace = spaces[id] ?? space
        let converted = space.convert(stroke, from: markSpace)
        let selection = MarkSelection(stroke: converted)
        let accent = CGColor(srgbRed: 0.25, green: 0.55, blue: 1, alpha: 1)

        context.saveGState()
        context.concatenate(
            Stroke.rotationTransform(around: selection.anchor, by: selection.rotation)
        )
        context.setStrokeColor(accent)
        context.setLineWidth(1.5)
        context.setLineDash(phase: 0, lengths: [5, 4])
        context.addRect(selection.unrotatedBounds)
        context.strokePath()
        context.restoreGState()

        for (handle, point) in selection.handlePoints(
            rotationHandleOffset: MarkSelection.defaultRotationHandleOffset
        ) {
            if handle == .rotation {
                let radius: CGFloat = 5
                context.setFillColor(CGColor(gray: 1, alpha: 1))
                context.fillEllipse(in: CGRect(x: point.x - radius, y: point.y - radius, width: radius * 2, height: radius * 2))
                context.setStrokeColor(accent)
                context.setLineWidth(1.5)
                context.addEllipse(in: CGRect(x: point.x - radius, y: point.y - radius, width: radius * 2, height: radius * 2))
                context.strokePath()
            } else {
                let half: CGFloat = 4
                let square = CGRect(x: point.x - half, y: point.y - half, width: half * 2, height: half * 2)
                context.setFillColor(CGColor(gray: 1, alpha: 1))
                context.fill(square)
                context.setStrokeColor(accent)
                context.setLineWidth(1.5)
                context.stroke(square)
            }
        }
    }

    /// ⌫ with a mark selected: the mark leaves through the session's own
    /// removal — the overlay's own delete route (`session.remove(id:)`),
    /// so a numbered sequence stays gapless; the journal stays silent like
    /// the eraser's (removal is not undoable here, the session's redo keeps
    /// it settable when one exists).
    @discardableResult
    func deleteSelectedMark() -> Bool {
        guard let id = selectedMarkID,
            session.strokes.contains(where: { $0.id == id }) else { return false }
        let removed = session.remove(id: id)
        selectedMarkID = nil
        needsDisplay = true
        if removed { Diag.log("editor delete mark \(id)") }
        return removed
    }

    /// The armed view (S1): the region's edges over the dimmed rest of the
    /// picture, drawn as corner brackets and four edge handles in the accent
    /// colour — the owner's idiom for the crop, replacing the old white border
    /// and grip squares. No solid rule runs between bracket and handle: the
    /// dim marks the boundary there, and the picture keeps its own brightness
    /// inside the region.
    private func drawCropOverlay(space: EditorCropSpace, region: CGRect?, in context: CGContext) {
        guard let region else { return }
        let viewRegion = space.viewRect(fromPixel: region)
        let shroud = CGMutablePath()
        shroud.addRect(bounds)
        shroud.addRect(viewRegion)
        context.setFillColor(CGColor(gray: 0, alpha: 0.35))
        context.addPath(shroud)
        context.fillPath(using: .evenOdd)

        context.setStrokeColor(CropFrame.accent)
        context.setLineWidth(CropFrame.bandWidth)
        context.setLineCap(.round)
        for (from, to) in CropFrame.brackets(of: viewRegion) {
            context.move(to: from)
            context.addLine(to: to)
            context.strokePath()
        }
        for (from, to) in CropFrame.handles(of: viewRegion) {
            context.move(to: from)
            context.addLine(to: to)
            context.strokePath()
        }
    }

    /// The confirm hint (T4/S6): while a rectangle is staged the pixels are
    /// not cut yet, so the picture has to say how to commit. Drawn as a dark
    /// pill with white text — the same vocabulary the overlay's hint uses —
    /// centred above the staged rectangle's top edge so it reads against the
    /// shroud; when the rectangle touches the display's top, it slips inside
    /// under the top edge instead, clamped so it never leaves the picture.
    private func drawCropHint(space: EditorCropSpace, region: CGRect?, in context: CGContext) {
        guard let region else { return }
        let viewRegion = space.viewRect(fromPixel: region)
        let text = "Hit ↵ to crop" as NSString
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 13, weight: .medium),
            .foregroundColor: NSColor.white,
        ]
        let textSize = text.size(withAttributes: attributes)
        let padding = CGSize(width: 14, height: 8)
        let pillWidth = textSize.width + padding.width * 2
        let pillHeight = textSize.height + padding.height * 2
        var y = viewRegion.minY - pillHeight - 10
        if y < space.display.minY + 4 {
            y = viewRegion.minY + 10
        }
        y = min(max(y, space.display.minY), space.display.maxY - pillHeight)
        let pill = CGRect(
            x: space.display.midX - pillWidth / 2,
            y: y,
            width: pillWidth,
            height: pillHeight
        )
        context.setFillColor(CGColor(gray: 0, alpha: 0.74))
        context.addPath(
            CGPath(
                roundedRect: pill,
                cornerWidth: pill.height / 2,
                cornerHeight: pill.height / 2,
                transform: nil
            )
        )
        context.fillPath()
        text.draw(
            at: CGPoint(x: pill.minX + padding.width, y: pill.minY + padding.height),
            withAttributes: attributes
        )
    }

    /// One mark's live rendering (round four S3): blur paints the content
    /// underneath as the redaction patch (the compositor's `drawBlur` rule —
    /// the same source, the same pixel route, the same
    /// `MarkRenderer.redactionPatch` dispatch), every other tool through
    /// `MarkRenderer.draw` exactly as ever.
    private func drawLiveMark(_ stroke: Stroke, space: EditorCropSpace, in context: CGContext) {
        if stroke.tool == .blur {
            withMarkRotation(stroke, in: context) { _ in
                drawLiveBlur(stroke, in: context, space: space)
            }
            return
        }
        MarkRenderer.draw(stroke: stroke, in: context)
    }

    /// The rotation dance the compositor's own blur branch wraps its body in
    /// (the `_ = mark` indirection keeps the two-argument helper shape below
    /// close to the overlay's `withMarkRotation`).
    private func withMarkRotation(
        _ stroke: Stroke, in context: CGContext,
        _ body: (CGContext) -> Void
    ) {
        guard stroke.rotation != 0 else {
            body(context)
            return
        }
        context.saveGState()
        context.concatenate(Stroke.rotationTransform(around: stroke.anchor, by: stroke.rotation))
        body(context)
        context.restoreGState()
    }

    /// The live canvas's blur (round four S3): the content underneath the
    /// mark, redacted through `MarkRenderer.redactionPatch` — exactly the
    /// compositor's `drawBlur`: the crop over the SAME surface the canvas
    /// draws (`composedGround` when the per-capture background composes, the
    /// capture itself otherwise), the crop clipped to the surface (a mark
    /// reaching past the picture never stretches), and the patch drawn at the
    /// intersection with the flip the compositor's own placement uses. The
    /// mark still mints through `DrawingSession.begin`, so preview, live view
    /// and committed capture are one mark's three views.
    private func drawLiveBlur(_ stroke: Stroke, in context: CGContext, space: EditorCropSpace) {
        guard let first = stroke.points.first, let last = stroke.points.last else { return }
        let rect = PathBuilder.normalizedRect(from: first, to: last)
        guard rect.width > 0, rect.height > 0 else { return }
        let source = composedGround?.surface ?? image
        // The patch only exists where the surface is: the crop is the mark's
        // rect clipped to the surface's own frame, in view space, exactly the
        // compositor's intersection rule.
        let surfaceRect = space.viewRect(fromPixel: CGRect(x: 0, y: 0, width: source.width, height: source.height))
        let visible = rect.intersection(surfaceRect)
        guard !visible.isNull, !visible.isEmpty else { return }
        guard let patch = MarkRenderer.redactionPatch(
            source,
            pixelRect: space.pixelRect(fromView: visible),
            style: stroke.redactionStyle,
            seed: stroke.redactionSeed,
            scale: space.pixelsPerPoint
        ) else { return }
        context.saveGState()
        context.clip(to: rect)
        context.translateBy(x: visible.minX, y: visible.maxY)
        context.scaleBy(x: 1, y: -1)
        context.draw(patch, in: CGRect(origin: .zero, size: visible.size))
        context.restoreGState()
    }

    // MARK: - Eraser

    /// The eraser's screen radius, in screen points — the drawing overlay's
    /// circle size, carried over: at any zoom the pointer erases what it
    /// touches, a screen-sized circle.
    private static let eraserRadius: CGFloat = 8

    /// Erases the marks under the pointer. A mark never moves — it keeps the
    /// space of the moment it was drawn (S7) — so the pointer's view point
    /// converts through every evaluated mark's own mapping, and the circle's
    /// radius scales with the same pixels-per-point ratio the mapping uses;
    /// the erase lands where the marks render, hit-test and save, whatever
    /// the zoom or pan was when they went down or stands now. All the actual
    /// removal stays in `DrawingSession.erase` — the one erase path the
    /// drawing overlay already drives — called once per distinct recorded
    /// space so each of its hit tests runs inside the mapping the evaluated
    /// marks live in, never a second erase path beside it.
    private func erase(atView point: CGPoint) {
        let current = activeSpace
        let pixel = current.pixelPoint(fromView: point)
        var removed: [UUID] = []
        var evaluated: [EditorCropSpace] = []
        for id in session.strokes.map(\.id) {
            let markSpace = spaces[id] ?? current
            guard !evaluated.contains(markSpace) else { continue }
            evaluated.append(markSpace)
            removed.append(contentsOf: session.erase(
                at: markSpace.viewPoint(fromPixel: pixel),
                radius: Self.eraserRadius * current.pixelsPerPoint / markSpace.pixelsPerPoint))
        }
        for id in removed { spaces.removeValue(forKey: id) }
        if !removed.isEmpty { Diag.log("editor erase count=\(removed.count)") }
        pruneSelection()
        needsDisplay = true
    }

    // MARK: - Mark selection (S3)

    /// The drawing overlay's edit cursor, working over the marks the editor
    /// owns. The same flow, the same StareCore rules, the same shape of
    /// state: a primary selection, an in-flight preview transformed from the
    /// untouched snapshot, ONE journal step per committed drag. The extra
    /// input the overlay's version carries — one more layer of mapping —
    /// is the mark's own recorded space: every reach, handle and delta below
    /// converts through `spaces[id]`, so a mark selected, moved and adjusted
    /// at any zoom lands where its pixels live (the eraser's rule above,
    /// reused verbatim).

    /// The screen-sized reach grabbing a mark takes, the overlay's own
    /// constant (`selectionHitRadius`): one value, both surfaces.
    private var selectionReach: CGFloat { OverlayView.selectionHitRadius }

    /// The drag on the selected mark. The handle decides, exactly as the
    /// overlay's does: the body moves, a corner resizes uniformly, the knob
    /// rotates.
    private enum MarkSelectionDrag {
        case move(start: CGPoint)
        case scale(handle: MarkHandle)
        case rotate(startAngle: CGFloat)
    }

    /// The untouched snapshot the preview transforms from.
    private var selectionOriginal: Stroke?
    private var selectionPreview: Stroke?
    private var selectionDrag: MarkSelectionDrag?
    /// The mark's own space, captured at drag start.
    private var selectionSpace: EditorCropSpace?

    /// Drops any dead id out of the selection — a mark the eraser took away
    /// must not keep handles pointing at nothing.
    private func pruneSelection() {
        guard let id = selectedMarkID else { return }
        guard session.strokes.contains(where: { $0.id == id }) else {
            selectedMarkID = nil
            return
        }
    }

    /// Gives the selection up: no handles, no drag state left behind.
    func clearMarkSelection() {
        guard selectedMarkID != nil || selectionDrag != nil || selectionOriginal != nil else { return }
        selectedMarkID = nil
        selectionDrag = nil
        selectionOriginal = nil
        selectionPreview = nil
        selectionSpace = nil
        needsDisplay = true
    }

    /// Converts the current view point into the mark's own view space.
    private func localPoint(in markSpace: EditorCropSpace, view point: CGPoint, current: EditorCropSpace) -> CGPoint {
        markSpace.viewPoint(fromPixel: current.pixelPoint(fromView: point))
    }

    /// The screen-constant chrome sizes — handle and knob reach — in a
    /// mark's own space, the eraser radius's own conversion.
    private func chromeScale(for markSpace: EditorCropSpace, current: EditorCropSpace) -> CGFloat {
        guard markSpace.pixelsPerPoint > 0 else { return 1 }
        return current.pixelsPerPoint / markSpace.pixelsPerPoint
    }

    private func beginMarkSelection(at point: CGPoint, in current: EditorCropSpace) {
        // A handle of the already-selected mark wins, exactly as the
        // overlay's beginSelection does: resize and rotation stay grabbable
        // without re-picking the mark first.
        if let id = selectedMarkID,
            let selected = session.strokes.first(where: { $0.id == id }) {
            let markSpace = spaces[id] ?? current
            let local = localPoint(in: markSpace, view: point, current: current)
            let scale = chromeScale(for: markSpace, current: current)
            if let handle = MarkSelection(stroke: selected).handle(
                at: local,
                handleSize: MarkSelection.defaultHandleSize * scale,
                rotationHandleOffset: MarkSelection.defaultRotationHandleOffset * scale) {
                startSelectionDrag(handle, on: selected, at: local, in: markSpace)
                return
            }
        }

        // The topmost mark under the pointer arms its move drag right away —
        // select-and-move is one gesture, the overlay's own rule.
        if let hit = session.strokes.last(where: { stroke in
            let markSpace = spaces[stroke.id] ?? current
            let local = localPoint(in: markSpace, view: point, current: current)
            let scale = chromeScale(for: markSpace, current: current)
            return stroke.isSelectedByCursor(at: local, radius: selectionReach * scale)
        }) {
            selectedMarkID = hit.id
            let markSpace = spaces[hit.id] ?? current
            let local = localPoint(in: markSpace, view: point, current: current)
            let scale = chromeScale(for: markSpace, current: current)
            let handle = MarkSelection(stroke: hit).handle(
                at: local,
                handleSize: MarkSelection.defaultHandleSize * scale,
                rotationHandleOffset: MarkSelection.defaultRotationHandleOffset * scale) ?? .body
            startSelectionDrag(handle, on: hit, at: local, in: markSpace)
            needsDisplay = true
            return
        }

        // Empty canvas: the plain click gives the selection up, and no mark
        // is ever minted — DrawingSession refuses the edit cursor already;
        // the pointer route never reaches `begin` at all.
        if selectedMarkID != nil {
            clearMarkSelection()
            needsDisplay = true
        }
        Diag.log("editor select empty click, selection given up")
    }

    private func startSelectionDrag(_ handle: MarkHandle, on stroke: Stroke, at point: CGPoint, in markSpace: EditorCropSpace) {
        selectionOriginal = stroke
        selectionPreview = nil
        selectionSpace = markSpace
        switch handle {
        case .body:
            selectionDrag = .move(start: point)
        case .topLeft, .topRight, .bottomLeft, .bottomRight:
            selectionDrag = .scale(handle: handle)
        case .rotation:
            let anchor = stroke.anchor
            selectionDrag = .rotate(startAngle: atan2(point.y - anchor.y, point.x - anchor.x))
        }
    }

    /// One preview frame from the untouched snapshot, evaluated in the
    /// mark's own space.
    private func updateSelectionPreview(at viewPoint: CGPoint) {
        guard let drag = selectionDrag, let original = selectionOriginal,
            let markSpace = selectionSpace else { return }
        let current = displaySpace(armed: false)
        let point = localPoint(in: markSpace, view: viewPoint, current: current)
        switch drag {
        case let .move(start):
            selectionPreview = MarkTransform.translated(
                original, by: CGPoint(x: point.x - start.x, y: point.y - start.y))
        case let .scale(handle):
            selectionPreview = MarkTransform.scaled(original, dragging: handle, to: point)
        case let .rotate(startAngle):
            let anchor = original.anchor
            let angle = atan2(point.y - anchor.y, point.x - anchor.x) - startAngle
            selectionPreview = MarkTransform.rotated(original, by: angle)
        }
        needsDisplay = true
    }

    /// Ends the drag: the preview replaces the committed mark exactly once,
    /// journalled as ONE mark step (⌘Z hands the restore to the session,
    /// which holds the previous geometry itself).
    private func commitSelectionDrag() {
        defer {
            selectionDrag = nil
            selectionOriginal = nil
            selectionPreview = nil
            selectionSpace = nil
            needsDisplay = true
        }
        guard let preview = selectionPreview, let original = selectionOriginal,
            preview != original, session.replace(preview) else { return }
        record.noteMark()
        Diag.log("editor transform \(preview.tool.rawValue) rotation=\(preview.rotation)")
    }

    // MARK: - Mouse

    override func mouseDown(with event: NSEvent) {
        // Space-pan (and middle-button pan) wins over every other gesture,
        // as on the board: the drag moves the capture, not a tool.
        if isSpacePanning || event.buttonNumber == 2 {
            isMiddlePanning = event.buttonNumber == 2
            lastPanPoint = convert(event.locationInWindow, from: nil)
            reassertCursor() // pan drag starts → closed hand (S3's vocabulary)
            return
        }
        let point = convert(event.locationInWindow, from: nil)

        if isCropping {
            let space = displaySpace(armed: true)
            let pixel = space.pixelPoint(fromView: point)
            gestureSpace = space
            // The staged rectangle has first claim (T4/S6): while one waits,
            // its grips and interior are what the pointer grabs, so the user
            // can go on adjusting it. Without one, a live applied region's
            // grips and interior do; a fresh marquee replaces whatever was
            // staged.
            if let pending = stage.pending {
                let viewPending = space.viewRect(fromPixel: pending)
                if let grip = EditorCropRule.handle(at: point, on: viewPending) {
                    gesture = .adjusting(handle: grip, start: pending)
                } else if viewPending.contains(point) {
                    gesture = .moving(start: pending, grab: pixel)
                } else {
                    gesture = .marquee(start: pixel)
                }
            } else if let region = record.region {
                let viewRegion = space.viewRect(fromPixel: region)
                if let grip = EditorCropRule.handle(at: point, on: viewRegion) {
                    gesture = .adjusting(handle: grip, start: region)
                } else if viewRegion.contains(point) {
                    gesture = .moving(start: region, grab: pixel)
                } else {
                    gesture = .marquee(start: pixel)
                }
            } else {
                gesture = .marquee(start: pixel)
            }
            needsDisplay = true
            return
        }

        // ⌥ claims a canvas layer (S19 slice 2): the crop owns the pointer
        // when armed, otherwise a drop-in capture is where the gesture goes.
        if event.modifierFlags.contains(.option), !isCropping {
            grabCanvasLayer(at: point)
            return
        }

        guard let state else { return }
        let drawingSpace = displaySpace(armed: false)
        guard drawingSpace.display.contains(point) else { return }

        // S3: the select tool edits the marks the canvas owns — select, then
        // move, resize (corner) or rotate (knob) — the drawing overlay's own
        // flow, here over the editor's recorded spaces. It picks no mark of
        // any tool invisible to the pointer and mints nothing.
        if state.tool.isSelection {
            beginMarkSelection(at: point, in: drawingSpace)
            return
        }

        // The eraser removes marks instead of starting one: the gesture
        // routes straight to `session.erase` — the no-op invisible stroke
        // `begin` used to mint for it was the eraser's editor defect.
        isErasing = state.tool.isEraser
        if isErasing {
            erase(atView: point)
            return
        }
        drawingStart = point
        drawingMoved = false
        drawingStrokes = session.strokes
        // T6b/S13: the editor's marks redact the way the drawing overlay's do
        // — the state mirrors the one preference, so the minted mark stamps it.
        // S2/S3: the spotlight's armed shape rides the state the way
        // `arrowHeadStyle` does, so an editor-drawn spotlight is the shape the
        // user cycled to.
        let stroke = session.begin(
            at: point, tool: state.tool, ink: state.ink,
            redactionStyle: state.redactionStyle,
            spotlightShape: state.spotlightShape)
        spaces[stroke.id] = drawingSpace
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        if isPanning {
            let point = convert(event.locationInWindow, from: nil)
            if let last = lastPanPoint {
                pan(byPointerDelta: CGSize(width: point.x - last.x, height: point.y - last.y))
            }
            lastPanPoint = point
            return
        }
        let point = convert(event.locationInWindow, from: nil)

        if isLayerGesture, let gesture, let space = gestureSpace {
            let pixel = space.pixelPoint(fromView: point)
            switch gesture {
            case let .layerMove(id, _, grab):
                _ = composition.move(id: id, by: CGSize(width: pixel.x - grab.x, height: pixel.y - grab.y))
            case let .layerResize(id, handle, start):
                // Shift holds the layer's shape, the one rule every element
                // resize follows (B4): nothing else in the editor binds it.
                let region = event.modifierFlags.contains(.shift)
                    ? EditorCropRule.lockedRegion(from: start, dragging: handle, to: pixel, in: fullBounds)
                    : EditorCropRule.region(from: start, dragging: handle, to: pixel, in: fullBounds)
                _ = composition.place(id: id, at: region)
            default: break
            }
            needsDisplay = true
            return
        }

        if isCropping, let gesture, let space = gestureSpace {
            let pixel = space.pixelPoint(fromView: point)
            // Every drag only reshapes the STAGED preview (T4/S6): the
            // pixels on screen are still the whole original until Return.
            switch gesture {
            case let .marquee(start):
                stage.updatePreview(EditorCropRule.clamped(
                    EditorCropRule.marquee(between: start, and: pixel), in: fullBounds))
            case let .adjusting(handle, start):
                // Shift holds the start rectangle's aspect ratio (S1): the
                // same locked rule the canvas layers resize with — free drag
                // otherwise.
                stage.updatePreview(
                    event.modifierFlags.contains(.shift)
                        ? EditorCropRule.lockedRegion(from: start, dragging: handle, to: pixel, in: fullBounds)
                        : EditorCropRule.region(from: start, dragging: handle, to: pixel, in: fullBounds))
            case let .moving(start, grab):
                stage.updatePreview(EditorCropRule.region(
                    from: start,
                    movedBy: CGPoint(x: pixel.x - grab.x, y: pixel.y - grab.y),
                    in: fullBounds
                ))
            default: break
            }
            needsDisplay = true
            return
        }

        if isErasing {
            erase(atView: point)
            return
        }

        // S3: a selection drag previews the transform through the same
        // MarkTransform rules the overlay previews with.
        if selectionDrag != nil, selectionOriginal != nil {
            updateSelectionPreview(at: point)
            return
        }

        session.extend(to: point)
        if point != drawingStart {
            drawingMoved = true
        }
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        if isPanning {
            if event.buttonNumber == 2 { isMiddlePanning = false }
            lastPanPoint = nil
            reassertCursor() // drag end → open hand (space held) or the arrow
            return
        }
        // One canvas step per drag (S19 slice 2) — never one per mouse event.
        if isLayerGesture {
            endCanvasLayerDrag()
            return
        }
        if isCropping {
            endCropDrag()
            return
        }
        // The eraser's drag ends where it began in the journal: erasing
        // gained the document nothing undoable — `DrawingSession.undo` never
        // restores erased marks (the eraser's rule) — so it takes no mark
        // step, and the next ⌘Z reaches the previous real change directly.
        if isErasing {
            isErasing = false
            needsDisplay = true
            return
        }
        // S3: the selection drag's end commits the preview as ONE step —
        // one drag, one undoable transform, never one per mouse event.
        if selectionDrag != nil {
            commitSelectionDrag()
            return
        }
        let point = convert(event.locationInWindow, from: nil)
        // A click that never left its mouseDown point has no direction: feeding
        // it to `extend` would append a duplicate sample and `commit` would
        // keep the zero-length mark, a mark that paints nothing. Skipping the
        // extend lets `commit` judge it and throw it away instead (S7).
        if drawingMoved || point != drawingStart {
            session.extend(to: point)
        }
        session.commit()
        // The journal keys off the session's COMMITTED MARKS — what the
        // document actually gained — never off the whole session object and
        // never off the tool (S7). That is why it cannot miss a future tool:
        // whatever gesture a tool uses, its edit has to land in
        // `session.strokes` (a click tool already commits inside `begin`, a
        // drag at `commit`), and any session-only difference — `active`
        // appearing or vanishing, a no-op commit — journals nothing, so a
        // gesture that changed nothing can never eat a ⌘Z.
        if let before = drawingStrokes, session.strokes != before {
            record.noteMark()
        }
        drawingStart = nil
        drawingMoved = false
        drawingStrokes = nil
        needsDisplay = true
    }

    /// The drag ends but the crop does NOT (T4/S6): the rectangle stays on
    /// screen with its grips and the picture is still whole — nothing is
    /// applied at mouseUp any more, whatever kind of drag it was. A preview
    /// below the minimum side stages nothing (the old scratch-drag rule),
    /// and the palette stays marked on the crop while it waits, so the user
    /// can keep adjusting. Return is the only way the pixels are cut —
    /// `confirmStagedCrop`, one journal step, exactly as the old apply ran.
    private func endCropDrag() {
        stage.endPreview()
        gesture = nil
        gestureSpace = nil
        needsDisplay = true
    }

    /// Return (T4/S6): the staged rectangle becomes the applied crop —
    /// snapped to the pixel grid, journalled as one step, and handing the
    /// palette mark back to the remembered tool — the same epilogue the old
    /// mouseUp apply ran. Confirming the region that is already live
    /// journals nothing: a no-op must not be an undoable step (S7).
    private func confirmStagedCrop() {
        guard isCropping else { return }
        defer { needsDisplay = true }
        gesture = nil
        gestureSpace = nil
        if let applied = stage.confirm(in: fullBounds), applied != record.region {
            record.crop(to: applied)
            Diag.log("editor cropped to region \(applied)")
        }
        state?.endCropSelection()
    }

    /// Picking any tool gives the staged rectangle up (T4/S6): it drops with
    /// the crop's marking — one selection state owns both. Nothing was ever
    /// applied, so the journal keeps quiet.
    private func dropStagedRectangle() {
        guard stage.isWaiting else { return }
        stage.cancel()
        needsDisplay = true
    }

    /// Whether the confirm hint is drawn right now — the staged crop's
    /// observable state, which the tests pin instead of reading pixels off
    /// a rendered bitmap.
    var showsCropHint: Bool {
        isCropping && stage.showsHint
    }

    // MARK: - Zoom and pan input (S16/T9)

    /// ⌘ + scroll zooms through the same gesture state machine the board
    /// uses (`ScrollZoom.Gesture`: direction lock, momentum rejection, the
    /// raw content-directed delta) and the same anchored zoom; plain scroll
    /// pans inside the clamp. What an event does — pan, zoom or nothing — is
    /// the pure gate's decision (`ScrollPan.decide` in StareCore), so this
    /// handler is only its adapter: it maps the `NSEvent` onto the gate's
    /// event, applies the pan in the felt direction, and feeds the zoom
    /// gesture the events the gate routes to it.
    override func scrollWheel(with event: NSEvent) {
        let decision = ScrollPan.decide(for: ScrollPan.Event(
            deltaX: event.scrollingDeltaX,
            deltaY: event.scrollingDeltaY,
            isDirectionInvertedFromDevice: event.isDirectionInvertedFromDevice,
            momentumPhase: ScrollZoom.MomentumPhase(rawValue: Int(event.momentumPhase.rawValue)) ?? .none,
            commandHeld: event.modifierFlags.contains(.command),
            zoomGestureLive: isZoomScrolling
        ))
        switch decision {
        case let .pan(delta):
            pan(byPointerDelta: delta)
        case .zoom:
            defer {
                // The gesture's closing phases release the lock (see the
                // board's handler for the probed phase values).
                if event.phase == .ended || event.phase == .cancelled { endZoomScroll() }
            }
            let gestureDecision = scrollZoomGesture.decide(for: ScrollZoom.Event(
                deltaY: event.scrollingDeltaY,
                phase: ScrollZoom.Phase(rawValue: Int(event.phase.rawValue)) ?? .none,
                momentumPhase: ScrollZoom.MomentumPhase(rawValue: Int(event.momentumPhase.rawValue)) ?? .none
            ))
            guard case let .zoom(factor) = gestureDecision else { return }
            applyZoom(factor, anchoredAt: convert(event.locationInWindow, from: nil))
            isZoomScrolling = true
            lastZoomScrollDelta = factor > 1 ? 1 : -1
            reassertCursor()
        case .ignore:
            // A non-⌘ event while the gesture holds is its wind-down (⌘ let
            // go mid-gesture): the gesture ends instead of panning. Momentum
            // belongs to no live gesture — the gate refused it, so the tail
            // of a zoom or a plain flick moves nothing and prolongs nothing.
            if isZoomScrolling, !event.modifierFlags.contains(.command) { endZoomScroll() }
        }
    }

    /// Trackpad pinch: magnification events carry a multiplicative factor
    /// around the pointer — the app's anchoring rule, on the same viewport.
    override func magnify(with event: NSEvent) {
        guard event.magnification != 0 else { return }
        applyZoom(1 + event.magnification, anchoredAt: convert(event.locationInWindow, from: nil))
    }

    // MARK: - Drop input (S19 slice 2)

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        sender.draggingPasteboard.canReadObject(forClasses: [NSImage.self]) ? [.copy] : []
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        let point = convert(sender.draggingLocation, from: nil)
        guard let image = NSImage(pasteboard: sender.draggingPasteboard)?
            .cgImage(forProposedRect: nil, context: nil, hints: nil) else { return false }
        return receiveCapture(image, atView: point) != nil
    }

    private func endZoomScroll() {
        isZoomScrolling = false
        scrollZoomGesture = ScrollZoom.Gesture()
        reassertCursor()
    }


    // MARK: - Clipboard paste (S19 slice 3)

    /// ⌘V: reads an image from the general pasteboard — through its explicit
    /// TIFF or PNG data only, never `NSImage(pasteboard:)`, which would also
    /// resolve a file URL to an image — and hands it to `receiveCapture`, the
    /// same route a drop takes, so the placement, the clamps, the crop-armed
    /// refusal and the ONE journal are not written twice. A pasteboard
    /// carrying no image pastes nothing and journals no step: `receiveCapture`
    /// is never reached, so the value comparison in `mutateCanvas` is never
    /// even entered.
    func pasteFromClipboard() {
        let pasteboard = NSPasteboard.general
        let data = pasteboard.data(forType: .tiff) ?? pasteboard.data(forType: .png)
        guard let data, let image = NSImage(data: data)?
            .cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            Diag.log("editor paste ignored: pasteboard carries no image")
            return
        }
        _ = receiveCapture(image)
        Diag.log("editor pasted \(image.width)x\(image.height)")
    }

    // MARK: - Canvas layers (S19 slice 2)

    /// The layer list of the canvas, in z-order — the model's own value, read
    /// by the tests through the public surface.
    var canvasLayers: [CanvasLayer] { composition.layers }

    /// The layer the keys act on: minted by a ⌥-click, kept until the layer
    /// goes away.
    private var selectedLayerID: UUID?

    var selectedCanvasLayer: CanvasLayer? {
        selectedLayerID.flatMap { composition.layer(withID: $0) }
    }

    /// The applied crop's region as the tests' mapping reads it (read-only
    /// seam; the gesture rules live in `EditorCropRule`).
    var croppedRegion: CGRect? { record.region }

    /// The route a dropped capture takes (S19 slice 2): AppKit's drag session
    /// — the surface route that exists today — hands the editor an image and a
    /// view point, and this rule turns them into one layer centred on the
    /// drop point at the image's own pixel size, clamped by the model.
    /// While the crop is armed the drop is refused: the crop owns the pointer.
    ///
    /// Clipboard paste (S19 slice 3) rides this same machinery rather than a
    /// second placement path: `point == nil` names a paste, which lands
    /// centred on the VISIBLE canvas area — the display rect the current
    /// space maps, the viewport's zoom and pan included — at the image's own
    /// pixel size, and the model clamps it exactly like a drop. The paste
    /// point deliberately does NOT depend on the pointer: a ⌘V while the
    /// pointer sits over another window or off the canvas would otherwise
    /// place the layer out of sight or be refused outright, and neither is a
    /// sane answer for a keyboard gesture with a defined centre.
    @discardableResult
    func receiveCapture(_ image: CGImage, atView point: CGPoint? = nil) -> CanvasLayer? {
        guard !isCropping, image.width > 0, image.height > 0 else { return nil }
        let space = displaySpace(armed: false)
        let pixel: CGPoint
        if let point {
            guard space.display.contains(point) else { return nil }
            pixel = space.pixelPoint(fromView: point)
        } else {
            let centre = CGPoint(x: space.display.midX, y: space.display.midY)
            pixel = space.pixelPoint(fromView: centre)
        }
        let placement = CGRect(
            x: pixel.x - CGFloat(image.width) / 2,
            y: pixel.y - CGFloat(image.height) / 2,
            width: CGFloat(image.width),
            height: CGFloat(image.height))
        var newID: UUID?
        mutateCanvas { newID = $0.append(image, at: placement).id }
        selectedLayerID = newID
        Diag.log("editor canvas layer added \(image.width)x\(image.height)")
        return newID.flatMap { composition.layer(withID: $0) }
    }

    /// Every canvas mutation funnels through here: the change runs on a copy
    /// and only a value change journals one `.canvas` step into the ONE
    /// journal — a no-op (a clamped-away reorder, a click that moved a layer
    /// nowhere) eats no ⌘Z, exactly like the marks' rule.
    private func mutateCanvas(_ change: (inout CanvasComposition) -> Void) {
        var updated = composition
        change(&updated)
        guard updated.layers != composition.layers else { return }
        record.canvas(from: composition.layers, to: updated.layers)
        composition = updated
        needsDisplay = true
    }

    /// The topmost layer whose view rect is under the point, grips included:
    /// the hit is answered in the same space the layer renders in.
    private func layerHit(at point: CGPoint, in space: EditorCropSpace) -> CanvasLayer? {
        let reach = EditorCropRule.defaultHandleReach
        for layer in composition.layers.reversed() {
            let rect = space.viewRect(fromPixel: layer.placement)
                .insetBy(dx: -reach, dy: -reach)
            if rect.contains(point) { return layer }
        }
        return nil
    }

    /// A ⌥ press over a layer claims it: the grip resize-s, the interior
    /// move-s, and the layer takes the selection so the keys can act on it.
    private func grabCanvasLayer(at point: CGPoint) {
        let space = displaySpace(armed: false)
        guard space.display.contains(point), let hit = layerHit(at: point, in: space) else { return }
        selectedLayerID = hit.id
        gestureSpace = space
        canvasDragStart = composition.layers
        let viewRect = space.viewRect(fromPixel: hit.placement)
        if let handle = EditorCropRule.handle(at: point, on: viewRect) {
            gesture = .layerResize(id: hit.id, handle: handle, start: hit.placement)
        } else {
            gesture = .layerMove(id: hit.id, start: hit.placement, grab: space.pixelPoint(fromView: point))
        }
        needsDisplay = true
    }

    private var isLayerGesture: Bool {
        switch gesture {
        case .layerMove, .layerResize: true
        default: false
        }
    }

    /// The layer list where the current drag began, so the whole drag
    /// journals exactly one canvas step — never one per mouse event.
    private var canvasDragStart: [CanvasLayer]?

    /// The drag ends: the placement changes already sit on the composition
    /// (applied live through `move`/`place` and their clamps), and the whole
    /// drag is journalled as one step when the value truly changed.
    private func endCanvasLayerDrag() {
        defer {
            gesture = nil
            gestureSpace = nil
            canvasDragStart = nil
            needsDisplay = true
        }
        guard let start = canvasDragStart, composition.layers != start else { return }
        record.canvas(from: start, to: composition.layers)
        Diag.log("editor canvas layer step layers=\(composition.layers.count)")
    }

    /// ⌫ — the selected layer leaves, one canvas step.
    private func removeSelectedCanvasLayer() -> Bool {
        guard let id = selectedLayerID, composition.layer(withID: id) != nil else { return false }
        mutateCanvas { _ = $0.remove(id: id) }
        selectedLayerID = nil
        return true
    }

    /// `[` sends the selection one step back, `]` one step forward; a
    /// clamped-away restack is a no-op that journals nothing.
    private func restackSelectedCanvasLayer(by delta: Int) -> Bool {
        guard let id = selectedLayerID,
            let current = composition.layers.firstIndex(where: { $0.id == id }) else { return false }
        mutateCanvas { $0.reorder(id: id, to: current + delta) }
        return true
    }

    // MARK: - Gesture cursors (S16/T9)

    /// The running gesture's cursor, derived from the state so every exit
    /// path reverts it simply by clearing that state: closed hand while a
    /// pan drag runs, open hand while space is held, a magnifier while
    /// ⌘ + scroll runs — the board's vocabulary, on the editor.
    private var gestureCursor: NSCursor? {
        if isPanning { return .closedHand }
        if isSpacePanning { return .openHand }
        if isZoomScrolling { return lastZoomScrollDelta >= 0 ? NSCursor.zoomIn : NSCursor.zoomOut }
        return nil
    }

    /// The armed item's cursor (S3, batch A): the editor is where the drawing
    /// happens, so it answers with the active tool's own cursor the way the
    /// overlay does. The armed crop keeps the plain arrow (its staged
    /// rectangle has its own pointer vocabulary), a tool that cannot work over
    /// a still image never shows its cursor here even if the detached state
    /// still carries it, and a missing state leaves the arrow.
    private var toolCursor: NSCursor {
        guard let state, case .tool(let tool) = state.captureSelection,
            tool.worksInCaptureEditor else { return NSCursor.arrow }
        return OverlayView.cursor(for: tool.cursor)
    }

    /// The cursor this layer shows right now: the gesture cursor while a
    /// gesture runs, the tool's cursor otherwise. Every cursor the editor
    /// shows is set here and nowhere else.
    func reassertCursor() {
        (gestureCursor ?? toolCursor).set()
    }

    /// Round four S5: the ONE cursor decision of the editor's window — the
    /// tool (or gesture) glyph while the pointer is over the image, and the
    /// plain arrow over every surface the image is not (the palette row, the
    /// title bar, the window buttons). Nothing in the editor ever answered
    /// for those surfaces before, so the last tool glyph followed the pointer
    /// wherever it went once inside the window. The canvas's own handlers
    /// (cursorUpdate, the crossings below) and the content's routing all
    /// read this one function — no second ambient set().
    func cursor(atWindowPoint point: CGPoint) -> NSCursor {
        let local = convert(point, from: nil)
        guard bounds.contains(local) else { return NSCursor.arrow }
        return gestureCursor ?? toolCursor
    }

    override func cursorUpdate(with event: NSEvent) {
        reassertCursor()
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for area in trackingAreas where area.owner === self { removeTrackingArea(area) }
        // The delivery half of the editor's cursor (S7/3b): AppKit only
        // delivers `cursorUpdate` (and the entry/exit crossings) through a
        // tracking area — cursor rectangles alone cannot answer them, and
        // this canvas declared none, so the cursorUpdate above never ran in
        // the real window no matter what the direct-call test saw. This is
        // the one mechanism every other cursor surface of the app already
        // uses: the overlay canvas, the toolbar bar and panel, and the cards
        // all install exactly this area, and `.activeAlways` is what keeps
        // the cursor honest for a surface that does not depend on the app
        // being active or the window being key.
        addTrackingArea(
            NSTrackingArea(
                rect: bounds,
                options: [.cursorUpdate, .mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                owner: self,
                userInfo: nil
            )
        )
    }

    override func mouseEntered(with event: NSEvent) {
        reassertCursor()
    }

    override func mouseMoved(with event: NSEvent) {
        // Re-assert on every move, the way the overlay canvas does: the
        // window opts in to moves (below), and re-answering on the move —
        // not only on rect crossings — is what kept a stale cursor from
        // coming back there. Round four S5: the moved event is routed to a
        // responder (this canvas was often it), never necessarily to the
        // view under the pointer — so the route asks the ONE decision at
        // the event's OWN location: over the picture that is exactly today's
        // reassertion; over the chrome it is the arrow, and the tool glyph
        // can no longer follow the pointer onto the bar.
        if let content = superview as? CaptureEditorContent {
            content.applyEditorCursor(atWindowPoint: event.locationInWindow)
            return
        }
        reassertCursor()
    }

    override func mouseExited(with event: NSEvent) {
        // The pointer leaving the canvas hands the cursor to the editor's
        // window's next servant — the palette row, the title bar, the window
        // buttons — through the ONE decision this editor answers with
        // (round four S5): the point is off this canvas, so the decision
        // answers the arrow. No content around this canvas (a bare harness
        // window) keeps today's own exit answer; a bare canvas has no chrome
        // of its own to serve.
        if let content = superview as? CaptureEditorContent {
            content.applyEditorCursor(atWindowPoint: event.locationInWindow)
            return
        }
        NSCursor.arrow.set()
    }

    /// The view going away ends any gesture, so nothing stale survives the
    /// editor closing and the next window shows its own cursor.
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard window == nil else { return }
        isSpacePanning = false
        isMiddlePanning = false
        isErasing = false
        lastPanPoint = nil
        isZoomScrolling = false
        scrollZoomGesture = ScrollZoom.Gesture()
        // The layer surface's in-flight state dies with the window too.
        selectedLayerID = nil
        canvasDragStart = nil
    }

    // MARK: - Keyboard

    override func keyDown(with event: NSEvent) {
        // Space pans (the app-wide convention); holding it never draws and
        // never arms anything (S16: the tool keys are untouched).
        if event.keyCode == 49 {
            if !event.isARepeat {
                isSpacePanning = true
                reassertCursor() // space held → open hand
            }
            return
        }
        if event.keyCode == 53 { // Escape
            if isCropping {
                // Cancel the staged rectangle and hand the mark back to the
                // remembered tool (T4/S6). The picture stays exactly as it
                // was — no journal step — and an applied region stays live;
                // undo can still take the applied one back afterwards (S7).
                stage.cancel()
                gesture = nil
                gestureSpace = nil
                state?.endCropSelection()
                needsDisplay = true
            } else if selectedMarkID != nil || selectionDrag != nil {
                // S3: with a mark selected, Escape first gives the selection
                // up instead of costing the user their editor window.
                clearMarkSelection()
            } else {
                window?.close()
            }
            return
        }

        let characters = event.charactersIgnoringModifiers ?? ""

        // T4/S6: Return is the staged rectangle's confirm key — the only way
        // the pixels are cut — and the drawn hint names it exactly. The
        // keypad's Enter (keyCode 76, the second ↵ key) confirms exactly the
        // same way (v0.5 verifier: it used to do nothing). With nothing
        // staged the key is not the editor's: it falls through to super
        // below instead of being swallowed.
        if event.keyCode == 36 || event.keyCode == 76 { // Return or keypad Enter
            if isCropping && stage.isWaiting {
                confirmStagedCrop()
                return
            }
            // Nothing staged: fall through — the responder chain keeps the key.
        }

        if event.modifierFlags.contains(.command) {
            switch event.charactersIgnoringModifiers?.lowercased() {
            case "v": // ⌘V — paste an image from the clipboard onto the canvas (S19 slice 3)
                // A field editor owning the responder chain keeps its own ⌘V:
                // the canvas never steals a text field's paste.
                guard !(window?.firstResponder is NSTextView) else {
                    super.keyDown(with: event)
                    return
                }
                pasteFromClipboard()
                return
            case "z":
                undo()
                return
            case "0": // ⌘0 — pan and zoom back to the fit (S16/T9)
                resetViewport()
                return
            case "+", "=": // ⌘+ / ⌘=
                zoomIn()
                return
            case "-", "_": // ⌘−
                zoomOut()
                return
            default:
                break
            }
            super.keyDown(with: event)
            return
        }

        // Canvas layers (S19 slice 2): ⌫ deletes and `[`/`]` restack the
        // selection none of them is a tool key. Nothing selected — the key is
        // not the editor's: it falls through like Return with nothing staged.
        if !isCropping {
            // S3: a mark selection eats ⌫ first — the mark goes; the canvas
            // layer's own ⌫ only runs with no mark under the selection.
            if event.keyCode == 51, selectedMarkID != nil,
                deleteSelectedMark() { return }
            if event.keyCode == 51, removeSelectedCanvasLayer() { return } // ⌫
            if event.keyCode == 33, restackSelectedCanvasLayer(by: -1) { return } // [
            if event.keyCode == 30, restackSelectedCanvasLayer(by: 1) { return } // ]
        }

        // S4: the one route the canvas already resolves at — the same one
        // the overlay's canvas performs — with the cursor re-assertion the
        // overlay's own tool-key route does (a chosen tool's cursor shows
        // without waiting for the next pointer move).
        if let character = characters.first,
            resolvesArmedKey(character) {
            return
        }

        super.keyDown(with: event)
    }

    override func keyUp(with event: NSEvent) {
        if event.keyCode == 49 {
            isSpacePanning = false
            // Space release → the tool cursor, or the closed hand if a pan
            // drag is still running.
            reassertCursor()
            return
        }
        super.keyUp(with: event)
    }

    /// The key resolver for the armed item and the ink (S4): the ONE route
    /// the canvas's own keyDown performs, exposed so the editor WINDOW can
    /// run it too when a chrome control holds the focus and the responder
    /// chain declined — so `b` arms the blur wherever the focus sits, as it
    /// always did on the drawing overlay, where the floating bar can never
    /// take the keyboard. Only tools the editor offers resolve here: V and T
    /// must not arm a cursor or a text field this surface cannot serve, and
    /// a ⌘-carrying press is never a tool key (⌘V is paste, ⌘Z undo). The
    /// state is detached from the app's preferences (T8/S6), so it routes
    /// over its own in-memory map — the shipped standard one.
    func resolvesArmedKey(_ character: Character) -> Bool {
        guard let state else { return false }
        switch state.shortcutRouter.resolve(character, allowedTools: Tool.captureEditorTools) {
        case .tool(let tool):
            state.tool = tool
            reassertCursor()
            return true
        case .ink(let ink):
            state.ink = ink
            return true
        case .none:
            return false
        }
    }

    /// The window-facing key route (S4): one character, no ⌘ modifier, and
    /// the canvas's own resolver decides. All other keys are not the
    /// editor's armed-item keys.
    func handlesArmedItemKey(with event: NSEvent) -> Bool {
        guard !event.modifierFlags.contains(.command),
            let characters = event.charactersIgnoringModifiers,
            characters.count == 1,
            let character = characters.first else { return false }
        return resolvesArmedKey(character)
    }

    /// ⌘+ / ⌘− — one zoom step, anchored at the pointer like the board's
    /// keys, falling back to the canvas centre.
    func zoomIn() {
        applyZoom(EditorViewport.zoomStep)
    }

    func zoomOut() {
        applyZoom(1 / EditorViewport.zoomStep)
    }

    /// ⌘Z reverses the newest change — a crop, a mark or a canvas step, in
    /// the order they happened (S7, S19 slice 2). The armed palette item does
    /// not move: undo restores the previous region and re-entering the crop
    /// shows it again.
    func undo() {
        if let step = record.undo() {
            switch step {
            case .marks: _ = session.undo()
            case .canvas: adoptCanvasFromJournal()
            case .crop: break
            }
        } else {
            _ = session.undo()
        }
        needsDisplay = true
    }

    func redo() {
        if let step = record.redo() {
            switch step {
            case .marks: _ = session.redo()
            case .canvas: adoptCanvasFromJournal()
            case .crop: break
            }
        } else {
            _ = session.redo()
        }
        needsDisplay = true
    }

    /// Copies the journal's layer restore into the live composition: the ONE
    /// journal owns both directions of a canvas step, the composition stays
    /// its mirror.
    private func adoptCanvasFromJournal() {
        composition.restore(record.canvasLayers)
        if let id = selectedLayerID, composition.layer(withID: id) == nil {
            selectedLayerID = nil
        }
    }

    func clearMarks() {
        session.clear()
        // The mark history died with the clear; the crop steps keep their
        // place in the shared journal (S7).
        record.clearMarkHistory()
        needsDisplay = true
    }

    func beginCrop() {
        // Arming the gesture is arming the selection (S6). With a region
        // applied, the armed view shows its edges over the whole original so
        // they can be grabbed and adjusted again — nothing resets (S7).
        state?.selectCrop()
        needsDisplay = true
        Diag.log("editor crop armed region=\(record.region.map { "\($0)" } ?? "none")")
    }

    /// The image with the edit marks on top, at full capture resolution: the
    /// applied region cut from the ORIGINAL with the marks converted into
    /// that space (S7) — a crop after a crop composes from the original
    /// pixels, so repeated crops never lose pixels.
    func composedImage() -> CGImage? {
        let space = displaySpace(armed: false)
        // The canvas layers flatten FIRST (S19 slice 2): `flattened()` returns
        // the base itself with no layers — the identity slice 1 pinned — so
        // today's save path runs untouched then, byte for byte.
        var base: CGImage
        if composition.layers.isEmpty {
            base = image
        } else if let flattened = composition.flattened() {
            base = flattened
        } else {
            base = image
        }
        if let region = record.region, region != fullBounds {
            guard let cropped = base.cropping(to: region) else { return nil }
            base = cropped
        }
        // The compositor places a mark at `point x scale` measured from the
        // base image's top-left corner, but the marks' view space is the
        // fitted display's, whose origin sits inside the letterbox. The one
        // mapping is `EditorCropSpace`: converting into a space whose display
        // is re-anchored at the base's origin subtracts that letterbox origin
        // while keeping the display's fit, so a mark drawn at a view point is
        // saved at the pixel that point maps to — on every window aspect,
        // the letterboxed axis included (S7/T11). The fit's scale (S16/T9):
        // the target is always the FIT-sized display, never the viewport's
        // zoomed one, so a mark drawn while the editor is zoomed or panned
        // converts through its recorded space into the same fit-sized target
        // — the same stroke drawn at 3× saves exactly the pixels the fit
        // drawing saves. Zoom changes where you look, never what lands in
        // the file. Applied over that mapping, the crop only cuts the base:
        // it never shifts the marks a second time, because the converted
        // coordinates are already region-relative.
        // The zoomed-out letterboxing note above still holds, but the target's
        // coverage stays anchored to the BASE's own frame — the crop region
        // or the whole capture (S5): the compositor places marks from the
        // base's top-left corner, so the composed ground's backdrop margin
        // must not shift them. This is exactly the coverage `displaySpace`
        // names when the background composes nothing, so an inactive
        // backdrop keeps today's bytes exactly.
        let baseCoverage = record.region ?? fullBounds
        let fitted = EditorCropSpace.fitted(coverage: baseCoverage, inCanvas: bounds)
        let target = EditorCropSpace(
            display: CGRect(origin: .zero, size: fitted.display.size),
            coverage: baseCoverage
        )
        let marks = session.strokes.map { target.convert($0, from: spaces[$0.id] ?? space) }
        guard
            let marked = MarkCompositor.composite(marks: marks, over: base, scale: target.pixelsPerPoint)
        else { return nil }
        // The capture's background (T2/S2), composed at exactly this ONE
        // point: copy, the save panel and the history delivery all take their
        // pixels from here, so the three can no longer disagree — and the
        // stored default the editor seeded from is no longer silently
        // ignored by a save. With every parameter off the composition is
        // nothing and the arranged canvas is returned exactly as today,
        // byte for byte.
        return CaptureBackdrop.composed(
            marked,
            padding: state?.backdropPadding ?? 0,
            cornerRadius: state?.backdropCornerRadius ?? 0,
            shadow: state?.backdropShadow ?? false
        ) ?? marked
    }

    /// The image the save panel encodes for `format` (T2/S2): the same
    /// composed pixels `composedImage()` hands the copy and history paths,
    /// plus the ONE extra step `CaptureFile.write` performs before its own
    /// encode — a format that cannot carry alpha would encode the backdrop's
    /// transparent margin as an undefined colour, so it is flattened onto
    /// the backdrop's opaque base. Only when a backdrop is actually applied
    /// (the same guard the composition applies), so an uncomposed save keeps
    /// today's bytes exactly.
    func composedImageForSave(format: CaptureFormat) -> CGImage? {
        guard let composed = composedImage() else { return nil }
        guard format == .jpeg, isActiveBackdrop, let flattened = CaptureBackdrop.flattened(composed) else {
            return composed
        }
        return flattened
    }

    /// Whether the canvas's per-capture background composes at all (T2/S2) —
    /// the same guard `CaptureBackdrop.composed` applies to its parameters.
    private var isActiveBackdrop: Bool {
        state.map { $0.backdropIsActive } ?? false
    }

    // MARK: - Test seam

    /// Replaces the session with one holding `marks`, recorded in the current
    /// display space. The tests use it to pin where a drawn mark lands
    /// without synthesizing a window event chain.
    func seedMarks(_ marks: [Stroke]) {
        let space = displaySpace(armed: false)
        spaces = [:]
        for mark in marks {
            spaces[mark.id] = space
        }
        session = DrawingSession.restored(strokes: marks)
        needsDisplay = true
    }

    func copyToPasteboard() {
        guard let composed = composedImage() else { return }
        let representation = NSBitmapImageRep(cgImage: composed)
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.declareTypes([.png, .tiff], owner: nil)
        if let png = representation.representation(using: .png, properties: [:]) {
            pasteboard.setData(png, forType: .png)
        }
        if let tiff = representation.tiffRepresentation {
            pasteboard.setData(tiff, forType: .tiff)
        }
        Diag.log("editor copied \(composed.width)x\(composed.height)")
    }

    /// The name the save panel's field defaults from — ONE call, used by
    /// the panel itself and by the Settings chain preview, so a template is
    /// never previewed under one name and written under another (S4).
    /// `app` and `displayName` (S5) are the capture's identity when the
    /// capture tail threaded it through the editor handoff, none when it
    /// is not; a missing value refuses its token and the template degrades
    /// to the prefix name, exactly as `fileName(at:)` refuses.
    static func savePanelFileName(
        preference: CapturePreference, at date: Date, calendar: Calendar = .current,
        app: String? = nil, displayName: String? = nil
    ) -> String {
        preference.fileName(at: date, calendar: calendar, app: app, display: displayName)
    }

    /// The save panel defaults to the persisted capture preference: the file
    /// name is `CapturePreference.fileName(at:)` rendered through the one
    /// `savePanelFileName` call with the naming identity THIS capture
    /// arrived with (S5) — the same values the capture tail's folder save
    /// and preview render from, so the panel's field and the written file
    /// can never disagree. The chosen format sets the panel's type and
    /// extension, instead of the hardcoded "Stare.png" (T11/S6).
    func savePanel(preference: CapturePreference, onSaved: (() -> Void)? = nil) {
        // T2/S2: the save encodes the SAME composed pixels the copy path
        // takes, with the one format step `CaptureFile.write` performs
        // (the JPEG flatten — see `composedImageForSave`).
        guard let composed = composedImageForSave(format: preference.format) else { return }
        let panel = NSSavePanel()
        let isPNG = preference.format == .png
        panel.allowedContentTypes = [isPNG ? UTType.png : UTType.jpeg]
        panel.nameFieldStringValue = Self.savePanelFileName(
            preference: preference, at: Date(),
            app: fileNameContext.app, displayName: fileNameContext.displayName
        )
        panel.begin { response in
            guard response == .OK, let url = panel.url,
                let data = CaptureFile.data(for: composed, format: preference.format) else {
                return
            }
            try? data.write(to: url)
            Diag.log("editor saved \(url.lastPathComponent)")
            onSaved?()
        }
    }
}
