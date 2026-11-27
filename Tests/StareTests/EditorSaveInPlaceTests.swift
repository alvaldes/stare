import AppKit
import StareCore
import UniformTypeIdentifiers
import XCTest

@testable import Stare

/// Editor-save-in-place (odd/tasks/editor-save-in-place.md): "un save no
/// vendria mal en el editor. algo como un btn save y que tenga un key cmd+s
/// que salve los cambios en la imagen que se esta editando sin tener que
/// descargar para tener otro imagen con los cambios."
///
/// The behaviour, decided here: `Save` overwrites the image the editor was
/// opened from — the exact file a Finder open handed it (in its own
/// format), the history entry's stored PNG (never a second entry or a
/// second file), or a capture's folder save under the template name — while
/// `Save As…` keeps its panel and copy behaviour untouched. One composer
/// (`composedImage()`) and one encoder (`CaptureFile.data`) carry the
/// pixels; nothing to overwrite falls back to the Save As panel so the
/// button never lies.
@MainActor
final class EditorSaveInPlaceTests: XCTestCase {
    // MARK: - Harness

    private var tempRoots: [URL] = []

    override func tearDown() {
        for root in tempRoots {
            try? FileManager.default.removeItem(at: root)
        }
        tempRoots.removeAll()
        NSApp.mainMenu = nil
        menuTargets.removeAll()
        super.tearDown()
    }

    private func makeTempDir() -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("editor-save-in-place-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        tempRoots.append(root)
        return root
    }

    private func solid(_ width: Int, _ height: Int, red: CGFloat = 1, blue: CGFloat = 0) -> CGImage {
        let context = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8,
            bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        context.setFillColor(CGColor(srgbRed: red, green: 0, blue: blue, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage()!
    }

    /// A pen mark down the middle, so the editor's composed pixels differ
    /// from the image it opened with — every overwrite test must prove the
    /// overwrite, not a re-encode of unchanged pixels.
    private func mark() -> Stroke {
        Stroke(tool: .pen, ink: .red, points: [CGPoint(x: 16, y: 6), CGPoint(x: 24, y: 12)])
    }

    private func makeEditorWindow(
        image: CGImage, capture: CapturePreference = .standard,
        saveTarget: CaptureEditorSaveTarget = .capture
    ) -> CaptureEditorWindow {
        let window = CaptureEditorWindow(
            image: image, capture: capture, redactionStyle: .blur,
            onDeliver: nil, saveTarget: saveTarget, rewriteHistoryEntry: nil
        ) { _ in }
        window.confineToPrimaryScreen()
        // One layout tick, so the canvas has the real frame the display
        // space fits into (the chrome tests' own idiom).
        window.contentView?.needsLayout = true
        window.contentView?.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        return window
    }

    private func decode(from url: URL) throws -> (CGImage, String?) {
        let source = try XCTUnwrap(CGImageSourceCreateWithURL(url as CFURL, nil), "the file decodes")
        let type = CGImageSourceGetType(source).map { $0 as String }
        let image = try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))
        return (image, type)
    }

    // MARK: - S2: the file an editor was opened from is what Save overwrites

    func testAFileBackedEditorOverwritesThatExactFileWithItsComposedPixels() throws {
        let dir = makeTempDir()
        let url = dir.appendingPathComponent("shot.png")
        // The file on disk holds DIFFERENT pixels than the editor opens
        // with, so an overwrite must change the bytes — a re-encode of
        // unchanged pixels could not.
        try CaptureFile.data(for: solid(40, 20, red: 0, blue: 1), format: .png)!.write(to: url)
        let before = try Data(contentsOf: url)

        let editor = makeEditorWindow(image: solid(40, 20), saveTarget: .storedFile(url))
        defer { editor.orderOut(nil); editor.close() }
        let content = try XCTUnwrap(editor.editorContent)
        content.canvas.seedMarks([mark()])

        let outcome = content.saveInPlace()

        XCTAssertEqual(outcome, .savedOverFile(url), "S2: the edit lands in the exact file it opened from")
        let (decoded, type) = try decode(from: url)
        XCTAssertEqual(type, UTType.png.identifier, "the file keeps its own format")
        XCTAssertEqual(decoded.width, 40)
        XCTAssertEqual(decoded.height, 20)
        XCTAssertNotEqual(try Data(contentsOf: url), before, "the stored pixels were replaced")
        // The composed pixels — the pen mark over the red capture — are what
        // the file now holds, not the blue pixels it was opened with.
        let pixel = try XCTUnwrap(
            NSBitmapImageRep(cgImage: decoded).colorAt(x: 20, y: 8)?.usingColorSpace(.deviceRGB))
        XCTAssertEqual(pixel.redComponent, 1, accuracy: 0.05, "the pen mark over the red capture")
        XCTAssertEqual(pixel.blueComponent, 0, accuracy: 0.05)
    }

    /// "writes that file, in its own format": a JPEG under Open With keeps
    /// its JPEG — the ONE encoder writes the file's format, never the
    /// preference's.
    func testAFileBackedJPEGKeepsItsJPEGFormat() throws {
        let dir = makeTempDir()
        let url = dir.appendingPathComponent("shot.jpg")
        try CaptureFile.data(for: solid(40, 20, red: 0, blue: 1), format: .jpeg)!.write(to: url)

        let editor = makeEditorWindow(image: solid(40, 20), saveTarget: .storedFile(url))
        defer { editor.orderOut(nil); editor.close() }
        let content = try XCTUnwrap(editor.editorContent)
        content.canvas.seedMarks([mark()])

        XCTAssertEqual(content.saveInPlace(), .savedOverFile(url))
        let (_, type) = try decode(from: url)
        XCTAssertEqual(type, UTType.jpeg.identifier, "the file's own format, not the preference's")
    }

    /// S2 canary, naming its spec: the Finder's route is the one that names
    /// the stored file, so a Save from Open With can only ever overwrite
    /// that same file.
    func testTheFindersOpenRouteThreadsTheStoredFileTarget() throws {
        var url = URL(fileURLWithPath: #filePath)
        for _ in 0..<3 { url.deleteLastPathComponent() }
        let source = try String(
            contentsOf: url.appendingPathComponent("Sources/Stare/OverlayController.swift"),
            encoding: .utf8)
        XCTAssertTrue(
            source.contains("openCaptureEditor(image, saveTarget: .storedFile(url))"),
            "S2 canary: the Finder's Open With hands the file URL to the editor handoff")
    }

    // MARK: - S2: the history entry is rewritten, never duplicated

    func testAHistoryBackedEditorRewritesTheEntryAndAddsNoSecondEntry() throws {
        let dir = makeTempDir()
        let store = CaptureHistoryStore(directory: dir)
        let entry = store.add(solid(120, 80, red: 0, blue: 1))
        let fileURL = try XCTUnwrap(store.fileURL(for: entry))
        let before = try Data(contentsOf: fileURL)

        let editor = makeEditorWindow(image: solid(120, 80), saveTarget: .historyEntry(entry.id))
        defer { editor.orderOut(nil); editor.close() }
        let content = try XCTUnwrap(editor.editorContent)
        content.rewriteHistoryEntry = { composed, id in
            store.rewrite(entryID: id, with: composed)
        }
        content.canvas.seedMarks([mark()])

        XCTAssertEqual(content.saveInPlace(), .savedHistoryEntry)
        XCTAssertEqual(store.entries.count, 1, "a save is never a second entry")
        XCTAssertEqual(store.entries.first?.fileName, entry.fileName, "and never a second file")
        XCTAssertEqual(store.entries.first?.id, entry.id, "the entry keeps its id")
        XCTAssertEqual(store.entries.first?.date, entry.date)
        XCTAssertNotEqual(try Data(contentsOf: fileURL), before, "the stored PNG was replaced")
    }

    func testAHistoryBackedSaveRefreshesTheEntryThroughACrop() throws {
        let dir = makeTempDir()
        let store = CaptureHistoryStore(directory: dir)
        let entry = store.add(solid(120, 80))

        let editor = makeEditorWindow(image: solid(120, 80), saveTarget: .historyEntry(entry.id))
        defer { editor.orderOut(nil); editor.close() }
        let content = try XCTUnwrap(editor.editorContent)
        content.rewriteHistoryEntry = { composed, id in
            store.rewrite(entryID: id, with: composed)
        }
        try stageAndConfirmCrop(editor)

        XCTAssertEqual(content.saveInPlace(), .savedHistoryEntry)
        let region = try XCTUnwrap(content.canvas.croppedRegion, "the crop was applied: canvas=\(content.canvas.bounds) frame=\(content.canvas.frame) viewport=\(content.canvas.viewportState)")
        XCTAssertLessThan(region.width, 999_999, "diagnostic: region=\(region) canvas=\(content.canvas.bounds) viewport=\(content.canvas.viewportState)")
        XCTAssertGreaterThan(region.width, 0)
        // The entry's pixel size is what the crop made it — the line the
        // panel reads is the user's image now, not what it used to be.
        XCTAssertEqual(store.entries.first?.pixelWidth, Int(region.width))
        XCTAssertEqual(store.entries.first?.pixelHeight, Int(region.height))
        XCTAssertLessThan(store.entries.first!.pixelWidth, 120, "the crop changed the entry's pixel size")
        XCTAssertEqual(content.canvas.transientHintMessage, "Saved to the capture history")
    }

    /// The one resolution rule of the history-sheet route: Edit hands the
    /// editor the image the store's own cache holds, so a holding entry is
    /// what the editor's Save rewrites.
    func testTheStoreResolvesAHoldingEntryFromTheImageThePanelHandsOut() throws {
        let dir = makeTempDir()
        let store = CaptureHistoryStore(directory: dir)
        let entry = store.add(solid(30, 20))
        let image = try XCTUnwrap(store.image(for: entry))

        XCTAssertEqual(store.entry(for: image)?.id, entry.id, "S2: the panel's Edit image names its entry")
        XCTAssertNil(store.entry(for: solid(30, 20)), "a foreign image is no entry — the capture save keeps it")
    }

    // MARK: - S2: a card's capture takes the folder save a capture would

    func testACardBackedEditorWritesIntoTheFolderWithTheTemplateName() throws {
        let dir = makeTempDir()
        let folder = dir.appendingPathComponent("captures")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        var preference = CapturePreference(format: .png, destination: .folder(path: folder.path))
        preference.fileNameTemplate = "{app}"

        let editor = makeEditorWindow(image: solid(40, 20), capture: preference, saveTarget: .capture)
        defer { editor.orderOut(nil); editor.close() }
        let content = try XCTUnwrap(editor.editorContent)
        content.canvas.fileNameContext = CaptureEditorIdentity(app: "Xcode", displayName: nil)
        content.canvas.seedMarks([mark()])

        let outcome = content.saveInPlace()
        guard case let .savedToFolder(url) = outcome else {
            return XCTFail("S2: a folder-destination capture saves into that folder, got \(outcome)")
        }
        XCTAssertEqual(url, folder.appendingPathComponent("Xcode.png"), "the template name the ONE name call renders")
        let (decoded, type) = try decode(from: url)
        XCTAssertEqual(type, UTType.png.identifier)
        XCTAssertEqual(decoded.width, 40)
        XCTAssertEqual(decoded.height, 20)
    }

    // MARK: - S2/S3: nothing to overwrite falls back to Save As

    func testNothingToOverwriteOpensTheSaveAsPanelInstead() throws {
        let content = CaptureEditorContent(
            image: solid(40, 20),
            capture: CapturePreference(format: .png, destination: .clipboard),
            redactionStyle: .blur)
        // A clipboard destination has nothing on disk to overwrite.
        var asked: [CapturePreference] = []
        content.presentSaveAsPanel = { asked.append($0) }

        XCTAssertEqual(content.saveInPlace(), .savePanelRequested, "the fallback is the Save As panel")
        XCTAssertEqual(asked.count, 1)
        XCTAssertEqual(asked.first?.destination, .clipboard, "the panel runs with the live preference")
        XCTAssertNil(content.canvas.transientHintMessage, "the panel is the feedback; no false success hint")
    }

    func testSaveAsStaysACopyAndNeverOverwritesTheStoredFile() throws {
        let dir = makeTempDir()
        let url = dir.appendingPathComponent("shot.png")
        try CaptureFile.data(for: solid(40, 20, red: 0, blue: 1), format: .png)!.write(to: url)
        let before = try Data(contentsOf: url)

        let editor = makeEditorWindow(image: solid(40, 20), saveTarget: .storedFile(url))
        defer { editor.orderOut(nil); editor.close() }
        let content = try XCTUnwrap(editor.editorContent)
        content.canvas.seedMarks([mark()])
        var asked: [CapturePreference] = []
        content.presentSaveAsPanel = { asked.append($0) }

        // The chrome's Save As arm — not Save. The panel opens (witnessed
        // here; production runs with the real panel) and the opened file is
        // untouched: a copy is a copy.
        let saveAs = try XCTUnwrap(
            content.chrome.rootView.chromeToolbar.extraActions
                .last { $0.help == "Save As…" },
            "the chrome keeps Save As… beside Save")
        saveAs.handler()

        XCTAssertEqual(asked.count, 1, "Save As… asks for the panel")
        XCTAssertEqual(try Data(contentsOf: url), before, "Save As… never overwrites the file it was opened from")
    }

    // MARK: - S4: the button and the route

    func testTheChromeCarriesSaveBesideSaveAs() throws {
        let content = CaptureEditorContent(image: solid(40, 20), capture: .standard, redactionStyle: .blur)
        let shown = content.chrome.rootView.chromeToolbar.extraActions.map { ($0.symbolName, $0.help) }
        XCTAssertTrue(
            shown.contains { $0.0 == "arrow.down.doc" && $0.1 == "Save" },
            "S4: the Save button sits in the editor's chrome: \(shown)")
        XCTAssertTrue(
            shown.contains { $0.0 == "square.and.arrow.down" && $0.1 == "Save As…" },
            "S4: Save As… keeps its export glyph and help")
    }

    /// The chrome's Save arm saves in place: the file-backed editor
    /// overwrites through the real button.
    func testTheChromeSaveButtonSavesInPlace() throws {
        let dir = makeTempDir()
        let url = dir.appendingPathComponent("shot.png")
        try CaptureFile.data(for: solid(40, 20, red: 0, blue: 1), format: .png)!.write(to: url)
        let before = try Data(contentsOf: url)

        let editor = makeEditorWindow(image: solid(40, 20), saveTarget: .storedFile(url))
        defer { editor.orderOut(nil); editor.close() }
        let content = try XCTUnwrap(editor.editorContent)
        content.canvas.seedMarks([mark()])

        let save = try XCTUnwrap(
            content.chrome.rootView.chromeToolbar.extraActions
                .last { $0.help == "Save" },
            "the chrome carries the Save arm")
        save.handler()

        XCTAssertNotEqual(try Data(contentsOf: url), before, "S4: the button overwrites the opened file")
        XCTAssertEqual(content.canvas.transientHintMessage, "Saved to shot.png", "S4: the button shows that it saved")
    }

    /// S4: an honest failure keeps the button honest — a folder destination
    /// that cannot take the file is said, not faked as a save.
    func testAFailedFolderSaveSaysItCouldNot() throws {
        let content = CaptureEditorContent(
            image: solid(40, 20),
            capture: CapturePreference(format: .png, destination: .folder(path: "/no/such/folder/anywhere")),
            redactionStyle: .blur)

        XCTAssertEqual(content.saveInPlace(), .refused)
        XCTAssertEqual(content.canvas.transientHintMessage, "Couldn't save the image")
    }

    /// S4: a detached editor cannot honour a history target — the same
    /// honest refusal, never a crash.
    func testAnUnwiredHistoryTargetRefusesHonestly() {
        let content = CaptureEditorContent(image: solid(40, 20), capture: .standard, redactionStyle: .blur)
        content.saveTarget = .historyEntry(UUID())

        XCTAssertEqual(content.saveInPlace(), .refused)
        XCTAssertEqual(content.canvas.transientHintMessage, "Couldn't save the image")
    }

    // MARK: - S4: ⌘S reaches the editor window and nothing else

    private var menuTargets: [NSObject] = []

    private func saveMenu(closeEditor closeTarget: EditorCloseShortcutTarget, saveTarget: EditorSaveShortcutTarget) -> NSMenu {
        _ = NSApplication.shared
        let settings = SettingsShortcutMenuTarget {}
        menuTargets.append(contentsOf: [settings, closeTarget, saveTarget])
        return AppDelegate.makeMainMenu(openSettings: settings, closeEditor: closeTarget, saveEditor: saveTarget)
    }

    private func commandS() throws -> NSEvent {
        try XCTUnwrap(NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: [.command],
            timestamp: 0, windowNumber: 0, context: nil,
            characters: "s", charactersIgnoringModifiers: "s",
            isARepeat: false, keyCode: 1))
    }

    func testTheAppMenuCarriesSaveEditorOnCommandS() throws {
        let menu = saveMenu(closeEditor: EditorCloseShortcutTarget(), saveTarget: EditorSaveShortcutTarget())
        NSApp.mainMenu = menu
        let item = try XCTUnwrap(
            menu.items.first?.submenu?.items.first {
                $0.action == #selector(EditorSaveShortcutTarget.saveEditorWindow(_:))
            },
            "S4 canary: the app menu carries the Save Editor item")
        XCTAssertEqual(item.title, "Save Editor")
        XCTAssertEqual(item.keyEquivalent, "s")
        XCTAssertEqual(item.keyEquivalentModifierMask, [.command])
        XCTAssertTrue(item.target is EditorSaveShortcutTarget, "the item routes to the editor-only target")
    }

    func testCommandSSavesInTheEditorWindowAndLeavesAnotherWindowAlone() throws {
        try XCTSkipIf(NSScreen.main == nil, "no display: a window cannot be shown")
        let dir = makeTempDir()
        let url = dir.appendingPathComponent("shot.png")
        try CaptureFile.data(for: solid(40, 20, red: 0, blue: 1), format: .png)!.write(to: url)
        let before = try Data(contentsOf: url)

        let editor = makeEditorWindow(image: solid(40, 20), saveTarget: .storedFile(url))
        defer { editor.orderOut(nil); editor.close() }
        let content = try XCTUnwrap(editor.editorContent)
        content.canvas.seedMarks([mark()])

        let other = NSWindow(
            contentRect: CGRect(x: 0, y: 0, width: 260, height: 160),
            styleMask: [.titled, .closable], backing: .buffered, defer: false)
        other.confineToPrimaryScreen()
        other.orderFrontRegardless()
        defer { other.orderOut(nil) }

        // The gate ⌘W uses — the key window when it IS an editor's — reads
        // the editor here, so ⌘S saves through the window's own route.
        let gate: () -> CaptureEditorWindow? = { [editor] in editor }
        let menu = saveMenu(
            closeEditor: EditorCloseShortcutTarget(keyEditorWindow: gate),
            saveTarget: EditorSaveShortcutTarget(keyEditorWindow: gate))
        NSApp.mainMenu = menu

        XCTAssertTrue(menu.performKeyEquivalent(with: try commandS()), "⌘S belongs to the menu's Save Editor")
        XCTAssertNotEqual(try Data(contentsOf: url), before, "S4: ⌘S saved the editor's image in place")
        XCTAssertTrue(other.isVisible, "S4: ⌘S touches only the editor window")

        // The same gate's refusal every other key window gets: another
        // window holding the key leaves the editor's file untouched.
        try CaptureFile.data(for: solid(40, 20, red: 0, blue: 1), format: .png)!.write(to: url)
        let untouched = try Data(contentsOf: url)
        let nilGate: () -> CaptureEditorWindow? = { nil }
        let refusingMenu = saveMenu(
            closeEditor: EditorCloseShortcutTarget(keyEditorWindow: nilGate),
            saveTarget: EditorSaveShortcutTarget(keyEditorWindow: nilGate))
        NSApp.mainMenu = refusingMenu
        XCTAssertTrue(refusingMenu.performKeyEquivalent(with: try commandS()), "the item answers but its gate declined")
        XCTAssertEqual(try Data(contentsOf: url), untouched, "S4: ⌘S never saves into a non-editor window's store")
    }

    /// The launch wires the real menu with the save target — a menu built
    /// only in a test proves nothing about the app's own key pass (the ⌘W
    /// close-test's canary, restated for ⌘S).
    func testTheLaunchWiresTheRealMenuWithTheEditorSaveTarget() throws {
        var url = URL(fileURLWithPath: #filePath)
        for _ in 0..<3 { url.deleteLastPathComponent() }
        let source = try String(
            contentsOf: url.appendingPathComponent("Sources/Stare/AppDelegate.swift"),
            encoding: .utf8)
        XCTAssertTrue(
            source.contains("openSettings: target, closeEditor: editorTarget, saveEditor: saveTarget)"),
            "S4 canary: the launch builds the menu with the editor save target wired")
        XCTAssertTrue(
            source.contains("NSApp.keyWindow as? CaptureEditorWindow"),
            "S4 canary: the gate reads the key window the way production dispatches ⌘S")
    }

    // MARK: - The store's own rewrite (S2)

    func testTheStoreRewriteKeepsTheEntryAndRefreshesItsPixels() throws {
        let dir = makeTempDir()
        let store = CaptureHistoryStore(directory: dir)
        let entry = store.add(solid(120, 80), date: Date(timeIntervalSince1970: 100))
        let fileURL = try XCTUnwrap(store.fileURL(for: entry))
        let before = try Data(contentsOf: fileURL)
        let smaller = solid(60, 40)

        XCTAssertTrue(store.rewrite(entryID: entry.id, with: smaller))
        XCTAssertEqual(store.entries.count, 1, "never a second entry")
        XCTAssertEqual(store.entries.first?.fileName, entry.fileName, "never a second file")
        XCTAssertEqual(store.entries.first?.id, entry.id)
        XCTAssertEqual(store.entries.first?.date, entry.date)
        XCTAssertEqual(store.entries.first?.pixelWidth, 60, "the pixel size is what the save made it")
        XCTAssertEqual(store.entries.first?.pixelHeight, 40)
        XCTAssertNotEqual(try Data(contentsOf: fileURL), before, "the stored PNG was replaced in place")
        // A fresh store on the same directory sees the rewrite, so the
        // refresh survives the session.
        let reloaded = CaptureHistoryStore(directory: dir)
        XCTAssertEqual(reloaded.entries.first?.pixelWidth, 60)
        XCTAssertFalse(store.rewrite(entryID: UUID(), with: smaller), "an unknown entry refuses")
    }

    // MARK: - The staged crop, driven through the real window

    private func stageAndConfirmCrop(_ editor: CaptureEditorWindow) throws {
        let content = try XCTUnwrap(editor.editorContent)
        content.state.selectCrop()
        let canvas = content.canvas
        let frame = canvas.frame
        try XCTSkipUnless(frame.width > 0 && frame.height > 0, "no laid-out canvas to drive")
        // One run-loop tick so the window's first layout has settled before
        // the synthetic drags measure the fitted display (the chrome tests'
        // idiom) — without it the fit can still be the un-laid one and the
        // marquee can cover the whole image.
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        func event(_ type: NSEvent.EventType, at local: CGPoint) throws -> NSEvent {
            try XCTUnwrap(NSEvent.mouseEvent(
                with: type, location: canvas.convert(local, to: nil),
                modifierFlags: [], timestamp: 0, windowNumber: editor.windowNumber,
                context: nil, eventNumber: 0, clickCount: 1, pressure: 1))
        }
        // The staged rectangle is driven through the canvas's own fitted
        // mapping (`EditorCropSpace`, the ONE space the crop mechanics
        // read), so the synthetic drags name pixels of the picture no
        // matter how wide the canvas letterboxes at the test's layout.
        let space = EditorCropSpace.fitted(
            coverage: CGRect(x: 0, y: 0, width: 120, height: 80), inCanvas: canvas.bounds)
        let from = space.viewPoint(fromPixel: CGPoint(x: 12, y: 16))
        let to = space.viewPoint(fromPixel: CGPoint(x: 108, y: 64))
        canvas.mouseDown(with: try event(.leftMouseDown, at: from))
        canvas.mouseDragged(with: try event(.leftMouseDragged, at: to))
        canvas.mouseUp(with: try event(.leftMouseUp, at: to))
        XCTAssertTrue(canvas.showsCropHint, "the rectangle waits for Return")
        let key = try XCTUnwrap(NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: [],
            timestamp: 0, windowNumber: editor.windowNumber, context: nil,
            characters: "\r", charactersIgnoringModifiers: "\r", isARepeat: false, keyCode: 36))
        canvas.keyDown(with: key)
        XCTAssertFalse(canvas.showsCropHint, "Return confirmed the crop")
    }
}
