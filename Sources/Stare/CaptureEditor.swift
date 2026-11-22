import AppKit
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

    func open(image: CGImage, capture: CapturePreference = .standard) {
        let window = CaptureEditorWindow(image: image, capture: capture) { [weak self] closing in
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

    init(image: CGImage, capture: CapturePreference, onClose: @escaping (CaptureEditorWindow) -> Void) {
        let content = CaptureEditorContent(image: image, capture: capture)
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

    var preferredSize: CGSize {
        let image = canvas.image
        let width = min(max(CGFloat(image.width) / 2, 480), 1100)
        let scale = width / CGFloat(image.width)
        let height = CGFloat(image.height) * scale
        // One bar, so the window height follows its real fitting size.
        return CGSize(width: width, height: min(max(height, 260), 760) + chrome.fittingSize.height)
    }

    init(image: CGImage, capture: CapturePreference) {
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
            onCopy: { [weak self] in self?.canvas.copyToPasteboard() },
            onSave: { [weak self] in
                guard let self else { return }
                self.canvas.savePanel(preference: self.capture)
            },
            onClose: { [weak self] in self?.window?.close() }
        )
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
/// undo/redo reverse. Crops share ONE journal with the marks so ⌘Z always
/// pops the change that happened last, whatever kind it was.
struct EditorCropRecord: Equatable {
    enum Step: Equatable {
        case marks
        case crop(previous: CGRect?)
    }

    private(set) var region: CGRect?
    /// Applied steps, newest last. `marks` mirror the drawing session's own
    /// journal one to one, so a popped `.marks` delegates to it.
    private(set) var applied: [Step] = []
    /// Undone steps, newest last; `redo` reapplies these.
    private(set) var undone: [Step] = []
    /// The region each undone crop left behind for `redo` to reapply,
    /// aligned with the crop entries of `undone` in order.
    private var redoTargets: [CGRect?] = []

    var canUndo: Bool { !applied.isEmpty }
    var canRedo: Bool { !undone.isEmpty }

    /// Applies a new region as one undoable step.
    mutating func crop(to newRegion: CGRect?) {
        applied.append(.crop(previous: region))
        undone.removeAll()
        redoTargets.removeAll()
        region = newRegion
    }

    /// Journals a committed mark so the shared journal keeps the true order.
    /// Like the drawing session's own commit, it forks the redo history.
    mutating func noteMark() {
        applied.append(.marks)
        undone.removeAll()
        redoTargets.removeAll()
    }

    /// Reverses the newest step: a crop restores its previous region, a mark
    /// is routed to the drawing session by the caller.
    @discardableResult
    mutating func undo() -> Step? {
        guard let step = applied.popLast() else { return nil }
        undone.append(step)
        switch step {
        case .marks: break
        case let .crop(previous):
            redoTargets.append(region)
            region = previous
        }
        return step
    }

    /// Reapplies the newest undone step.
    @discardableResult
    mutating func redo() -> Step? {
        guard let step = undone.popLast() else { return nil }
        applied.append(step)
        if case .crop = step {
            region = redoTargets.popLast() ?? region
        }
        return step
    }

    /// The drawing session was hard-cleared: its history is gone, so the
    /// mark steps leave the journal. The crops keep their place and the redo
    /// targets stay aligned with them — by crop-entry position, never by
    /// position in `undone`, which mark entries shift (S7).
    mutating func clearMarkHistory() {
        var survivingTargets: [CGRect?] = []
        var targetIndex = 0
        for step in undone {
            guard case .crop = step else { continue }
            if targetIndex < redoTargets.count {
                survivingTargets.append(redoTargets[targetIndex])
            }
            targetIndex += 1
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

/// The picture plus a drawing layer, both in view space. The crop is a live
/// region of the ORIGINAL capture (S7): applying it never rebuilds the
/// bitmap from an already-cropped one, re-entering the crop shows the
/// region's edges again over the whole picture, any grip can be dragged to
/// adjust it, and undo returns to the previous region.
final class CaptureEditorCanvas: NSView {
    /// The original capture, never cropped: regions are rects over these
    /// pixels (S7). "Original" here means the capture as arrived, marks
    /// included — new marks compose over it at save and copy time instead of
    /// ever being baked into the region cut.
    private(set) var image: CGImage
    var state: EditorState?
    private var session = DrawingSession()
    /// The space each mark was recorded in — the display mapping of the
    /// moment it started. Marks are never rewritten; the renderer converts
    /// them below through their own space.
    private var spaces: [UUID: EditorCropSpace] = [:]
    /// The applied crop and its journal (S7): ⌘Z pops crops and marks in the
    /// order they happened.
    private var record = EditorCropRecord()
    /// The crop gesture is armed exactly when crop is the editor's selected
    /// item (S6): one state drives the palette's marking and the mouse, never
    /// two flags.
    private var isCropping: Bool {
        state?.isCropMarked ?? false
    }

    /// The drag on the crop. The gesture remembers nothing else: the display
    /// mapping it started with is kept beside it so the geometry stays
    /// stable under the pointer for the whole drag.
    private enum Gesture: Equatable {
        /// A fresh rubber-band selection over the armed view.
        case marquee(start: CGPoint)
        /// A grip of the applied region is being dragged.
        case adjusting(handle: CropHandle, start: CGRect)
        /// The region is being moved by its interior.
        case moving(start: CGRect, grab: CGPoint)
    }
    private var gesture: Gesture?
    private var gestureSpace: EditorCropSpace?
    /// The region taking shape, in original pixels, drawn live during the drag.
    private var pendingRegion: CGRect?

    init(image: CGImage) {
        self.image = image
        super.init(frame: .zero)
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
    /// region, or the whole image while nothing is cropped.
    private func displaySpace(armed: Bool) -> EditorCropSpace {
        let full = CGRect(x: 0, y: 0, width: image.width, height: image.height)
        var coverage = full
        if !armed, let region = record.region { coverage = region }
        return EditorCropSpace.fitted(coverage: coverage, inCanvas: bounds)
    }

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
            drawCropOverlay(space: space, region: pendingRegion ?? record.region, in: context)
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

    // MARK: - Mouse

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)

        if isCropping {
            let space = displaySpace(armed: true)
            let pixel = space.pixelPoint(fromView: point)
            gestureSpace = space
            if let region = record.region {
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
            pendingRegion = nil
            needsDisplay = true
            return
        }

        guard let state else { return }
        let drawingSpace = displaySpace(armed: false)
        guard drawingSpace.display.contains(point) else { return }
        let stroke = session.begin(at: point, tool: state.tool, ink: state.ink)
        spaces[stroke.id] = drawingSpace
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)

        if isCropping, let gesture, let space = gestureSpace {
            let pixel = space.pixelPoint(fromView: point)
            switch gesture {
            case let .marquee(start):
                pendingRegion = EditorCropRule.clamped(
                    EditorCropRule.marquee(between: start, and: pixel), in: fullBounds)
            case let .adjusting(handle, start):
                pendingRegion = EditorCropRule.region(from: start, dragging: handle, to: pixel, in: fullBounds)
            case let .moving(start, grab):
                pendingRegion = EditorCropRule.region(
                    from: start,
                    movedBy: CGPoint(x: pixel.x - grab.x, y: pixel.y - grab.y),
                    in: fullBounds
                )
            }
            needsDisplay = true
            return
        }

        session.extend(to: point)
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        if isCropping {
            finishCropGesture()
            return
        }
        let before = session
        session.extend(to: convert(event.locationInWindow, from: nil))
        session.commit()
        // A committed mark is an edit in the shared journal (S7): ⌘Z must pop
        // it before any crop that came before it. A commit that only threw a
        // stray active mark away (a degenerate stroke) left the marks alone,
        // so the journal stays silent about it.
        if session != before {
            record.noteMark()
        }
        needsDisplay = true
    }

    /// Ends the crop gesture: an adjust or a move commits the preview as one
    /// undoable step; a fresh marquee becomes the region only when it is big
    /// enough — a scratch drag below the minimum leaves the applied region
    /// alone, the way the old rule refused tiny crops. Either way the mark
    /// goes back to the remembered tool (S6).
    private func finishCropGesture() {
        let drawn = pendingRegion
        gesture = nil
        gestureSpace = nil
        pendingRegion = nil
        state?.endCropSelection()
        defer { needsDisplay = true }

        guard let drawn, EditorCropRule.isTakeable(drawn) else { return }
        record.crop(to: EditorCropRule.snapped(drawn, in: fullBounds))
        if let region = record.region {
            Diag.log("editor cropped to region \(region)")
        }
    }

    // MARK: - Keyboard

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { // Escape
            if isCropping {
                // Cancel the gesture and hand the mark back to the remembered
                // tool (S6). The applied region stays live; undo can still take
                // it back afterwards (S7).
                gesture = nil
                gestureSpace = nil
                pendingRegion = nil
                state?.endCropSelection()
                needsDisplay = true
            } else {
                window?.close()
            }
            return
        }

        let characters = event.charactersIgnoringModifiers ?? ""

        if event.modifierFlags.contains(.command) {
            if characters.lowercased() == "z" {
                undo()
                return
            }
            super.keyDown(with: event)
            return
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

    // MARK: - Actions

    /// ⌘Z reverses the newest change — the crop or a mark, in the order they
    /// happened (S7). The armed palette item does not move: undo restores the
    /// previous region and re-entering the crop shows it again.
    func undo() {
        if let step = record.undo() {
            if case .marks = step { _ = session.undo() }
        } else {
            _ = session.undo()
        }
        needsDisplay = true
    }

    func redo() {
        if let step = record.redo() {
            if case .marks = step { _ = session.redo() }
        } else {
            _ = session.redo()
        }
        needsDisplay = true
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
        let base: CGImage
        if let region = record.region, region != fullBounds {
            guard let cropped = image.cropping(to: region) else { return nil }
            base = cropped
        } else {
            base = image
        }
        let marks = session.strokes.map { space.convert($0, from: spaces[$0.id] ?? space) }
        return MarkCompositor.composite(marks: marks, over: base, scale: space.pixelsPerPoint)
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

    /// The save panel defaults to the persisted capture preference: the file
    /// name is `CapturePreference.fileName(at:)` — prefix plus timestamp —
    /// and the chosen format sets the panel's type and extension, instead of
    /// the hardcoded "Stare.png" (T11/S6).
    func savePanel(preference: CapturePreference) {
        guard let composed = composedImage() else { return }
        let panel = NSSavePanel()
        let isPNG = preference.format == .png
        panel.allowedContentTypes = [isPNG ? UTType.png : UTType.jpeg]
        panel.nameFieldStringValue = preference.fileName(at: Date())
        panel.begin { response in
            guard response == .OK, let url = panel.url,
                let data = CaptureFile.data(for: composed, format: preference.format) else {
                return
            }
            try? data.write(to: url)
            Diag.log("editor saved \(url.lastPathComponent)")
        }
    }
}
