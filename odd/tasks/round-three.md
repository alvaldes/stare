# Round three: what the owner found testing the whole backlog

Eight reports after a full pass. Each is a defect or a correction of something
shipped in the previous rounds.

## Specs

- **S1** (verbatim): "los cursores del blur y el spotlight deben ser la cruz". Blur
  and spotlight stop having drawn glyph cursors and answer the crosshair, like
  line, arrow, rectangle and ellipse.

- **S2** (verbatim): "se debe de poder abrir el editor desde el historial con un menu
  contextual click derecho. opciones editar y otras mas (analisis)". Right-clicking a
  capture in the history opens a context menu whose actions include editing it, plus
  the others the app can honestly offer for a stored capture.

- **S3** (verbatim): "en el editor el tool 'v' no selecciona ni permite editar una
  marca". In the capture editor the select tool must actually select marks and let
  them be edited, the way it does on the drawing overlay.

- **S4** (verbatim, two halves): "en el editor el tool 'b' no hace nada y en dibujo no
  tiene el estilo pixelado que esperaba que ya tuviera como en la imagen/video de
  referencia". The blur key must work inside the editor, and redaction must actually
  look pixelated for this user — his stored preference still says blur from before
  the default changed.

- **S5** (verbatim): "en el editor el tool 'spotlight' tiene un espacio a ambos lados
  que no es normal porque?" The spotlight's cell in the editor's palette carries
  unexplained padding on both sides.

- **S6** (verbatim, with a screenshot): "en settings el about tiene un icono que no
  tiene nada". The About card's header draws an empty rounded square where its symbol
  should be.

- **S7** (verbatim): "Si tengo abierto cualquier modo, ya sea dibujo, pizarra, historial
  y presiono la combinación command+, debería abrir settings que hoy no lo hace".

- **S8** (verbatim): "Aunque tenga settings abiertos, el historial debería permitir
  hacer capturas sobre estas pantallas y no lo que hace ahora mismo que hago la
  captura y no toma settings como parte de la captura".

- **S9** (verbatim): "el cursor custom del tool solo es custom dentro la imagen del
  editor fuera es el cursor normal" — being clarified with the owner before it is
  implemented, because it reads two ways: a complaint that the drawing overlay lost
  its per-tool cursors, or a request that per-tool cursors apply only inside the
  editor's image.

## Tasks

| ID | Specs | Task | Route | Commit |
| --- | --- | --- | --- | --- |
| T1 | S1, S9 | Blur and spotlight answer the crosshair; the area-mode cursor stops leaking | worker | pending |
| T2 | S2 | Right-click a history capture for its actions | worker | pending |
| T3 | S6, S7 | The About card's symbol, and command-comma from any mode | worker | pending |
| T4 | S3, S4, S5 | The editor's select and blur tools, and the spotlight's cell | worker | pending |
| T5 | S8 | A capture includes Stare's own windows | worker | pending |

## Log

- **L1** (owner, 2026-11-25, verbatim, in order): the nine quotes above, sent as one
  message with a screenshot of the About card. He also said the version bump and tag
  happen once all of these are closed.
- **L2** (S1 worker, 2026-11-26): Retired the blur and spotlight drawn glyphs —
  the role mapping (the owner's "los cursores del blur y el spotlight deben ser la
  cruz") now answers `blurCrosshair`/`spotlightCrosshair`, one role per tool, and
  the two unreachable glyph painters (`ToolGlyphCursor` dot grid and beam) plus
  their `blurDots`/`spotlightBeam` enum cases are gone; the drawn set is five
  (numberRings, penDot, markerBeam, laserSpark, eraserRing). Pins re-derived:
  `ToolAndInkTests.testCursorRolesNameTheirToolExactly`, and in `ToolCursorGlyphTests`
  the retired spotlight-glyph test was replaced by
  `testBlurAndSpotlightAnswerTheCrosshairByIdentity` plus
  `testTheContractCoversEveryRoleExactlyOnceAndServesEachRightly` (drawn/identity
  set coverage, pinned per role, no silent fallback). The self test's
  `toolCursorsReport()` reads the same drawn/identity table. S9 leak check: traced
  every disarm of the area-mode crosshair (`answeredCursor()`) — drag mouse up, Esc,
  Return — and those restore the tool cursor; the leak that WAS live was `clear()`
  (the palette's Clear button and the deactivation clear): it released the frozen
  frame but left `isSelectingArea` armed, so the crosshair and the armed shroud
  survived on a cleared session. `OverlayView.clear()` now disarms through the same
  `cancelAreaSelection` path a cancelled drag uses, pinned by
  `testTheArmedAreaCrosshairDoesNotSurviveAClear`. Full-window and full-display
  captures requested by plain `s`/`⌥S` while area mode is armed stay armed — by
  design, and unchanged; the parent's S9 clarification with the owner decides
  whether those paths should disarm too. Commit cells left `uncommitted`.

- **L3** (S2 worker, 2026-11-26): The history's right-click menu shipped. A
  context menu on a cell — Edit first, then Copy Image, Copy File Path,
  Reveal in Finder, Save a Copy…, Delete — exists in exactly one shape: the
  model's item list (`CaptureHistoryPanelModel.menuItems(for:)`), from which
  the cell's SwiftUI `.contextMenu` and the tests both derive, so titles,
  order and routing cannot drift apart. The store gained the two APIs the
  honest actions needed: `CaptureHistoryStore.remove(_:)` — the entry, its
  stored PNG, its session cache line and the persisted index record all go,
  and it operates on the store's OWN in-list copy, so even a deceitful
  argument whose ID matches a real entry cannot send a deletion outside the
  captures folder — and `fileURL(for:)`, the validated URL or nil (nil for a
  hostile name or a missing file; the hostile-name rule that guards load and
  prune, pinned in CaptureHistoryIndexPathTests, guards these too). Choices
  recorded: the file-carried actions are DISABLED, not absent, when the
  store has no validated URL (the menu can never offer an item that would
  fail after being offered); Edit is disabled until a handoff is wired, and
  the overlay wires the ONE handoff (`openCaptureEditor`) the capture card
  already shares; Save a Copy… runs a save panel and writes the PNG where
  the user names it, adding nothing to either history; Delete asks for a
  confirming second click on the SAME cell — a single click cannot lose
  work — the first click arming it with a visible "Click Delete again to
  confirm" line on the cell and "Confirm Delete" in the menu, any walk away
  (click-select, arrows, refresh) disarming it. Everything existing survives
  re-pin: click-to-pick, keyboard map, dismiss rules, sheet geometry,
  becoming key. Tests canary S2: 18 new (CaptureHistoryStoreMenuAPITests 6,
  CaptureHistoryContextMenuTests 11, CaptureHistoryMenuKeyboardSurvivalTests
  1). Focused `swift test --filter 'CaptureHistory'`: exit 0, 61 tests,
  0 failures. Whole suite unpiped `swift test`: exit 0, StareCoreTests
  920/0 failures, StareTests 458/0 failures. Commit cells left `uncommitted`.

- **L4** (T4/S3-S5 worker, 2026-11-26, results): The cancelled run's partial
  work failed 7 of 10 focused tests; finishing it left both focused filters
  green and corrected what the partial run got wrong. S3 (the editor's select
  tool): the drag-move, corner-adjust and rotation-knob tests needed no new
  editing model — the partial run's flow over `DrawingSession`,
  `Stroke.isSelectedByCursor`, `MarkSelection` and `MarkTransform` already
  worked (press on a mark selects it, one gesture is select-and-move, a corner
  scales uniformly, the knob rotates, one journal step per drag, ⌫ deletes the
  selection, Escape sheds it) — and the committed implementation is untouched.
  What the partial run got wrong, fixed: (a) its `mouseDragged` hook for the
  select preview **deleted** the drawing path's live `session.extend` +
  `drawingMoved`, so an in-flight mark appeared only after the pointer rose —
  restored, verbatim the HEAD behaviour, selection branch above it; (b) its
  selection tests read `mark.points` as capture pixels (`viewPoint(fromPixel:
  mark.points.first!)` pressed off-canvas at (350, 200)), but the canvas's own
  architecture records each mark in the space it was drawn in — here the fit
  display's view space, which is what `spaces[id]` stores — so its own spaces
  are the fit-view points the tests wanted directly; the recorded-space line
  ("the mark's own recorded space IS the fit display's view space") is now in
  the tests, and the asserted empties it could never inspect are real: the
  move test presses the mark's midpoint (outside any handle's reach, a grab of
  the body and not a corner), and its ink checks map through
  `space(of: editor).pixelPoint(fromView:)` into the 100×100 composed capture
  the rep scans: its ink lands at pixel (75, 75) — the (200, 150) drag end —
  and pixel (50, 50), the grabbed one, is vacated; (c) all gesture helpers in
  the file fed **window-space**
  `locationInWindow` straight into a flipped canvas, so every asymmetric
  coordinate landed mirrored ((x, y) → local (x, height−y); the symmetric y=100
  presses hid it, and the adjust drag passed by exercising an unintended
  pointer); helpers now write canvas-local top-down points, the same mapping
  the capture-history probe helper uses. Focused run: `swift test --filter
  "CaptureEditorSelectionTests|CaptureEditorBlurToolTests"`, exit 0, 10 tests
  (4 blur + 6 selection), 0 failures; 3 of them had failed at the start of this
  session (rotate knob, drag-move ink, corner adjust) plus storage decode (one
  assertion block) per the cancelled run's own baseline (7 of 10). Neighbours
  re-pinned after the record-path change (focused filters,
  `CaptureEditor(Zoom|Eraser|Backdrop|Delivery|Cursor|StagedCrop|CanvasPaste|Bookmark)|…`:
  exit 0, 0 failures) — the eraser's distinct-space rule, the 3× zoom save
  bytes and the crop/journal behaviour all stand.
- The S4b reversal shipped (AppPreferences): a stored `redactionStyle
  : "blur"` blob — the owner's own pre-B2 document — now decodes as the
  shipped `.randomizedPixelate`, so the app he runs presents the pixelated
  look he asked for after seeing it; the earlier deliberate decision (the
  stored field says blur because the visible Redaction picker once offered it
  and could be an explicit choice the app must not override) is REVERSED on
  his round-three say-so, and the reversal's reason is recorded in the
  field's doc comment in AppPreferences.swift: the blur he was seeing was the
  shipped default his stored document still carried, not a pick he made. The
  model mirror, the state it seeds, and a mark minted from the migrated
  choice all carry pixelate, and the mark renders as a mosaic, never the
  blur twin, through the one `MarkRenderer.redactionPatch` dispatch — pinned
  by `CaptureEditorBlurToolTests
  .testAStoredBlurPreferenceDecodesToPixelateAndItsMarkRendersAsAMosaic`
  (green). The stroke- and session-level restore fallbacks stay `.blur`
  (RedactionStorageTests green): a pre-B2 drawing keeps painting exactly what
  it painted — that pin concerns saved marks, which the owner did not
  dispute, never the stored preference.
- The superseded no-migration pin, `AppPreferencesTests.
  testAnExplicitStoredBlurIsNeverMigrated` (Tests/StareCoreTests/, a file
  outside this task's allowed edit surfaces), now disagrees with the
  migration by design and fails the full suite until its owner re-derives it:
  the failed run left it as the S4b blocker; the re-derivation is queued at
  the transaction controller, the only piece of T4 left open.
- S5, probed to exhaustion, not reproduced in code: two fresh probes this
  session (every AppKit descendant frame; a layer-rendered chrome bitmap with
  the spotlight marked) find NO source of the padding in the cell, the
  AppKit-host wrapper nor the chrome: the editor's tool cells all sit on the
  same pitch (select x=12, blur x=320, spotlight x=352 = blur+32, eraser
  x=397 via the family divider, all 28×26; `AppKitPlatformViewHost
  <SpotlightToolButton>` frame equals its neighbours'), the marked plate
  spans the full 28 pt (px 352–379 at 1×) and the sun.max glyph is centred
  (extent 361–374 around cell centre 366), identical to its neighbours' glyph
  centring; the run-left bitmaps (/tmp/chrome.png, /tmp/drawingbar.png) agree.
  No speculative edit to ToolbarView — nothing observed would be a fix, and
  the shape menu must not regress. If the owner reproduces it in a build, a
  screenshot beside these probe numbers decides whether the source is a
  Retina-only rendering pass the headless harness cannot show.
- The superseded no-migration pin re-derived (the one test in
  Tests/StareCoreTests/AppPreferencesTests.swift this task was authorised to
  touch): `testAnExplicitStoredBlurIsNeverMigrated` is retired, replaced by
  `testAStoredBlurDecodesAsTheShippedPixelateIntoTheReversal` — a stored
  `"blur"` blob now decodes as the shipped `.randomizedPixelate`, and the
  section's canary (beside the field's own doc comment in AppPreferences.swift)
  names the round-three S4 reversal and the owner's words ("en dibujo no tiene
  el estilo pixelado que esperaba que ya tuviera"). The reversal is scoped:
  the derived test also asserts a stored mark WITHOUT the redaction field —
  the `PersistedStroke` decode fallback `Stroke(persisted:)` — still restores
  as `.blur` (the stroke/session-level pins live on in RedactionStorageTests,
  untouched). RED→GREEN observed: RED was the old pin failing the filter (40
  tests, 1 failure: `("randomizedPixelate") is not equal to ("blur")` at line
  448 of the file); GREEN `swift test --filter "AppPreferencesTests"`: exit 0,
  40 tests, 0 failures. No other test in the file touched.
- S5 recorded as unexplained, with numbers. This session measured the PAINTED
  GLYPH inside every tool cell of the editor's chrome (previous round's probes
  had compared only cell frames and glyph CENTRING): each tool armed in turn,
  its accent plate pinning the cell's exact geometry, and the white glyph on
  the plate measured pixel-wise at 2x off a chrome rendered over a solid
  ground. Cell x positions reproduce the earlier probe exactly (select 12, pen
  57, highlighter 89, line 134, arrow 166, rectangle 198, ellipse 230, number
  275, blur 320, spotlight 352, eraser 397; every plate 28 pt wide); the
  painted glyph widths: select 7.5, pen 8.5, highlighter 13.5, line 10.5,
  arrow 10.0, rectangle 15.0, ellipse 13.0, number 13.0, blur 11.5,
  spotlight 14.0, eraser 13.5 pt. The spotlight is the second WIDEST cell in
  the row — wider than the neighbours' median (13.0, ratio 1.08), inside the
  neighbours' spread (7.5–15.0). Nothing in these numbers supports a fix "so
  it reads like its neighbours": it already reads wider than most, and the
  spread across cells is the symbols' natural widths at the same 13 pt font.
  No speculative edit to ToolbarView (the verdict of the previous rounds
  stands); no glyph-width pin was added to the suite (a pixel-measured pin
  would travel with the OS's symbol metrics); the measuring harness was a
  temporary test, removed after the numbers were taken — the chrome test file
  returns to HEAD byte-for-byte. If the owner reproduces the padding in his
  build, a screenshot beside these numbers decides what remains to be
  explained (the earlier note about a Retina-only rendering pass the headless
  harness cannot show already covers the one live hypothesis).
- **L5** (S6–S8 worker, 2026-11-26): Both remaining units closed in one pass.

  **S6 (the About card's blank symbol).** Cause, re-derived on this machine's
  system list (`CoreGlyphs.bundle/symbol_order.plist`, the file every SF Symbol
  name-check runs against): "app" IS a valid SF Symbol — `NSImage
  (systemSymbolName:)` answers a real image, and the suspected cause carried
  with the task ("app" is not an SF Symbol name) is WRONG here. The glyph named "app"
  is ITSELF an empty rounded app-icon tile: its ink is only the tile's
  outline, nothing inside (verified by rendering it: ~765 ink pixels across a 64 pt
  canvas, all forming the hollow squircle; an ASCII map of the drawn pixels
  shows an outline shape with an empty middle). Drawn inside the card's own
  24×24 control-background tile under its own separator stroke, it reads as a
  blank rounded square — the owner's screenshot. Fix at the source that owns
  it: the About card now carries `SettingsArea.about.symbol` ("info.circle") —
  the pane object's OWN symbol, the one its sidebar row already shows — so
  card and sidebar are one decision (SettingsView.swift, the About card call
  site, with the cause in a comment there too). Pinned in
  `SettingsAboutSymbolTests`, two tests: (1) the walking pin the round asked
  for — every `symbol:` argument in the three Settings sources
  (SettingsView/SettingsComponents/SettingsHistoryPane: 28 card call sites as
  of this pass) resolves to a real SF Symbol at the card's own rendering
  configuration (12 pt semibold, non-zero glyph size); a call site whose
  symbol the walk cannot read FAILS the test rather than slipping past, and a
  refactor that drops the count below the call count fails too; (2) the derived
  pin — the About card's symbol equals `SettingsArea.about.symbol`, so the
  empty tile ("app") cannot come back as the About header. The walking pin
  reads GREEN at HEAD ("app" resolves: honest finding — it cannot catch THIS
  defect by itself), the derived pin went RED first (`SettingsView.swift:2098, canary names S6,
  "app" not equal to "info.circle") then GREEN. Additionally `SettingsCard`
  now fails LOUDLY in tests when any card is built with a symbol no SF Symbol answers (debug
  assert in its init, release builds compile it out).

  **S7 (⌘, from every mode).** Cause: Stare is an `.accessory` app, so it
  ships without a standard AppKit main menu at all — and ⌘, is delivered
  through the main menu's key equivalents. With no menu, the keystroke died in
  every mode that held the keyboard. The app menu now carries `Settings…`
  with ⌘, (`AppDelegate.makeMainMenu`, built in
  `applicationDidFinishLaunching`), routed through a retained
  `SettingsShortcutMenuTarget` into the ONE open path (`AppDelegate
  .openSettings`) the status bar and the setup guide already share — opening
  Settings does NOT cancel a mode (session stays active/boards keep pages/
  sheet stays up, the convention everywhere else). Because a `.normal`-level
  Settings window would open BEHIND the `.screenSaver` drawing panels and
  still look dead, the open reads
  `OverlayController.isAnyOverlaySurfaceActive` (new, the one mode question)
  and lifts the window into the overlay band (`SettingsWindowController
  .level(aboveOverlay:)` / `.overlaySurfaceLevel`, the same band the history
  sheet and the guide sit on; `show(aboveOverlay:)` defaults false, so the
  status bar's and the guide's opens are unchanged and every later open
  re-decides the level). Logged as the honest limit NOT hidden: a GLOBAL
  registration of ⌘, (Carbon/CGEvent hotkey, the GlobalHotkeyManager path)
  would intercept the keystroke for every OTHER app in the system — refused,
  so ⌘, reaches Settings exactly when Stare is the active app, which every
  screen-holding mode makes true; when NOTHING is open Stare is background and
  the reachable route into Settings is the status-bar menu (which already
  carried `Settings…`). Tests, `SettingsShortcutTests`, seven: the item's
  structure + the real menu dispatch (`NSMenu.performKeyEquivalent` — the
  dispatch NSApplication itself runs for key equivalents) into the open path,
  then that same dispatch from a live drawing session, from the open board,
  from the open history sheet, and with nothing open, each asserting the mode
  SURVIVES the dispatch (no silent cancel), plus the lift-under-a-mode test
  and the normal-level-when-nothing-open test. RED was the behaviour itself at
  the run where target retention was missing (NSMenuItem holds its target
  WEAKLY — the test retains it exactly as the AppDelegate does; second RED
  xctest missing the initialized app instance, NSApp IUO). One honest
  trade-off recorded: while the Shortcuts pane is RECORDING a binding, ⌘, is
  now answered by the app menu first (key equivalents dispatch before the
  responder chain), so ⌘, can no longer be RECORDED as a custom global-hotkey
  binding inside Settings — exactly as it works in every macOS app that has a
  Settings menu item.

  **S8 (Settings in the capture).** Cause: `ScreenContent.prepare` (CaptureService.swift)
  excluded EVERY window of Stare's own process — the exclusion that
  legitimately keeps the drawing panels, the palette, the capture cards, the
  history sheet and the pointer highlight out of the pixels also took the
  Settings window down on screen. The rule is now explicit and pure
  (`ScreenContent.excludesOwnWindow`): every own window is excluded EXCEPT the
  one keyed on `ScreenContent.settingsWindowTitle` ("Stare Settings"), the
  same constant `SettingsWindowController.makeWindow` names its window with —
  filter and window cannot drift. The Settings window is only ever IN the
  enumeration when it is on screen (the shareable-content probe runs
  `onScreenWindowsOnly`), so a closed Settings never paints. Kinds, stated
  plainly: COVERED — the whole-display capture, the frozen area-capture base
  and the live-blur refresh all ride the same `prepare` (a drawn area crop
  keeps whatever of Settings falls inside the framed region); LEFT OUT — the
  ⌥S window capture: it resolves the front-most window of ANOTHER app and
  crops that window out of the display image; "Stare's windows are never that
  capture's target" is the documented `WindowCaptureTarget` contract, and a
  window capture of the Settings window itself would be a new feature, not
  this fix. The overlay and the bar still never appear while a capture runs:
  they are own windows with other (or no) titles, still excluded. When
  Settings overlaps the region being captured its pixels enter the image
  wherever it covers — a screen capture records what the screen shows, as it
  already does for a window of any other app (there is no per-window
  subtraction a screen capture can do). Tests, `CaptureIncludesOwnWindowsTests`,
  three: the rule matrix (Settings kept; untitled own panel and other-title
  own window excluded; foreign-pid and ownerless windows never excluded, and
  the exact "Stare Settings" string pinned), the window-title identity pin
  (the real controller window carries the constant's title) and the REAL
  capture proof — skipped only when the runner lacks Screen Recording, but
  this run HELD the permission and observed it live: a Settings-named window
  on screen was in the captured image (its ~distinct colour well past 4,000
  pixels) while Stare's own overlay-window colour counted 0.

  Verification, the parent's exact commands (unpiped, blocks, foreground):
  - `swift test --filter "SettingsAboutSymbolTests|SettingsShortcutTests"`:
    exit 0 — 9 tests (2 S6 + 7 S7), 0 failures.
  - `swift test --filter "Settings|Capture"`: exit 0 — 197 tests, 0 failures
    (the whole Settings/Capture neighbouring sweep, including
    `WindowSizing`/`PaneLayout`/`BarPreview`/`CaptureCard*`/histories: the
    changed `show()` signature, the lift, the window-title constant and the
    new own-window rule broke nothing).
  Commit cells left `uncommitted`.
