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

- **S4** (owner, after using the build; verbatim): "B1 - le falta el tool 'v' y siempre debe estar en pos
  horizontal top. sobra el btn de 'X' 'basura' y el gripper." The editor's palette always sits horizontally
  at the top, whatever the user's own bar is configured as — the orientation snapshot is withdrawn — it must
  carry the select tool, and the close button and the gripper do not belong there.

- **S5** (verbatim): "B4 - cambio las propiedades del bg en el editor pero no hace nada". The background
  control must apply live: moving a slider or toggling the shadow has to change what the editor shows.

- **S6** (verbatim, a note at the end of the same message): "nota default folder de las caputras ~/Downloads".
  A fresh install writes captures to `~/Downloads`, not `~/Documents`.

## Tasks

| ID | Specs | Task | Route | Commit |
| --- | --- | --- | --- | --- |
| T1 | S1, S3 | The editor's palette answered by the bar's own geometry and orientation rules | worker | 2cba577 |
| T2 | S2 | The background controls in the editor; Settings keeps the default only | worker | 2cba577 |
| T3 | S1-S3 | Docs: CHANGELOG and this log | worker | |
| T4 | S4 | Always horizontal on top, with the select tool, without the close button or the gripper | worker | uncommitted |
| T5 | S5 | The background control applies live in the editor | worker | uncommitted |
| T6 | S6 | A fresh install writes captures to ~/Downloads | worker | uncommitted |

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
- **L4** (S4–S6): the corrections the owner reported after using the build.
  - What was withdrawn (T4/S4): `EditorToolbarSnapshot` is gone outright — the
    struct, `EditorState.init(preferences:toolbar:)`'s `toolbar:` argument, the
    `toolbar:` chain through `CaptureEditorController`/`CaptureEditorWindow`/
    `CaptureEditorContent`, and the overlay's snapshot construction at the
    editor handoff. It was approved as "withdraw outright, do not leave it
    inert": a snapshot left in place would keep the editor reading a stored
    configuration the spec now says it must ignore. The chrome is ALWAYS one
    horizontal row at the top: `CaptureEditorContent.chromeBorder` answers
    `.top` unconditionally, `preferredSize` and `layout()` carry only the
    single row case, and the popover's arrow edge is fixed `.bottom`. The
    detached `EditorState` keeps the shipped horizontal/top mirrors in memory
    — nothing stored is read, and the read-only contract survives: no model
    is injected, so nothing the editor picks persists.
  - The seam for the two missing items (T4/S4): the select tool joins via the
    item-list rule itself — `Tool.worksInCaptureEditor` no longer excludes it
    (it mints no mark over a still image: `DrawingSession.begin` refuses the
    edit cursor — so the palette gains an empty-handed pointer route with the
    same armed-item marking as every tool). The close 'X' and the gripper
    leave via a `ToolbarView` parameter, `showsWindowChrome` (default `true`):
    the editor passes `false` and the instance's `drawnTrailingItems` drops
    `.close` and `.gripper`; the static `trailingItems` is untouched, so the
    outside bar's `suffix(2) == [.close, .gripper]` pin stands and the
    gripper tests keep passing. The editor still closes through the window's
    own traffic light and Escape.
  - The dead background control's real cause (T5/S5): NOT state the
    composition never reads, and NOT a cache — `composedImage()` reads the
    three knobs live and uncached, so copy/save/history pixels were already
    correct. The cause was that `CaptureEditorCanvas.draw` NEVER composed the
    backdrop at all (it drew the raw capture) and nothing observed the knobs,
    so the one surface the owner edits in simply never showed them. The fix:
    the canvas sinks onto the three knobs and invalidates, and `draw` paints
    the composed GROUND — `CaptureBackdrop.composed(image, …)`, memoized on
    the image and the three values — instead of the raw capture, with the
    display fit grown to the surface (`surfaceCoverage`) so the margin is
    actually visible; zoom/pan clamp against the same ground. Layers and
    marks clip to the picture's own rect (the compositor composes them before
    the backdrop wraps it), and `composedImage`'s mark target stays anchored
    to the base's frame — the backdrop margin must not shift marks. With the
    backdrop off nothing changes byte for byte.
  - The fresh destination (T6/S6): `CapturePreference.defaultDestinationFolder
    = "~/Downloads"` is the fresh `init(destination:)` default, so `.standard`
    lands captures in Downloads; the decoder's missing-`destination` fallback
    stays the clipboard (`CaptureDestination.storedFallback`) — a stored
    document keeps whatever it holds and nobody migrates. The no-migration
    canary in `testMissingFieldsTakeStandard` is re-aimed: `decode("{}")` now
    answers the era's clipboard document, explicitly NOT the fresh standard.
    Note: Settings' own prefill when a stored-clipboard user first switches
    to a folder still says `~/Documents` (`SettingsView` is not in this
    task's edit surfaces — flagged, not changed).
  - Verification: RED observed (backdrop knobs left the canvas undrawn and
    un-invalidated; select absent from the editor list; the missing seam
    failed to compile). Focused: chrome 4 + backdrop 8 = 12 StareTests, 0
    failures; CapturePreferenceTests 35, 0 failures; the broader shared-code
    filter (CaptureEditor|Redaction|StagedCrop|Crop|Canvas|Composition|
    ToolbarGripper|SpotlightShape|ToolbarOverflow|CaptureSelection|CaptureFile
    |CaptureFileName|SettingsCapturePane|SelfTest) — 2 failures, exactly the
    three pins below. Whole suite, unpiped (`swift test > .build/w22.log
    2>&1; echo EXIT=$?`) — EXIT=1: StareTests 428, 0 failures; StareCoreTests
    918, 3 failures — all three in files OUTSIDE this task's edit surfaces:
    `ToolAndInkTests.testCaptureEditorOffersOnlyToolsThatWorkThere`,
    `ToolAndInkTests.testSelectShortcutDoesNotResolveInTheCaptureEditor`,
    `ToolShortcutMapTests.testStaticRouterEntryPointsKeepTheirBehaviour`
    (ToolShortcutMapTests.swift:148). Their stated meaning is what S4
    withdraws (the select tool was absent from the editor's list and 'v'
    resolved to nothing there); the re-derivation needs
    `Tests/StareCoreTests/ToolAndInkTests.swift` and
    `Tests/StareCoreTests/ToolShortcutMapTests.swift`, which the parent owns —
    raised, not guessed. Everything else in the suite is green.
- **L5** (S4): the three pins re-derived as approved — each carries a canary
  note naming S4/L4 as the reason its stated meaning changed. The select tool
  is now offered in the capture editor, and the 'v' shortcut now resolves
  there, because select mints no mark over a still image
  (`DrawingSession.begin` refuses the edit cursor); text and laser stay
  unavailable because they mint content the editor cannot take.
  - `ToolAndInkTests.testCaptureEditorOffersOnlyToolsThatWorkThere`:
    `XCTAssertFalse(offered.contains(.select))` → `XCTAssertTrue(offered…)`
    with the canary "S4/L4: the cursor is offered in the capture editor — it
    mints no mark over a still image". The test's advisory-B comment was
    re-stated in the same edit (text/laser stay dead; select joins).
  - `ToolAndInkTests.testSelectShortcutDoesNotResolveInTheCaptureEditor` →
    renamed `testSelectShortcutResolvesInTheCaptureEditor` so the name states
    the new rule;
    `resolve("v", allowedTools: Tool.captureEditorTools)` now asserts
    `.tool(.select)` with the canary "S4/L4: the editor offers the cursor
    too". The text shortcut's `.none` assertion stays exactly as it was.
  - `ToolShortcutMapTests.testStaticRouterEntryPointsKeepTheirBehaviour`:
    the same one-line re-derivation —
    `resolve("v", allowedTools: Tool.captureEditorTools)` now asserts
    `.tool(.select)`, canary noting S4/L4.
  - L4 follow-up (same unit, Flags): `SettingsView`'s destination prefill
    still says `~/Documents` (path `Sources/Stare/SettingsView.swift`); it
    remains NOT in this run's edit surfaces and stays on the ledger as the
    one known cosmetic mismatch so it cannot be forgotten.
  - L4 follow-up (same unit, Flags): the
    `ToolbarGripperSpec`/`ToolbarGripperTests` static tail pin
    (`suffix(2) == [.close, .gripper]` on the static `trailingItems`) is
    untouched; the editor's missing close button and gripper come from the
    new `showsWindowChrome` parameter (editor passes `false`), not from
    changing what the outside bar draws.
  - Verification: focused (`xcrun swift test --filter
    "ToolAndInkTests|ToolShortcutMapTests" > .build/w22b-focused.log 2>&1;
    echo EXIT=$?`) — EXIT=0: ToolAndInkTests 23 tests, 0 failures;
    ToolShortcutMapTests 14 tests, 0 failures. Whole suite, unpiped (`swift
    test > .build/w22b.log 2>&1; echo EXIT=$?`) — EXIT=0: StareCoreTests
    918, 0 failures; StareTests 428, 0 failures. The three failures are gone
    because their stated meaning changed under S4/L4 (select joined the
    editor's palette and 'v' resolves there) and the assertions re-derive
    the new rule — NOT by loosening an assertion: the text-shortcut `.none`
    pin and every neighbouring assertion are untouched, and the new select
    assertions are positive pins, not absence checks.
