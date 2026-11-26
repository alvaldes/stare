# B1 + B4: the capture editor's own surroundings

Two backlog items that are one piece of work: the editor must look and behave like
the app it lives in, and the background controls belong where the image is.

## Specs

- **S1** (verbatim, B1): "el entorno del edit capture debe ser el mismo que el de
  afuera: misma barra configrada, orientacion, no fija arriba y horizontal". The
  editor's palette follows the same rules as the outside bar — the user's own
  tool layout, the user's orientation and docked border, the same materials and
  the same placement rules — instead of a fixed horizontal strip pinned to the top.

- **S2** (verbatim, B4): "todo lo del backgound del capture debe estar en el editor
  (https://cleanshot.com/video/screenshots/bgtool.mp4) en settings solo si quiere que
  se tome por defecto con o sin." Background controls live in the editor; Settings
  keeps only the default of whether a capture is taken with or without one.

- **S3** The editor's item list is not the outside bar's list: the editor needs the
  capture-only actions (crop, pages, copy, save, and the background control). "Same
  bar" therefore means the same geometry, materials, placement and orientation
  rules — not the same items. That boundary is a decision taken here, recorded in
  the log, because the owner delegated the judgement with "termina todo".

## Tasks

| ID | Specs | Task | Route | Commit |
| --- | --- | --- | --- | --- |
| T1 | S1, S3 | The editor's palette answered by the bar's own geometry and orientation rules | worker | 2cba577 |
| T2 | S2 | The background controls in the editor; Settings keeps the default only | worker | 2cba577 |
| T3 | S1-S3 | Docs: CHANGELOG and this log | worker | |

## Log

- **L1** (owner, 2026-11-25, verbatim, two entries of one backlog list): "- el
  entorno del edit capture debe ser el mismo que el de afuera: misma barra
  configrada, orientacion, no fija arriba y horizontal" and "- todo lo del
  backgound del capture debe estar en el editor
  (https://cleanshot.com/video/screenshots/bgtool.mp4) en settings solo si quiere
  que se tome por defecto con o sin."
- **L2** (decision, taken by the agent because the owner asked for the whole
  backlog to be finished): the editor keeps its own item list. Duplicating the
  outside bar's items into the editor would put drawing tools where a capture is
  already being annotated, and the editor genuinely needs actions the bar has no
  concept of. What must match is everything the owner named: the layout he
  configured, the orientation, the docked side, the materials and the placement
  rules. The reference video could not be studied from this harness — the video
  endpoints only yield frames for YouTube and local files — so the background
  control's shape is taken from Stare's own idioms and the owner's words, not from
  CleanShot's.
- **L3** (S1–S3): the same bar in the user's orientation, and the background in
  the editor.
  - The snapshot decision (T1/S1): `CaptureEditorContent` seeds its state from
    an `EditorToolbarSnapshot` (`Sources/Stare/EditorState.swift`) — a plain
    value carrying the overlay's `toolbarOrientation` + `toolbarBorder`, read
    at the moment the capture is handed over (`OverlayController`'s editor
    handoff reads the mirrors at open time). The `PreferencesModel` is
    deliberately NOT injected: attaching it would make the editor's own tool
    picks persist into the user's saved bar through the existing
    write-through plumbing — a behaviour change nobody asked for. Without it
    the seeds ride `didSet`s that `writeIfNotSyncing` refuses, so the
    snapshot stays read-only. A mismatched stored pair coerces with
    `ToolbarBorder.docked(for:)`, the exact rule `ToolbarPanel` applies at
    placement.
  - The four layouts (T1/S1): `CaptureEditorContent.layout()` docks the
    chrome on the configured edge — a row spans the window's full width on
    the top or bottom edge, a column its full height on the left or right —
    and the canvas takes the rest. `preferredSize` arithmetic is honest per
    axis: a row's height (and, when the bar is wider than the canvas, its
    width) and a column's width join the canvas's clamped size. The chrome
    stays the editor window's own `ToolbarView` hosted in `NSHostingView`
    inside a normal titled window (no floating panel); the open path still
    makes the canvas first responder, and the parity boundaries stay: the
    item list is `Tool.captureEditorGroups`, no overflow, no pages.
  - The background control (T2/S2): a `rectangle.on.rectangle` toolbar
    action in the chrome's `extraActions`, opening a real popover (allowed:
    the editor's window is a normal key window) that edits THREE per-capture
    fields on the editor's own state — `backdropPadding`,
    `backdropCornerRadius`, `backdropShadow` — seeded once from the
    `CapturePreference` the overlay hands in (`seedBackdrop(from:)`) and
    never wired into `writeIfNotSyncing`, so nothing leaks into the stored
    blob and Settings keeps only the default. The controls clamp through
    `CaptureBackdrop`'s own clamps; the clamp inside a `@Published` field's
    `didSet` converges on a value change because an unconditional
    reassignment re-triggers the observers and recursed to a segfault
    (observed, then fixed).
  - Composition point (T2/S2): `CaptureEditorCanvas.composedImage()` wraps
    its marked canvas with `CaptureBackdrop.composed` as its last step, so
    copy, the save panel and `deliverComposed` all share the same pixels.
    The save path's JPEG flank replicates `CaptureFile.write`'s own flatten
    (the transparent backdrop margin cannot encode into a format without
    alpha) through `composedImageForSave(format:)`, applied only when a
    backdrop actually composes — so an inactive backdrop keeps today's
    bytes exactly. This closes the inconsistency whereby every editor save,
    copy and history delivery silently ignored the stored backdrop that
    `CaptureFile.write` composed.
  - Verification (all exit 0):
    - `xcrun swift test --filter "CaptureEditorChromeTests|CaptureEditorBackdropTests"`
      — 12 tests, 0 failures. Measured chrome/canvas frames (300×200 capture;
      bounds → chrome → canvas):
      horizontal-top `(0,0,915,374)` → `(0,320,915,54)` → `(0,0,915,320)`,
        fitting height 54 (the bar is wider than the canvas floor of 480, so
        the honest max sizes the row's width to the bar's 915);
      horizontal-bottom → `(0,0,915,54)` → `(0,54,915,320)`;
      vertical-left `(0,0,524,747)` → `(0,0,44,747)` → `(44,0,480,747)`,
        fitting width 44 joining the canvas width;
      vertical-right → `(480,0,44,747)` → `(0,0,480,747)`.
    - Focused existing suites over the shared editor code
      (`CaptureEditor|RedactionPreference|RedactionParity|CaptureStagedCrop|
      CaptureCrop|CaptureCanvas|CaptureComposition`) — 121 tests, 0
      failures.
    - Whole suite, unpiped (`swift test > .build/w18.log 2>&1; echo EXIT=$?`)
      — EXIT=0: 904 StareCoreTests + 404 StareTests (392 baseline + the 12
      new), 0 failures.
