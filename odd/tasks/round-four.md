# Round four: what the third pass left broken or unfinished

## Specs

- **S1** (verbatim): "cualquier haccion sobre el menu en el historial debe hace que se cierre el historial".
  Acting on a history menu item closes the sheet.

- **S2** (verbatim): "en el editor 'v' al movel se muevel el marco azul y despues la marca". Dragging with
  the select tool must move the mark itself; today the selection frame moves first and the mark follows.

- **S3** (verbatim): "en el editor 'b' no pinta pero en dibujo si funciona el pixelado". The blur tool paints
  in the drawing overlay and still does not in the editor.

- **S4** (verbatim, with a screenshot): "sigue igual" — in the editor's palette the spotlight's cell is ~400 pt
  wide where its neighbours are ~28 pt, because the wrapper that carries its shape menu has no fixed frame.

- **S5** (verbatim): "no esta resuelto sigue mostrando el custom cursor del tool activo sobre la barra y sobre
  el window title y los botones de la ventana del editor". The tool cursor must apply only over the image;
  over the editor's own chrome — palette, title bar, window buttons — it is the arrow.

- **S6** (verbatim): "el editor debe mostrarse en el dock como una app mas porque sino se queda la ventana
  abirta y se puede perder. Ademas si se abre desde finder una imagen debe salir la opcion de abrir con stare
  y abra el editor". While an editor is open the app is a regular app in the Dock, and an image opened from the
  Finder with Stare lands in the editor.

- **S7** (verbatim): "ya cierra el historial pero falta aplicar el foco la ventana del editor o al finder porque aun
  se queda el foco la app en la que estaba antes de abrir el historial". Closing the history gives focus back
  to the editor window if one is open, otherwise to the Finder — not to whichever app was frontmost before.

- **S8** (verbatim): "porque cmd+w no cierra la ventana del editor?" Command-W closes the editor window.

- **S9** (verbatim, with two screenshots): "he hecho algunos blur pero no todos salieron como esperaba, algunos
  parecen un rect de color que no tiene nisiquiera nada que ver con fondo donde esta haciendo blur. Pero algo
  interesante es que al guardarlo si funciona". The live preview of a blur mark sometimes paints a flat colour
  unrelated to what is under it, while the saved file is correct — so the preview samples the wrong source.

## Tasks

| ID | Specs | Task | Route | Commit |
| --- | --- | --- | --- | --- |
| T1 | S4, S5 | The spotlight's cell and the cursor over the editor's chrome | worker | uncommitted |
| T2 | S1, S2, S3 | History closes on action; select moves the mark; blur paints | worker | uncommitted |
| T3 | S6 | Dock presence and Open With | worker | uncommitted |
| T4 | S7-S9 | Focus after the history, command-W, and the live blur's source | worker | uncommitted |

## Log

- **L1** (owner, 2026-11-26, verbatim): the six quotes above, sent as one message with a screenshot of the
  editor's palette where the spotlight cell spans roughly a third of the bar.
- **L2** (worker, 2026-11-26, T1–T3 closing pass, all six S#): S1 — an acted history menu action now runs its
  act and then the pick's own `onClose` seam (`CaptureHistoryPanelModel.perform`), so the sheet closes and the
  panel's hide restores focus; arming Delete stays open on purpose (the confirm happens on the standing sheet)
  and the confirming delete closes like the rest — 6 model-level tests, one panel-level hidden-hook test.
  S2 — the editor's draw replaces the dragged mark with its ONE selection preview on the drawn set for the
  whole drag (`drawLiveMark`), so the ink and the dashed chrome land together and the drop journals exactly one
  step (live-ink-probe test: old spot vacated mid-drag, ink at the dragged spot, one ⌘Z per drag).
  S3 — blur marks on the editor's live canvas paint the redaction through the ONE dispatch
  (`MarkRenderer.redactionPatch`, the compositor's own crop rule via `drawLiveBlur` — same `DrawingSession`
  stamp) instead of the 0-width outline stroke; live-view pin inside the mark, stripes kept outside it.
  S4 — the spotlight's AppKit cell takes its neighbours' 28×26 back (fixed frame on the
  `SpotlightToolButton` in `ToolbarView.toolButton`; the right-click shape menu is the same view's own and
  unaffected); the stretch pin measured 118 pt against the fix at a widened window (the defect reproduces at
  spare row width, not at preferred width).
  S5 — the editor's one cursor decision `CaptureEditorCanvas.cursor(atWindowPoint:)`: the armed tool's glyph
  (or the gesture pair) only over the image; the arrow over the palette row, the title bar and the window
  buttons; the content now owns the same delivery tracking area every other cursor surface installs
  (`.cursorUpdate` + `.activeAlways` + crossings) and routes its handlers and the canvas's exit through the
  decision — no second ambient `set()`; leaving the image and re-entering it both pin the pair.
  S6 — `CaptureEditorController.dockActivationPolicy(forEditorCount:)` (0 → accessory, any editor → regular)
  applied at open and at the last close, so the Dock shows Stare exactly while an editor window exists
  (launch stays the accessory LSUIElement contract); the app delegate bridges the system's open-files event
  into `OverlayController.openFileInEditor(at:)`, which decodes and hands the file through the ONE
  `openCaptureEditor`; the bundle's Info.plist declares png/jpeg/gif/tiff at rank Alternate (offered, never
  the default thief).
  Focused run `swift test --filter "CaptureEditor|CaptureHistoryPanel|ToolbarLayout"` exit 0 — 107 cases
  passed (95 StareTests + 12 StareCoreTests), 0 failed, additions 21 (S1×7 incl. panel level, S2×1, S3×1,
  S4×1, S5×4, S6×7). Two deliberate exclusions: the Dock icon's REAL visibility in Finder/Cmd-Tab and the
  Finder "Open With" menu are runtime system appearances — the owner's eye closes those; `LSUIElement` stays
  true, so the Dock presence rides the runtime flip, not a launch change.
- **L3** (worker, 2026-11-26, T4 closing pass, S7–S9): S7 — the history's hide no longer hands the
  foreground to whatever app was frontmost before the sheet opened (the `restoreFrontmostApplication`
  branch is replaced): `OverlayController.HistoryFocusDestination.destination` is the value rule with the
  fallbacks named in the spec's order — editor first (`CaptureEditorController.frontmostWindow`, activated
  through the overlay's `makeEditorKey` seam whose default is the real `makeKeyAndOrderFront`), the open
  board's canvas second (the standing rule the picks' delivery keeps), the FINDER third
  (`OverlayController.activateFinderApplication`, the workspace's Finder app activated; tests inject a
  witness). Pick and refused deliveries untouched (`deliverHistoryPick` unchanged; the board pick's
  existing tests still pass). S8 — the cause: Stare's menu-less accessory app gets its key equivalents
  through the main menu's key pass FIRST (the same order ⌘, needed its item for), the menu never carried
  ⌘W, and the window's keyboard had no close route of its own — so the keystroke died before any
  responder. The `Close Editor` (⌘W) item rides the retained `EditorCloseShortcutTarget`, whose gate is
  the exact production question `NSApp.keyWindow as? CaptureEditorWindow` and whose action is the window's
  own `performClose` — the close button's route, through the window's close tail once. The Settings
  window, a floating panel and the whole app are never closed (the gate reads nil for every other key
  window). S9 — the actual sampler: the LIVE editor blur handed `MarkRenderer.redactionPatch` (and so
  `BlurEffect.crop`) the space's TOP-DOWN view rect untouched, while `BlurEffect.crop` reads its rect in
  the crop's own BOTTOM-LEFT bitmap space — proven with a standalone gradient crop probe (rect y=5 read
  the patch from the visual-bottom rows, brightness 0.92 = the row 5 pixels ABOVE the bottom, not from
  the visual top). The saved file rode the compositor, whose `drawBlur` converts with
  `y = height − maxY × scale`, so it was correct; the overlay's `drawBlur` converts the same way. The
  live draw now performs the compositor's own conversion before the one dispatch
  (`Sources/Stare/CaptureEditor.swift`, `drawLiveBlur`): it samples exactly what the compositor samples.
  Evidence — RED observed before the fix (live=0.95..0.98 red-tinted vs compositor=0.92 neutral gray
  inside the same patch, the fixture striped above and flat red below); GREEN — focused run
  `swift test --filter "CaptureEditor|CaptureHistoryPanel|Redaction"` exit 0, 128 cases passed
  (104 StareTests + 24 StareCoreTests), 0 failed, additions 8 (S7×3 incl. the fallback rule, S8×4 incl.
  the source-wiring canary, S9×1 with the live==compositor patch parity inside the mark). Two harness
  discoveries recorded for the next rounds: a headless xctest process never becomes active, so regular
  windows' `isKeyWindow` cannot be asserted there — S7/S8 pin their activation ROUTES with witnesses
  (the real AppKit calls stay as the defaults) and the key's real effect is the owner's runtime eye; and
  a failed `NSApp.activate(ignoringOtherApps:)` in a process whose activation policy is accessory
  poisons every LATER panel's keying in the same run, so the S7 tests run after the pre-existing
  CaptureHistoryPanelKeyboardTests (class order, `CaptureHistoryPanelLeaveFocusTests`) — its first RED
  run had already shown the interaction without any spec change to it.
  - Follow-up (worker, 2026-11-26, the full suite's two
    `TextSelectionWindowTests` failures): the S7 class now leaves the process exactly as it found it —
    `CaptureHistoryPanelLeaveFocusTests` records the state before each test (`NSApp.isActive` + the
    Dock-presence policy a standing editor window flips) and restores both in `tearDown` when they
    changed (`setActivationPolicy`, then `deactivate()` — a policy flip alone can deactivate the app),
    closes the sheet and any editor windows its routes left standing WITHOUT the close hooks (the
    sheet's own `hide()` fires the focus handoff, a fresh activation, after the assertions), and
    resigns any key window (`keyWindow?.resignKey()`), so no window is key when the next class starts.
    Every S7 assertion kept; the destination rule and both witnessed routes untouched.
    `swift test --filter "CaptureHistoryPanelLeaveFocusTests|TextSelectionWindowTests"` — green,
    EXIT=0 five consecutive runs (18 tests: 3 + 15, 0 failures each) — after the hooks crashed the
    first five runs (EXIT=1, fatal error at `CaptureHistoryPanelTests.swift:397`: the hooks read the
    nil-before-init global `NSApp`; fixed by `NSApplication.shared` in the hooks). HONEST ATTRIBUTION:
    the pair was green BEFORE the restoration too (one earlier run), so the S7 class is not the
    contaminator this environment answers for. With cursor-stack instrumentation (since removed) the
    real poison was found outside S7: `CaptureEditorZoomTests` leaves `NSCursor.current == crosshair`
    (a bare `set()`, never restored) — its pen-picker test presses `p` through the canvas
    (`resolvesArmedKey` → `reassertCursor()` → `crosshair.set()`) and never sets the cursor back;
    the crosshair stands under the surface's own push, so the class's pop hands back the arrow and
    the next class sees a changed `current`. The deterministic minimal repro (4/4 before the S7
    hooks, still failing after them) is
    `swift test --filter "CaptureEditorZoomTests|TextSelectionWindowTests"` — the crosshair standing
    is the zoom test's, and `testEveryExitRestoresThePreviousCursorAfterTheCrosshair`'s
    baseline (crosshair) minus the class's pop (arrow) honestly fails at :220. The :196 keyWindow-nil
    failure needs an even wider prefix (it reproduces under a broad `Capture|...|TextRecognition`
    filter, 2/2) and was not pinned to one class; a `.set()` cursor left standing is the same
    family. FIX CANDIDATE BEYOND THIS TASK'S SURFACES: `Tests/StareTests/CaptureEditorZoomTests.swift`
    restoring the cursor it found in `tearDown` (the same restore family the S7 hooks now perform for
    activation), or the parent's own suite run to decide.
  - Follow-up 2 (worker, 2026-11-26, the zoom restore lands, the wide prefix still poisons): the
    zoom class now captures `NSCursor.current` in `setUp` and restores it in `tearDown` with `set()`
    (no stack manipulation), so its own poison is closed inside its surfaces — the narrow repro
    `swift test --filter "CaptureEditorZoomTests|TextSelectionWindowTests"` runs EXIT=0, 27 tests
    (12 + 15), 0 failures. The BOUNDED WIDE PROBE (`Capture|CardCursorRouting|Composite|LiveBlur|
    Onboarding|Pinned|Pointer|Primary|Redaction|ScreenRecording|Settings|StatusBar|TextRecognition|
    TextSelectionWindowTests`, 436 StareTests + 349 StareCoreTests) still ends EXIT=1 with the same
    two selection failures (`TextSelectionWindowTests.swift:220` cursor restore, `:196` keyWindow
    nil), so both poisons have owners beyond the zoom class. Bisection, probe re-runs with families
    removed via `--skip`, everything else identical: `CardCursorRoutingTests` alone reproduces the
    cursor failure — `--filter "CardCursorRoutingTests|TextSelectionWindowTests"` runs EXIT=1 with
    exactly the :220 failure (2/2 runs): its `controller.activate()` / `toggleBoard()`
    (`OverlayController.activate`, OverlayController.swift:911) leaves `NSCursor.crosshair.set()`
    standing with no restore — the same `.set()`-leaver family the zoom class was. Under the wide
    prefix it is proven by add/remove: probe with `Settings|StatusBar` skipped keeps ONLY :196 red;
    with `CardCursorRoutingTests` additionally skipped (`--skip
    "Settings|StatusBar|CardCursorRouting"`) the probe is green, EXIT=0, 343+343 tests, 0 failures —
    and `--skip "Settings|CardCursorRouting"` is green too, EXIT=0, 343+343, 0 failures. The :196
    keyWindow-nil branch also survives every wide run where CardCursorRoutingTests is present; its
    source is the same `activate()`'s failed `NSApp.activate(ignoringOtherApps:)` plus the standing
    overlay panels/toolbar — the exact mechanism the L3 S7 hooks neutralise for
    `CaptureHistoryPanelLeaveFocusTests`, but `CardCursorRoutingTests` restores nothing (no
    deactivate, no resignKey, no cursor restore). FIX NEEDED BEYOND THIS TASK'S SURFACES: the same
    leave-as-found hooks in `Tests/StareTests/CardCursorRoutingTests.swift` (cursor capture in
    `setUp` / restore in `tearDown` with `set()`, `deactivate(restoringFocus: false)` when a mode
    is up, `keyWindow?.resignKey()`). A residual second branch remains: with
    `CardCursorRoutingTests` REMOVED the wide probe still fails both tests whenever the
    Settings-family classes run alongside the rest (probe minus `Settings|StatusBar`: only :196;
    minus `Settings|CardCursorRouting`: green). Eleven focused pairs (each Settings class alone, all
    Settings together, Settings x CaptureHistoryPanel(Keyboard+LeaveFocus) x Onboarding x
    CaptureEditorDock x CaptureEditorWindowClose x CaptureEditorCursor x CaptureSpotlightShape x
    CaptureIncludes x RedactionParity x LiveBlur x StatusBarGlyph, each filtered straight against
    TextSelectionWindowTests) all run green (EXIT=0), so this branch is cumulative across the wide
    prefix and NOT pinned to one class in the authorized budget. No assertion was weakened:
    `TextSelectionWindowTests` was not touched; all evidence above is from probe composition only.
  - Follow-up 3 (worker, 2026-11-26, the leave-as-found hooks land, the board residue closes, the residual
    Settings-family branch is still not one class): the shared helper now lives in
    `Tests/StareTests/TestWindowPlacement.swift` — `LeaveAsFound` (capture in `setUp`: `NSCursor.current`,
    `NSApp.isActive`, `activationPolicy()`; restore in `tearDown` in the order that keeps each hook from
    undoing the next: policy first — a flip can deactivate the app as a side effect — then the active flag,
    then `keyWindow?.resignKey()`, then the cursor via `set()`, never a stack push/pop) — and BOTH hooked
    classes now use it: `CaptureHistoryPanelLeaveFocusTests` (its own panel/editor closing stays
    class-owned, the process-level hooks come from the helper) and `CardCursorRoutingTests` (new: capture
    in `setUp`; in `tearDown` the overlay mode's own no-hook exit `deactivate(restoringFocus: false)`, the
    board's own user-visible route `toggleBoard()` for the board mode — no no-hook close seam exists for
    the board, so the class leaves through the mode switch's route, whose focus restore re-asserts
    whichever app was already frontmost — then the helper). What each class WAS leaving standing, and what
    the hooks now close:
    `CaptureEditorZoomTests` — the pen-picker's crosshair `set()` (closed by follow-up 2).
    `CardCursorRoutingTests` — the crosshair `set()` from BOTH modes, a failed
    `NSApp.activate(ignoringOtherApps:)`, the app active, and the board's standing residue: instrumentation
    (one probe class sorting immediately before `TextSelectionWindowTests`, since removed) showed TWO
    visible full-screen `OverlayWindow`s (`level 1000`, one per display) plus a visible `ToolbarPanel`
    (`level 1001`) at the selection surface's doorstep in red compositions; the newest window census after
    the board exit drops them.
    `CaptureHistoryPanelLeaveFocusTests` — the activation, the Dock-presence policy flip and a standing key
    window (closed by follow-up 1, now via the helper).
    Narrow repros after the hooks: `swift test --filter "CardCursorRoutingTests|TextSelectionWindowTests"`
    EXIT=0 (23 tests, 0 failures) — the CursorRouting strand the ledger pinned to :220 is CLOSED, Cursor
    Routing is innocent under `--skip` removal AND alone.
    Full bisection table (bounded probe, each composition run with the exact delivered filter):
    full probe (no skip): EXIT=1, 436 StareTests + 349 StareCoreTests, exactly the two selection failures
    (:220, :196) — five runs, deterministic.
    `--skip "Settings|StatusBar"` red both tests ×2 runs; `--skip "Settings|CardCursorRouting"` GREEN
    EXIT=0 ×2 runs (343 StareTests); `--skip "CardCursorRouting"` red; `--skip "Settings"` red;
    `--skip "StatusBar"` red; Settings singles ×14 (all of the family, PRE board fix) red;
    single-class skips ×15 across the non-Settings families (OnboardingFocus, CaptureIncludes,
    PinnedImage, PrimaryScreen, CaptureEditorDock, CaptureHistoryPanel(Keyboard/LeaveFocus),
    CompositeParity, LiveBlur, TextRecognitionClient, StatusBarGlyph, RedactionParity,
    ScreenRecordingClientAdapter, CaptureSpotlightShape, ToolbarLayout) all red; half skips (runtime class
    order): classes 1–36 of 72 (AppIconImageTests…CaptureHistoryPanelTests) GREEN (171 StareTests),
    classes 37–71 (CaptureHistoryStoreMenuAPITests…TextRecognitionClientTests) GREEN (282 StareTests);
    two same-size count probes (15 classes removed two ways, 310 StareTests each) red — composition, not
    count. All with the exact delivered command plus one `--skip` (bisection only; nothing delivered).
    POST board-fix verdict: the trio's removal does NOT turn the full probe green — one more strand, and
    its TWO members are (a) the Settings family — no single Settings class ruled out ×14 re-run post-fix,
    both halves re-run post-fix red — and (b) something that every GREEN composition has in common: ANY
    full half of the runtime class order skipped is green, so the strand spans cross-composition; the
    probe instrumentation (removed) proved the red/green DOORSTEP STATES are IDENTICAL to the field
    (active=false, policy=.accessory, keyWindow=nil, mainMenu=nil, modalWindow=nil, same cursor image, 20
    windows both) — so the poison is invisible to an AppKit snapshot: in-suite queued phases
    (`SettingsWindowController.show` / `OnboardingWindowController`'s queued `NSApp.activate` +
    makeKeyAndOrderFront re-asserts, `OverlayController.assertActivation`'s 0.1-s retry ladder) and/or
    window-server-side keying state accumulated across `NSApp.activate` failures (the S7 mechanism the L3
    S7 hooks neutralise for ONE class at a time). Delivered probe, twice consecutively at the end:
    EXIT=1, 436 StareTests + 349 StareCoreTests, 2 failures (the same two `TextSelectionWindowTests`
    lines), 0 other failures, no added `--skip`, `TextSelectionWindowTests` untouched, every earlier
    assertion intact. UNATTRIBUTED means for the parent: the residual strand's candidate owners sit in
    files beyond this task's authorize surfaces — `Tests/StareTests/CaptureHistoryPanelKeyboardTests.swift`
    (panel activations, the L3 blame target), `Tests/StareTests/SettingsShortcutTests.swift`
    (`controller.activate()`/board toggles), the `SettingsWindowController`/`OnboardingWindowController`
    queued activation family (~all Settings/Onboarding test classes), or Sources
    (`OverlayController` has no no-focus board-close seam; `SettingsWindowController.show` /
    `OnboardingWindowController` queue main-queue re-activation blocks that fire AFTER their test's
    teardown). HONEST ATTRIBUTION of what IS proven: the visible-window strands are closed; what remains
    needs either those files hooked the same leave-as-found way, or a Sources seam (internal
    `OverlayController` board close with `restoringFocus: false`, and/or moving the queued
    `NSApp.activate` re-asserts behind a test-observable gate) — a parent decision, not a worker one.
  - Follow-up 4 (worker, 2026-11-26, the closing pass — the two test-order failures taken to zero, all
    suite runs green): the actual mechanism is settled by INSTRUMENTED REMOVE-AND-RERUN evidence, and
    it is NOT the queued activation the follow-up above suspected. Probe with the two window
    controllers' queued re-assert blocks AND the ladder's `asyncAfter` re-queue all disabled, plus per
    -block instrumentation (`Diag.log` at each queued block's head): the wide probe was still red with
    the SAME two `TextSelectionWindowTests` failures (EXIT=1) — and the logs PROVE the queued blocks
    cannot be the poison: every settings/onboarding queued block fired after its test's end and
    SKIPPED (`self=false` — the controller was already deallocated, `weak self` nil, guard short)
    BEFORE any activation ran, and `assertActivation`'s attempts beyond 0 NEVER RAN post-mortem
    (their closures died with the controller: the only ladder log ever written in the red
    composition was the attempt=0 queue line, and no queued turn ever executed after its owner's
    exit). The queue sites were
    GATED anyway, because the task directed the gate, and the gate is correct regardless: all three
    queue sites (the
    two window controllers' `show()` re-asserts and `OverlayController.assertActivation`'s retry
    ladder) now queue STORED, CANCELLABLE `DispatchWorkItem`s — the gate being: the owner's exit
    cancels the item (`windowWillClose` cancels the window controllers' re-assert — a later `show`
    also cancels and re-arms — and `deactivate`/`closeBoard` cancel the ladder's retry), so a queued
    turn can never run after the owner is gone, even while a test's property still retains the
    controller, and the body's own guards (`window.isVisible`, the mode flags) answer nothing for
    anything that slips past. Second attribute: single-class skips × MANY (SettingsShortcut,
    CaptureHistoryPanelKeyboard, CaptureHistoryPanelLeaveFocus, CaptureHistoryPanelTests,
    CaptureHistoryMenuKeyboardSurvival, CaptureEditorDock, CaptureEditorWindowClose, CaptureIncludes,
    CaptureStagedCrop, StatusBar, OnboardingFocus, Primary, plus the entire Settings family minus
    SettingsWindowSizing) ALL still red — the strand is cumulative and owned by NO single class.
    THE REAL MECHANISM, instrumented through `TextSelectionWindow`'s own keying boundary: in the red
    compositions the surface's own `makeKey()` silently fails — `becomeKey` runs (so the crosshair
    IS pushed) but `isKeyWindow` stays false and `NSApp.keyWindow` stays nil afterwards, so the
    surface never resigns on close and its cursor pop never happens (:220 "Escape restores the
    previous cursor" fails) and :196's key assertion reads nil. This is exactly AppKit's promotion
    machinery gone out of commission: the window count (21) and the policy (.accessory) are
    IDENTICAL on red and green doorsteps — the only observed difference is `NSApp.isActive` — and
    the promotion is what the class's FIRST `makeKey` performs when it is intact (isolation does it
    itself; the green compositions' `keyTake` probe read `active=true policy=1`, the app left active
    by a late successful activation).
    THE CURE, in the CLASS'S own surface, with NO assertion weakened and `TextSelectionWindowTests`
    body untouched except hooks: the class's setUp captures `LeaveAsFound.capture()` and re-establishes
    the promotion machinery with AppKit's own reset — `setActivationPolicy(.regular)` — the same reset
    every `.accessory` → `.regular` → `.accessory` cycle performs (a probe confirmed plain
    `NSApp.activate` does NOT recover the promotion from the poisoned state, the flip does); the
    class's shared-hook `LeaveAsFound.restore` puts the found policy and the active flag back in
    teardown, so the class leaves exactly what it found (ToolbarLayoutTests, the next and last
    StareTests suite, still passes). Mechanism 2's sweep of the remaining classes (every hook reuses
    the shared `LeaveAsFound` helper in `TestWindowPlacement`, no new mechanism):
    `CaptureHistoryPanelKeyboardTests`, `CaptureHistoryMenuKeyboardSurvivalTests`,
    `CaptureHistoryPanelTests`, `CaptureHistoryOutsideClickTests` (`showPanel` keys the sheet and each
    leaves an active app/key window), and `SettingsShortcutTests` (its modes' activate/toggle and the
    settings window's open leave activation); `CaptureHistoryContextMenuTests` opens no windows and
    was left unhooked. Numbers of the closing runs: the delivered probe (bounded filter) — EXIT=0,
    0 failures, both bundles passed; the FULL suite unpiped as delivered —
    `swift test > .build/r9.log 2>&1; echo EXIT=$?` — EXIT=0, 920 tests (527 StareTests + 393
    StareCore), 0 failures, run TWICE consecutively with the same result (second run: EXIT=0, 920
    tests, 0 failures, both bundles passed), 0 added `--skip`, 0 weakened assertion, and every earlier
    suite's leave-as-found hooks untouched.
- **L6** (worker, 2026-11-26, the correction pass, S7 corrected + S10): BOTH causes are the owner's two
  reports. S7 CORRECTED — "ahora cada que cierro el capture history con la combinacion de keys hace foco
  en finder y no en la app que estaba usando, eso esta mal": a correction of the previous round (L3),
  which built the rule HE had asked for ("editor o finder", L1) literally. The history's close now hands
  the foreground back to the app the user was in before the history opened:
  `OverlayController.HistoryFocusDestination`'s third fallback `.finder` is replaced by `.previousApp`
  and `captureHistoryPanelDidHide` runs the standing restore the controller always owned
  (`rememberFrontmostApplication` at the sheet's open, `restoreFrontmostApplication` at the hide,
  re-exposed as the witnessed seam `restorePreviousFrontmost`); the Finder fallback and its seam
  (`activateFinder`/`activateFinderApplication`) are REMOVED. An open editor still takes the key first
  (the value rule and the witnessed editor route unchanged; the editor route now additionally asserts
  the previous-app restore NEVER runs while an editor stands open), and the board canvas keeps its rule;
  deliveries and refusals untouched (`deliverHistoryPick` and the identity ledger untouched).
  S10 — "settings tambien tiene que tener icono en el dock como el editor": ONE policy rule, not two
  that fight. `CaptureEditorController.dockActivationPolicy(forEditorCount:)` is re-derived as
  `dockActivationPolicy(forUserWindowCount:)` — the census is the count of the app's user-facing
  windows open, WHATEVER kind they are (editor, Settings window, or both), one number; the rule itself
  is unchanged (0 → accessory, any → regular). The reflection stays the editor controller's ONE site,
  fed by both halves: the app delegate — the owner that sees both kinds — installs the Settings
  window's 0/1 (`OverlayController.setDockCensusOfOtherUserWindows`) and the Settings window's
  open/close announces its change (`SettingsWindowController.isWindowOpen` + `dockPresenceDidChange`,
  announced in `show()` and in `windowWillClose`) into `OverlayController.refreshDockPresence`, so it
  re-runs the ONE reflection the editor open/close already ride. Evidence — RED observed
  before each fix (the re-derived tests fail to compile against the missing `.previousApp` destination,
  `forUserWindowCount` and the census seams); GREEN — focused run
  `swift test --filter "CaptureHistoryPanel|CaptureEditorDock|SettingsShortcut|SettingsWindowSizing"
  > .build/b.log 2>&1; echo EXIT=$?` — EXIT=0 TWICE consecutively, 45 StareTests, 0 failures (9 dock +
  27 history panel/keyboard/leave-focus + 7 shortcut + 3 sizing), StareCore 0 under this filter;
  additions 2 (the S10 runtime census test across no-windows/editor-only/both/closing-one-of-two/
  Settings-only/last-close, and the app-delegate wiring canary); RE-DERIVED 4, each with a canary
  naming its report (the dock policy value test → `...AnswersByTheUserWindowCount` "S10: ... whatever
  kind"; the S7 value test → `...NamesTheEditorTheBoardAndTheAppTheUserWasIn` "S7 CORRECTED: ... the
  Finder fallback is removed"; the S7 finder route test → `...ReturnsToTheAppTheUserWasIn` "S7
  CORRECTED: ... never a Finder activation"; the editor route's added assertion "an open editor still
  takes the key FIRST"). Two harness discoveries recorded: one composition poison and one locator
  hijack, both in the census test's own surfaces — (1) a census runtime test that opens and closes a
  REAL Settings window left the window standing closed-but-listed in `NSApp.windows`, and the LATER
  classes' title locators (`NSApp.windows.first { $0.title == ... }` in SettingsShortcutTests and
  SettingsWindowSizingTests) found IT — the lift test read a closed `level 0` window and the sizing
  tests read `contentMinSize (0,0)` / `minSize (0,32)` off it; cured by releasing the census window
  with its close (`isReleasedWhenClosed = true` before the final close), which removes it from the
  window list; skip-probes bounded it: the delivered filter with `--skip "Census"` EXIT=0, and
  `CaptureEditorDock|SettingsShortcut|SettingsWindowSizing` without the census test EXIT=0, while the
  full delivered filter without the cure was EXIT=1 twice. (2) The same class also got the shared
  `LeaveAsFound` hooks (the class flips the activation policy repeatedly) — right thing for hygiene,
  but NOT the cure: full-run EXIT=1 identical with hooks alone; the evidence above is the ADD/REMOVE
  proof. Two deliberate exclusions: the Dock icon's REAL visibility while the Settings window is open
  and the actual reactivation of the owner's app are runtime system appearances — the owner's eye
  closes those (the tests witness the routes, as the harness always has); and the Onboarding window
  was deliberately NOT added to the census — the owner named the editor and Settings only, and the
  guide promotes to Settings when it finishes.
