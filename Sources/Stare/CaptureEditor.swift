import AppKit
import SwiftUI
import StareCore

/// Editing a capture: the image with the tools on top, crop, copy and save.
/// The capture arrives with its marks already composed, so this is a second layer
/// over a real picture.
final class CaptureEditorController {
    private var windows: [CaptureEditorWindow] = []

    func open(image: CGImage) {
        let window = CaptureEditorWindow(image: image) { [weak self] closing in
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

    init(image: CGImage, onClose: @escaping (CaptureEditorWindow) -> Void) {
        let content = CaptureEditorContent(image: image)
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

    var preferredSize: CGSize {
        let image = canvas.image
        let width = min(max(CGFloat(image.width) / 2, 480), 1100)
        let scale = width / CGFloat(image.width)
        let height = CGFloat(image.height) * scale
        // One bar, so the window height follows its real fitting size.
        return CGSize(width: width, height: min(max(height, 260), 760) + chrome.fittingSize.height)
    }

    init(image: CGImage) {
        canvas = CaptureEditorCanvas(image: image)
        chrome = NSHostingView(
            rootView: EditorChrome(
                state: EditorState(),
                onUndo: {},
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
            onClear: { [weak self] in self?.canvas.clearMarks() },
            onCrop: { [weak self] in self?.canvas.beginCrop() },
            onCopy: { [weak self] in self?.canvas.copyToPasteboard() },
            onSave: { [weak self] in self?.canvas.savePanel() },
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
    let onClear: () -> Void
    let onCrop: () -> Void
    let onCopy: () -> Void
    let onSave: () -> Void
    let onClose: () -> Void

    var body: some View {
        ToolbarView(
            state: state,
            onUndo: onUndo,
            onClear: onClear,
            onDone: onClose,
            extraActions: [
                ToolbarAction(symbolName: "crop", help: "Crop", handler: onCrop),
                ToolbarAction(symbolName: "doc.on.doc", help: "Copy", handler: onCopy),
                ToolbarAction(symbolName: "square.and.arrow.down", help: "Save", handler: onSave),
            ]
        )
        .padding(.vertical, 6)
    }
}

/// The picture plus a drawing layer, both in view space.
final class CaptureEditorCanvas: NSView {
    private(set) var image: CGImage
    var state: EditorState?
    private var session = DrawingSession()
    private var isCropping = false
    private var cropOrigin: CGPoint?
    private var cropRect: CGRect?

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

    /// Where the image sits inside the view, keeping its aspect ratio.
    private var displayRect: CGRect {
        let imageSize = CGSize(width: image.width, height: image.height)
        guard imageSize.width > 0, imageSize.height > 0, bounds.width > 0, bounds.height > 0 else {
            return .zero
        }
        let scale = min(bounds.width / imageSize.width, bounds.height / imageSize.height)
        let size = CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
        return CGRect(
            x: (bounds.width - size.width) / 2,
            y: (bounds.height - size.height) / 2,
            width: size.width,
            height: size.height
        )
    }

    /// Pixels per view point, used for compositing and cropping.
    private var pixelScale: CGFloat {
        let rect = displayRect
        guard rect.width > 0 else { return 1 }
        return CGFloat(image.width) / rect.width
    }

    // MARK: - Drawing

    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        // Adaptive backdrop: the editor has to read in both system appearances.
        context.setFillColor(NSColor.underPageBackgroundColor.cgColor)
        context.fill(bounds)

        let rect = displayRect
        context.saveGState()
        context.translateBy(x: 0, y: rect.midY)
        context.scaleBy(x: 1, y: -1)
        context.translateBy(x: 0, y: -rect.midY)
        context.draw(image, in: rect)
        context.restoreGState()

        context.saveGState()
        context.translateBy(x: rect.minX, y: rect.minY)
        MarkRenderer.draw(strokes: session.visibleStrokes, in: context)
        context.restoreGState()

        if let cropRect {
            let shroud = CGMutablePath()
            shroud.addRect(bounds)
            shroud.addRect(cropRect)
            context.setFillColor(CGColor(gray: 0, alpha: 0.35))
            context.addPath(shroud)
            context.fillPath(using: .evenOdd)
            context.setStrokeColor(CGColor(gray: 1, alpha: 0.9))
            context.setLineWidth(1.5)
            context.addRect(cropRect)
            context.strokePath()
        }
    }

    // MARK: - Mouse

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)

        if isCropping {
            cropOrigin = point
            cropRect = CGRect(origin: point, size: .zero)
            needsDisplay = true
            return
        }

        guard let state, displayRect.contains(point) else { return }
        session.begin(at: point, tool: state.tool, ink: state.ink)
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)

        if isCropping {
            guard let origin = cropOrigin else { return }
            cropRect = PathBuilder.normalizedRect(from: origin, to: point)
            needsDisplay = true
            return
        }

        session.extend(to: point)
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        if isCropping {
            applyCrop()
            return
        }
        session.extend(to: convert(event.locationInWindow, from: nil))
        session.commit()
        needsDisplay = true
    }

    // MARK: - Keyboard

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { // Escape
            if isCropping {
                isCropping = false
                cropOrigin = nil
                cropRect = nil
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

        if let character = characters.first {
            switch ShortcutRouter.resolve(character) {
            case .tool(let tool):
                state?.tool = tool
                return
            case .ink(let ink):
                state?.ink = ink
                return
            case .none:
                break
            }
        }

        super.keyDown(with: event)
    }

    // MARK: - Actions

    func undo() {
        session.undo()
        needsDisplay = true
    }

    func clearMarks() {
        session.clear()
        needsDisplay = true
    }

    func beginCrop() {
        isCropping = true
        cropOrigin = nil
        cropRect = nil
        needsDisplay = true
        Diag.log("editor crop started")
    }

    private func applyCrop() {
        isCropping = false
        defer { needsDisplay = true }

        guard let rect = cropRect, rect.width >= 8, rect.height >= 8 else {
            cropRect = nil
            return
        }
        let display = displayRect
        let local = rect.offsetBy(dx: -display.minX, dy: -display.minY)
        let scale = pixelScale
        let pixelRect = CGRect(
            x: local.minX * scale,
            y: local.minY * scale,
            width: local.width * scale,
            height: local.height * scale
        ).integral

        guard let composed = composedImage(),
              let cropped = composed.cropping(to: pixelRect) else {
            cropRect = nil
            return
        }

        image = cropped
        // The cropped pixels already carry everything that was drawn.
        session.clear()
        cropRect = nil
        Diag.log("editor cropped to \(cropped.width)x\(cropped.height)")
    }

    /// The image with the edit marks on top, at full capture resolution.
    func composedImage() -> CGImage? {
        MarkCompositor.composite(marks: session.strokes, over: image, scale: pixelScale)
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

    func savePanel() {
        guard let composed = composedImage() else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png]
        panel.nameFieldStringValue = "Stare.png"
        panel.begin { response in
            guard response == .OK, let url = panel.url,
                  let png = NSBitmapImageRep(cgImage: composed).representation(using: .png, properties: [:]) else {
                return
            }
            try? png.write(to: url)
            Diag.log("editor saved \(url.lastPathComponent)")
        }
    }
}
