import AppKit
import Combine
import SwiftUI
import StareCore
import UniformTypeIdentifiers

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

    func open(
        image: CGImage, capture: CapturePreference = .standard, redactionStyle: RedactionStyle = .blur
    ) {
        let window = CaptureEditorWindow(
            image: image,
            capture: capture,
            redactionStyle: redactionStyle,
            onDeliver: onDeliver
        ) { [weak self] closing in
            self?.windows.removeAll { $0 === closing }
        }
        windows.append(window)
        window.center()
        window.makeFirstResponder(window.contentView?.subviews.first { $0 is CaptureEditorCanvas })
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
        // The user may have come from an inactive accessory app: raise the editor
        // above the frontmost application's windows, not just above our own.
        window.orderFrontRegardless()
        Diag.log("editor opened \(image.width)x\(image.height)")
    }
}

final class CaptureEditorWindow: NSWindow {
    override var canBecomeKey: Bool { true }

    init(
        image: CGImage,
        capture: CapturePreference,
        redactionStyle: RedactionStyle = .blur,
        onDeliver: ((CGImage) -> Void)? = nil,
        onClose: @escaping (CaptureEditorWindow) -> Void
    ) {
        let content = CaptureEditorContent(image: image, capture: capture, redactionStyle: redactionStyle)
        content.onDeliver = onDeliver
        super.init(
            contentRect: CGRect(origin: .zero, size: content.preferredSize),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )

        title = "Edit Capture"
        isReleasedWhenClosed = false
        self.onClose = { onClose($0) }
        contentView = content
        setContentSize(content.preferredSize)
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
    private let chrome: NSHostingView<EditorChrome>
    private let state = EditorState()
    /// The preference the save panel defaults from (T11/S6).
    private let capture: CapturePreference
    /// Where a composed variant goes once the user copies or saves it (L7).
    var onDeliver: ((CGImage) -> Void)?
    var preferredSize: CGSize {
        let image = canvas.image
        let width = min(max(CGFloat(image.width) / 2, 480), 1100)
        let scale = width / CGFloat(image.width)
        let height = CGFloat(image.height) * scale
        // One bar, so the window height follows its real fitting size.
        return CGSize(width: width, height: min(max(height, 260), 760) + chrome.fittingSize.height)
    }

    init(image: CGImage, capture: CapturePreference, redactionStyle: RedactionStyle) {
        self.capture = capture
        canvas = CaptureEditorCanvas(image: image)
        chrome = NSHostingView(
            rootView: EditorChrome(
                state: EditorState(),
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

    override func layout() {
        super.layout()
        let chromeHeight = chrome.fittingSize.height
        chrome.frame = CGRect(x: 0, y: bounds.height - chromeHeight, width: bounds.width, height: chromeHeight)
        canvas.frame = CGRect(x: 0, y: 0, width: bounds.width, height: bounds.height - chromeHeight)
    }
}

/// One bar: the same palette as the overlay, with crop, copy and save added to it.
struct EditorChrome: View {
    @ObservedObject var state: EditorState
    let onUndo: () -> Void
    let onRedo: () -> Void
    let onClear: () -> Void
    let onCrop: () -> Void
    let onCopy: () -> Void
    let onSave: () -> Void
    let onClose: () -> Void

    var body: some View {
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
                // any tool unmarks it. Copy and save are plain actions.
                ToolbarAction(symbolName: "crop", help: "Crop", isSelected: state.isCropMarked, handler: onCrop),
                ToolbarAction(symbolName: "doc.on.doc", help: "Copy", handler: onCopy),
                ToolbarAction(symbolName: "square.and.arrow.down", help: "Save", handler: onSave),
            ],
            // The editor draws over a static captured image: tools that need a
            // live session are not offered here (advisory B).
            toolGroups: Tool.captureEditorGroups
        )
        .padding(.vertical, 6)
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
    var state: EditorState? {
        didSet { observeSelection() }
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
    /// rectangle. One selection state owns both the marking and the
    /// rectangle; the canvas never keeps a second flag of its own.
    private func observeSelection() {
        selectionObservation = state?.$captureSelection.sink { [weak self] selection in
            guard case .tool = selection else { return }
            self?.dropStagedRectangle()
        }
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
        return coverage
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
        // parts outside the crop are clipped away.
        let pointsPerPixel = space.pixelsPerPoint > 0 ? 1 / space.pixelsPerPoint : 0
        let frame = CGRect(
            x: space.display.minX - CGFloat(space.coverage.minX) * pointsPerPixel,
            y: space.display.minY - CGFloat(space.coverage.minY) * pointsPerPixel,
            width: CGFloat(image.width) * pointsPerPixel,
            height: CGFloat(image.height) * pointsPerPixel
        )
        context.saveGState()
        context.clip(to: space.display)
        context.translateBy(x: 0, y: space.display.midY)
        context.scaleBy(x: 1, y: -1)
        context.translateBy(x: 0, y: -space.display.midY)
        context.draw(image, in: frame)
        // The layers ride the same flip and the same mapping (S19 slice 2):
        // z-order bottom to top, each drawn into the view rect its placement
        // maps to through the space — what the save flattens is what shows.
        for layer in composition.layers {
            context.draw(layer.image, in: space.viewRect(fromPixel: layer.placement))
        }
        context.restoreGState()

        // Every mark is placed through the space it was recorded in, so the
        // crop refitting or the window moving never dislocates it (S7).
        context.saveGState()
        context.clip(to: space.display)
        MarkRenderer.draw(
            strokes: session.visibleStrokes.map { space.convert($0, from: spaces[$0.id] ?? space) },
            in: context
        )
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
        }
    }

    /// The armed view: the region's edges over the dimmed rest of the
    /// picture, with the eight grips drawn, so the crop can be taken again
    /// and adjusted (S7).
    private func drawCropOverlay(space: EditorCropSpace, region: CGRect?, in context: CGContext) {
        guard let region else { return }
        let viewRegion = space.viewRect(fromPixel: region)
        let shroud = CGMutablePath()
        shroud.addRect(bounds)
        shroud.addRect(viewRegion)
        context.setFillColor(CGColor(gray: 0, alpha: 0.35))
        context.addPath(shroud)
        context.fillPath(using: .evenOdd)
        context.setStrokeColor(CGColor(gray: 1, alpha: 0.9))
        context.setLineWidth(1.5)
        context.addRect(viewRegion)
        context.strokePath()

        let grips: [CGPoint] = [
            CGPoint(x: viewRegion.minX, y: viewRegion.minY),
            CGPoint(x: viewRegion.midX, y: viewRegion.minY),
            CGPoint(x: viewRegion.maxX, y: viewRegion.minY),
            CGPoint(x: viewRegion.minX, y: viewRegion.midY),
            CGPoint(x: viewRegion.maxX, y: viewRegion.midY),
            CGPoint(x: viewRegion.minX, y: viewRegion.maxY),
            CGPoint(x: viewRegion.midX, y: viewRegion.maxY),
            CGPoint(x: viewRegion.maxX, y: viewRegion.maxY),
        ]
        let side: CGFloat = 8
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.setStrokeColor(CGColor(gray: 0, alpha: 0.5))
        context.setLineWidth(1)
        for grip in grips {
            let square = CGRect(x: grip.x - side / 2, y: grip.y - side / 2, width: side, height: side)
            context.addRect(square)
            context.drawPath(using: .fillStroke)
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
        needsDisplay = true
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
        let stroke = session.begin(at: point, tool: state.tool, ink: state.ink, redactionStyle: state.redactionStyle)
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
                stage.updatePreview(EditorCropRule.region(
                    from: start, dragging: handle, to: pixel, in: fullBounds))
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

    override func cursorUpdate(with event: NSEvent) {
        reassertCursor()
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
            if event.keyCode == 51, removeSelectedCanvasLayer() { return } // ⌫
            if event.keyCode == 33, restackSelectedCanvasLayer(by: -1) { return } // [
            if event.keyCode == 30, restackSelectedCanvasLayer(by: 1) { return } // ]
        }

        if let character = characters.first, let state {
            // Only tools the editor offers resolve here: V and T must not arm
            // a cursor or a text field this surface cannot serve. The editor's
            // state is detached from the app's preferences (T8/S6), so it
            // routes over its own in-memory map — the shipped standard one.
            switch state.shortcutRouter.resolve(character, allowedTools: Tool.captureEditorTools) {
            case .tool(let tool):
                state.tool = tool
                return
            case .ink(let ink):
                state.ink = ink
                return
            case .none:
                break
            }
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
        let fitted = EditorCropSpace.fitted(coverage: space.coverage, inCanvas: bounds)
        let target = EditorCropSpace(
            display: CGRect(origin: .zero, size: fitted.display.size),
            coverage: space.coverage
        )
        let marks = session.strokes.map { target.convert($0, from: spaces[$0.id] ?? space) }
        return MarkCompositor.composite(marks: marks, over: base, scale: target.pixelsPerPoint)
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

    /// The name the save panel's field defaults from — one call, and the
    /// same call with the same inputs the Settings preview makes (S4): no
    /// app, no display. The editor genuinely cannot know either. The capture
    /// instant is gone by the time the panel opens: while the editor is up,
    /// Stare itself is the frontmost application, so even `CaptureAppIdentity`
    /// — the capture path's own resolver — refuses `{app}` by contract (`{app}`
    /// must name what was captured, never the tool), and the only screen the
    /// editor sees is its own window's, never necessarily the captured
    /// display. Asking nothing is the honest answer: with no value the tokens
    /// refuse and the template degrades to the prefix name — the same
    /// fallback the Settings preview shows, never a name the preview does
    /// not promise.
    static func savePanelFileName(
        preference: CapturePreference, at date: Date, calendar: Calendar = .current
    ) -> String {
        preference.fileName(at: date, calendar: calendar, app: nil, display: nil)
    }

    /// The save panel defaults to the persisted capture preference: the file
    /// name is `CapturePreference.fileName(at:)` — the template's rendered
    /// shape, the prefix name when the template is empty or refuses — and
    /// the chosen format sets the panel's type and extension, instead of
    /// the hardcoded "Stare.png" (T11/S6). The inputs are the preview's
    /// inputs (S4): `app` and `display` are `nil`, see `savePanelFileName`.
    func savePanel(preference: CapturePreference, onSaved: (() -> Void)? = nil) {
        guard let composed = composedImage() else { return }
        let panel = NSSavePanel()
        let isPNG = preference.format == .png
        panel.allowedContentTypes = [isPNG ? UTType.png : UTType.jpeg]
        panel.nameFieldStringValue = Self.savePanelFileName(preference: preference, at: Date())
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
