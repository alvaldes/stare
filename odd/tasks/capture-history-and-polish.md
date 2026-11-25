# Capture history and card polish: pinned cards, ⌥⇧I history, bar and Settings geometry

Five UI requests from the owner over the shipped capture flow: the post-capture card gains pin and close,
a paste-style capture history opens on ⌥⇧I, the vertical bar's inset matches the horizontal one, the
Settings placement card reaches the pane edge, and the pointer preview gets shorter.
Branch `feat/capture-extras`, off `main` at `65c94a0`. Runner: `swift test` (one class per invocation).

## Specs

- **S1** "- la card al realizar una captura debe tener el pin y el close, hay que bajarle el tamanno y debe
  de qudar por encima de todo. de esta forma se puede fijar y se queda en esa posicion. y si salen mas
  capturas se apilan."
- **S2** "- Con opt+shift+I lo que debe salir es el historial al estilo https://pasteapp.io. Un detalle si
  esta abierto dibujo se debe cerrar y abrir historial. Con whiteboard si puede quedar por encima y permitir
  pegar imagenes en whiteboard."
- **S2a** (owner's answer to the persistence question, binding) "Persistente en disco, tope 50, con botón de
  limpiar": the history lives in Application Support, keeps the newest 50 captures, and the panel itself can
  clear it.
- **S3** "- la barra vertical debe estar a la misma distancia del borde derecho/izquierdo que lo esta del
  borde inferior/superior"
- **S4** "- el card placement del bar no llega hasta el final y deja un espacio a la derecha en settins"
- **S5** "- el preview del pointer highlighter tiene demasiada altura"

## Tasks

| ID | Specs | Task | Route | Commit |
| --- | --- | --- | --- | --- |
| T1 | S1 | Card keeps its pin and close, smaller plate, pinned cards hold their spot, captures stack | parent | e6fcdec |
| T2a | S2, S2a | Capture history on ⌥⇧I: persisted store (50), paste-style panel, closes drawing, floats over the board | worker | 797d9cd |
| T2b | S2, S2a | A chosen capture pastes into the open board as one page image layer, moved and resized with the editor's ⌥ gestures | worker | 797d9cd |
| T3 | S3 | Vertical bar sits the same distance from the side edge as the horizontal bar does from the top/bottom | parent | c594f15 |
| T4 | S4 | Settings placement card spans the pane instead of stopping at 700 pt | parent | 797d9cd |
| T5 | S5 | Pointer highlighter preview is shorter | parent | 17db96d |

## Backlog (owner, after the first manual pass — recorded, not started)

- **B1** "en settings se debe de poder configurar el tamanno de los preview en la grilla del historial" — **closed (L19)**: `AppPreferences.history` (`HistoryPreference.thumbnailSize`, 120–280 pt, default 170) rides in the versioned blob and is decoded leniently; the History pane grows a Previews card; the panel reads the preference on every `refresh()`, so the change reaches the next ⌥⇧I instead of the panel built at launch.
- **B2** "al historial le falta un comportamiento como maccy que si doy click afuera se cierra" — **closed (L22)**: the panel installs a local monitor (clicks in Stare's own windows) and a global one (every other app), and the first click that is neither the panel nor inside its frame closes it. The decision is a value rule, `CaptureHistoryPanel.hides(forClickOnPanelWindow:insidePanelFrame:)`, so it is pinned without screens or event taps.
- **B3** "la imagen del historial si se pega en la pizarra pero no centrada" — **closed (L18)**: the shared clamp capped each axis at the canvas and kept the origin the wider size had produced, so an image bigger than the visible area was squashed AND pushed off centre; a RED proved it (900×700 into 800×600 landed at x=-50 with midX 350 instead of 400). The paste now fits by ONE factor (`BoardImage.fittedSize`) before the clamp, which then cannot move a centred rect, and an empty visible area places the layer at the page origin instead of at a negative half-size. `testAnImageLargerThanTheVisibleAreaIsFittedWholeAndStaysCentred`, `testAPasteIntoAnEmptyVisibleAreaLandsAtThePageOriginAtItsOwnSize`.
- **B4** "la imagen en la pizarra debe de poder ajustarse como mismo se hace con el cursor tool (V) en las demas marcas y si se ajusta el tamano debe de poser mantener la forma si se hace el ajuste con shift presisonado. Esto del shift presionado es para todo lo que hace el tool 'V'"
- **B5** "un detalle es que la imagen se inserta invertida - /Users/alvaldes/Library/Application Support/dev.alvaldes.stare/CaptureHistory/captures/39E94DD1-2481-46FB-A833-543435EB2CD9.png" — **closed (L18)**: the rect was right and the pixels were mirrored — `drawPageImage` drew the CGImage plainly into a flipped view, the only such draw in the codebase; it now unflips about the rect's `midY` the way the capture card and the editor's canvas already do. `testThePageImagePaintsTheRightWayUp`. — **closed (L20/L21/L22)**: the layer is grabbed, moved and corner-resized with the select tool (V), no modifier; Shift holds the aspect ratio through `EditorCropRule.lockedRegion`, which the board AND the editor's element resize both use, so the rule is the same wherever an element is resized with grips. Inside the board the image layer is the only element that carries grips, so "las demas marcas" has no other surface there; the crop marquee keeps its free rule because the crop is the frame, not an element.
- **B6** "el esc en la pizarra no borra la imagen" — **closed (L18)**: the overlay's clear knows strokes only, so the layer survived a hint that promises "esc clear page". The board's `keyDown` now takes keyCode 53, lets the overlay drop a mark selection first, and then removes the page's layer. `testEscapeOnTheBoardClearsTheImageWithTheMarks`, `testEscapeWithAMarkSelectedOnlyDropsTheSelectionAndKeepsTheImage`.
- **B7** "settings debe tener un min de ancho y altura al que se puede achicar" — **closed (L19)**: the floor existed (860×560) but was never enforced. Assigning the auto-layout `NSHostingView` as content view makes AppKit re-derive the content minimum from constraints the hosting view does not carry, so `contentMinSize` read `(0,0)` on the first open and the window could be dragged to nothing. It is re-asserted after every content-view assignment, it is ONE constant shared with the SwiftUI root instead of two literals, and reopening now keeps the size the user chose instead of stamping the default back.
- **B8 (closed in L25 as ROWS, after L24's revert)** "las card en settings que estan en 2 col deben de verse bien y para eso deben tener un estilo donde se trate de que en una fila ambas card tengan ls misma altura o que la combinacion de varias en una col sea la altua de la card de la otra col asi queda simetrico todo." — **closed (L19)**, pending the owner's eye: each pane's column is a `SettingsCardStack` (a `Layout`) that takes the height it is proposed and shares the difference among its cards, so the two columns of a pane end on the same line and a lone card grows to the height of the pair beside it.
- **B9** "de \"1. Cursor sobre las cards\" no se ve el cursor normal ni en dibujo ni en la pizarra" — the arrow rule landed in `CaptureCardView` (`resetCursorRects` + a `.cursorUpdate` tracking area) and it is not enough: while the overlay or the board is up, the whole display is one crosshair, and the card's own tracking does not beat it. Next probe: log which window gets `cursorUpdate` while the pointer sits on a card in each mode; if the overlay's imperative `NSCursor.crosshair.set()` wins, the overlay's cursor path has to skip the pointer while it is inside a visible card's frame (a small registry of visible card rects the controller exposes), instead of the card trying to out-shout it.
- **B10** "de \"3 y 4. Flechas muertas y Enter copiando en blanco\" si funcioan lo del enter pero no lo de las flechas" — Enter now picks and copies, so the keys reach `CaptureHistoryPanel.handleKey` and the activation fix holds; the arrows specifically do not move the selection. Next probe: `Diag` line inside `handleKey` printing the keyCode and the index before/after, with the panel open over two different surfaces (desktop and an open board), and a check that `entries.count > 1` at the time. Do not assume the mapping: keyCodes 123/124/125/126 are already the documented ones, so the open questions are whether the event arrives at all and whether the SwiftUI grid keeps its focus.

B3, B5 and B6 are defects in what T2b just shipped, not new wishes; B1, B2, B4, B7 and B8 are new work. B4 leaks out of the board: the Shift-to-keep-the-shape rule is asked for every surface the cursor tool touches.

## Log

- **L1** (the owner's request, verbatim):
  "- la card al realizar una captura debe tener el pin y el close, hay que bajarle el tamanno y debe de qudar por encima
  de todo. de esta forma se puede fijar y se queda en esa posicion. y si salen mas capturas se apilan.
  - Con opt+shift+I lo que debe salir es el historial al estilo https://pasteapp.io. Un detalle si esta abierto dibujo
  se debe cerrar y abrir historial. Con whiteboard si puede quedar por encima y permitir pegar imagenes en whiteboard.
  - la barra vertical debe estar a la misma distancia del borde derecho/izquierdo que lo esta del borde inferior/superior
  - el card placement del bar no llega hasta el final y deja un espacio a la derecha en settins
  - el preview del pointer highlighter tiene demasiada altura"
- **L2** (owner's answer to the persistence question, verbatim option) "Persistente en disco, tope 50, con botón de limpiar" — no session-only history. Recorded as S2a.
- **L3** (owner's answer on how far the board paste goes, verbatim option) "Capa de imagen en la página (mover y redimensionar)" — not the cheap "fondo de la página" variant and not clipboard-only. This is why T2 split into the history itself (T2a) and the board's image layer (T2b).
- **L4** (evidence, T3): the anchors were 8% of the screen's WIDTH for the side borders and 8% of its HEIGHT for the top/bottom ones, so on a 1512×982 screen the column sat 100 pt in while the row sat 58 pt in. `ToolbarGripperSpec.defaultAnchor(border:screenFrame:)` now reads the cross-edge inset off the height for every border; the pinned top-border rect (456, 58, 600, 42) is unchanged, so nothing that already worked moved. `GeneralPreferencesTests` 67/67.
- **L5** (evidence, T4/T5): the Placement card was the Bar pane's only capped card — the pool card above it already spanned the pane — so the cap came off. The pointer tile went from 168 pt (exactly the default highlight's 161 pt extent, i.e. "real size") to 120 pt; the default now draws at 75 % and the caption says so, which is the trade the owner asked for. `PointerPreviewSizeTests` 3/3, `PointerHighlightRendererTests` 20/20.
- **L6** (evidence, T1): the card had no controls and a 260×170 thumbnail cap. It now carries a pin and a close on the plate, is 190×126 with a 6 pt backdrop, keeps its level above the palettes and the overlay, and a pinned card leaves the stack: it is never evicted by the cap and never pushed by a later capture. Undo/persistence of the pin is session-scoped on purpose. `CaptureCardTests` 7/7.
- **L7** (known gap, needs the owner's word): the capture editor's own save/copy path never leaves `CaptureEditor.swift`, so an edited variant saved from the editor does not reach the history; the capture the editor received does, because `deliver` recorded it first. Closing it needs a seam in `CaptureEditor.swift`.
- **L8** (known gap, reported by the worker): the board's image layer is not undoable — the board's journal is stroke-typed and an image op would mean touching `DrawingSession.swift`, which was outside that unit's surfaces.
- **L9** (evidence, verification and the fixes it forced): an independent verifier reproduced eight findings against the first cut, six of them real and fixed before the commits — the panel's keyboard never reached the hosting view (`NSHostingView` declines first responder, so Esc, the arrows and ↵ were dead through the real event path), the store trusted `fileName` from the index and would read and delete outside its own folder on a hand-edited index, ↓/↑ walked the grid backwards, a board image hanging off the base was squeezed into the intersection instead of clipped, the cap was not enforced at load, and a zero-width screen docked the column dead centre. Each fix landed after a RED that reproduced the probe. New classes: `CaptureHistoryPanelKeyboardTests`, `CaptureHistoryIndexPathTests`, `BoardImageClipTests`, `ToolbarAnchorRegressionTests`.
- **L10** (evidence, commits): `c594f15` (T3), `17db96d` (T5), `e6fcdec` (T1), `797d9cd` (T2a + T2b + T4 + docs). Full suite 619 tests, 0 failures, except `RedactionDispatchTests.testEveryPixelateBlockIsConstantInsideThePatch`, which fails in roughly one run in three on a tree this diff never touches (it passes 3/3 standalone and the class was green inside an earlier full run): a load-dependent pre-existing flake, reported as such rather than worked around.
- **L11** (slice note):`797d9cd` carries T2a and T2b together (about 1,300 authored lines) because the pick route, the board's image layer and the controller that owns both share `OverlayController.swift`; splitting them would have left a commit that could not build. Delivery shape when publishing: T3, T5 and T1 are three small PRs of their own, and T2 is one PR of two review passes — the history (store, panel, hotkey) and the board's image layer.
- **L12** (owner's second manual pass, verbatim, and what it changed):
  "- el cursor sobre las card de captura debe ser el normal no el de la tool en dibujo o en whiteboard
  - cuando se toma una captra y se fija esta queda abajo de la pila pero cuando se siguen tomando capturas y se apilan arriba y hago pin de la cuarta esta se fija en la posicion y el resto de capturas se cierra porque no estan pineadas. Lo que deberia hacer seguido de eso es bajar la captura 4 a donde estaba la captura 2 asi sigue ese efecto de apilada y la siguiente captura aparece en posicion 3.
  - en el historial las flechas no hacen nada
  - historial: el enter no copia la imagen, copia algo en blanco"
  Two of these are corrections to S1 and two are defects in the shipped T2a: the card now answers with the arrow cursor, and the stack is repacked after every appearance and every disappearance with pinned cards keeping their slot, so a pinned card drops into the free slot instead of hanging where the stack had grown to. The dead keyboard was not the responder chain — the panel is a non-activating window and the app was never activated, so every key went to the app underneath (which is also why Return "copied a blank image": it pasted that app's stale clipboard). The panel now activates Stare, remembers the frontmost app for the hide hook to restore, and routes keys through a local monitor as well as the responder chain. Pinned by `testThePointerOverTheCardIsTheArrowEvenWhileDrawing`, `testPinningTheNewestCardDropsItIntoTheFreeSlotWhenTheOthersGo`, and the strengthened `testAPickWithNoBoardOpenCopiesToThePasteboard`, which now decodes what was copied instead of trusting the pasteboard type.
- **L13** (owner's third pass, verbatim): "de \"1. Cursor sobre las cards\" no se ve el cursor normal ni en dibujo ni en la pizarra" and "de \"3 y 4. Flechas muertas y Enter copiando en blanco\" si funcioan lo del enter pero no lo de las flechas". So L12's cursor fix did not hold and its arrow half did not either, while its Enter half did — the activation half is confirmed, the key-routing half is not. Both are recorded as B9 and B10 with the next probe each, not guessed at: the card cannot out-shout a screen-wide crosshair by itself, and the arrows need an observed event rather than another mapping theory.

- **L14** (owner decision, verbatim): "Historia en ⌥⇧I, pin-latest sin tecla".
  The capture history owns ⌥⇧I. The pinned image loses its fixed global binding
  with it — `PinnedImageHotkeyDefaults` and its registration are gone — so the
  card's pin button and the menu's Pin Image are the whole path to float a pin and
  take it down again. The one fixed binding left is the history's.

- **L15** (owner instruction, verbatim): "estan super-yolo asi que dale sigue y avisame cuando termines".
  Both defects were worked to the probes L13 recorded, and both turned out to sit where the probe said.
  **B9** is the drawing layer, not the card: the overlay sets one crosshair for a whole display, so the
  card's own tracking area never wins. The rule now lives in `StareCore.CardCursor.isOverCard` and the
  controller re-answers the arrow from a monitor (`installCardCursorMonitor`) while the pointer sits
  inside a visible card's frame, through a new `CaptureCardController.visibleCardFrames` seam; five
  tests pin the comparison. The look itself still wants a human eye over a card in drawing mode and on
  the board.
  **B10** was not routing: `handleKey` maps 123/126/124/125 and two tests already drive those codes
  through `panel.sendEvent`, so the model moved and Return picked what nobody could see. The grid did
  not follow the selection, so it walked out of the viewport. The panel now scrolls the selected cell
  to the middle on every selection change, and `handleKey` carries the probe L13 asked for: with
  `STARE_HISTORY_KEY_PROBE=1` in the environment it logs keyCode, entry count and the selection before
  and after; off, it logs nothing, because a probe that ran always would grow the log on every arrow press.

- **L16** (owner disposition, verbatim): "En el historial las flechas no mueven el foco en la captura para
  seleccionar, pero esto no lo vamos a tratar ahora porque como aún hay que seguir trabajando en esta parte
  del historial, no vamos a trabajar esto ahora sino cuando trabajemos esta feature."
  So B10 stays open on purpose: the selection walks the model and the grid follows it, but the focus a user
  reads as "the capture I am choosing" does not move with the arrows. It is the history feature's own work,
  not a fix to bolt on now. Closed on the same pass: the board now keeps the arrow over a card (`openBoard`
  sets `isBoardActive`, never `isActive`, so the cursor monitor was inert there), and a capture hands the
  keyboard back to the app the user came from instead of leaving Stare frontmost — the card is a
  non-activating panel, so it stays visible while the focus returns.
  What pins the cursor one: `CardCursorRoutingTests` asks the controller's own
  `cursorSkipsTheCard` in each mode, and reverting the guard to `isActive` alone makes
  the board test fail — the check that this fix cannot silently regress. Both changes
  still want the owner's eye on the next manual pass, which is the only place the arrow
  and the returning keyboard can actually be seen.

- **L17** (owner decision, verbatim): "no aparece asi que dejemoslo asi porque no veo una solucion y
  llevamos dando vueltas en esto ya un tiempo y no veo la salida". B9's board half stops here, on purpose.
  What three passes established: the drawing mode gives the arrow (`cursorSkipsTheCard` answers in both
  modes, `CardCursorRoutingTests` pins it), the board does not; the canvas re-asserts its cursor on
  `mouseMoved` as well as on `cursorUpdate`; and the card is a non-activating panel that does not take
  mouse-moved events, so moves over it are delivered to the canvas underneath, which is the surface
  that keeps winning. What is *not* known is which of the remaining re-assertion sites does it, because
  the probe that would say so (`STARE_CURSOR_PROBE=1`, logging type, swallow decision and whether the
  event came from the card or the canvas) was never run. The code stays as it is: it is correct for the
  overlay and harmless on the board. A future pass should start by reading that probe, and if the answer
  is "another view re-asserts", the shape of the fix is to have the card take mouse-moved events rather
  than to keep dropping events from the canvas.

- **L18** (the three T2b defects, B3/B5/B6, worked to the probes): all three sat where the reported
  symptom said, and each one was reproduced before it was fixed.
  **B5** is the paint, not the placement: `drawPageImage` called `context.draw(layer.image, in: rect)`
  plainly inside a flipped view — the only CGImage draw in the sources without a flip — so the frame
  landed where it should and the pixels landed mirrored. The codebase's own convention (capture card,
  editor canvas) unflips about the rect's `midY`, which is rect-local and needs no `bounds` knowledge.
  **B3** is the shared clamp, and the RED pinned it precisely: 900×700 into 800×600 came back
  `(-50, -50, 800, 600)` — both axes capped independently, so the shape was squashed and the origin,
  which had been computed for the wider size, was left behind (midX 350 where the area's is 400). The
  paste now fits by one factor (`BoardImage.fittedSize`) before calling the editor's clamp, so the
  clamp only validates and can no longer move a centred rect, and an empty visible area places the
  layer at the page origin instead of at a negative half-size. `CanvasComposition` itself is untouched,
  so the editor's drop and ⌘V paste are exactly as they were.
  **B6** is a missing branch: `OverlayView.keyDown` owns Escape and `onClearMarks` reaches the journal,
  which is stroke-typed, so nothing ever touched `board.currentPage.image`. The board's `keyDown` now
  claims keyCode 53, lets the overlay give up a mark selection first (one stray click still costs
  nothing) and then drops the layer through `removePageImageOnEscape`. Not journalled, on purpose: the
  image lane's edits are session values (`⌫`, `⌥`-drag), so ⌘Z after an Escape restores the marks and
  not the picture — the same asymmetry that already existed, rather than a new one.
  **Evidence**: `swift test --filter BoardImage` 17/17, then the full suite 843 tests, 0 failures,
  `RedactionDispatchTests` included (the known flake did not fire this run).
  `testThePageImagePaintsTheRightWayUp` needed a measured convention before it could say anything: its
  first version mirrored the row twice and passed on the broken code. A throwaway probe established
  that `NSBitmapImageRep.colorAt(x: 0)` is the visual TOP and that a flipped view's cache maps view y
  straight onto it, so the helper only scales. With the mapping right the RED was unambiguous — rows
  260–290 (the frame's top) painted blue, rows 300–330 its bottom painted red.
  Not done here, on purpose: B4 (⌥ resize with Shift keeping the shape) leaks out of the board into
  every surface the V tool touches, and the paste's grab clamp still runs in view units while the
  ⌥-drag clamps in page units, so the first drag after a paste at zoom ≠ 1 can nudge the layer.

- **L19** (the Settings batch, B1/B7/B8): **B7 turned out to be a real defect with a measured root cause.**
  The floor was written down twice — `SettingsWindowController.minSize` and a `.frame(minWidth: 860,
  minHeight: 560)` literal in `SettingsView` — and neither number was what the window enforced:
  assigning an auto-layout content view makes AppKit re-derive the content minimum from constraints an
  `NSHostingView` does not carry, so the first open left `contentMinSize` at `(0, 0)` and the window
  could be dragged away to nothing. The RED is that exact read (`(0.0, 0.0)` where `(860, 560)` was
  expected). It is now one `static let minimumContentSize`, re-asserted after every content-view
  assignment and handed to `SettingsView`, whose root lays out from it. The same map found the
  neighbouring bug: `show()` rebuilt the hosting view at the *default* size, and assigning a content
  view resizes the window to it, so every reopen threw away the resize the user had made —
  `testReopeningSettingsKeepsTheSizeTheUserChose`.
  **B1** is a new preference, so there is no earlier behaviour to RED: `HistoryPreference` lives in the
  versioned blob (`AppPreferences.history`, appended last, decoded leniently like `redactionStyle`),
  clamped in the initialiser and in the setter, and the History pane's Previews card drives it. The one
  behaviour worth pinning was staleness: the panel is built lazily once, so it reads a provider on every
  `refresh()` instead of capturing the value at launch — `testThePanelReadsTheThumbnailSizeEveryTimeItRefreshes`.
  `HistoryPane` takes the model as an optional and the card observes it in its own `HistoryPreviewsCard`,
  so the three existing `HistoryPane(history:)` render tests keep their in-memory isolation.
  **B8** needed a mechanism, not a tweak: a plain `VStack` leaves spare height at the bottom, so the
  column beside a taller one ends ragged. Each pane column is now a `SettingsCardStack`, a custom
  `Layout` that accepts the height it is proposed and shares the surplus among its cards
  (`SettingsCardStack.distributed`). The two columns are handed the taller one's height, so a lone card
  grows to the pair beside it and both columns bottom out together. Four panes switched over; the
  single-column fold is untouched because nothing proposes it extra height. Pinned by
  `SettingsColumnSymmetryTests` (4 cases, including the 2-vs-1 shape the owner described). What a test
  cannot see is how it *looks*: this one still wants the owner's eye on the next manual pass.
  **Evidence**: `swift test --filter "HistoryPreference|SettingsColumnSymmetry|SettingsWindowSizing|CaptureHistoryThumbnailSize"`
  green 7/7 after the REDs above; `swift test --filter Settings` 38 tests with one failure that is not
  this diff's and is pre-existing (below); whole-suite run 846 tests, 0 failures reported.
  **Two things the whole-suite run cannot be trusted to say, both reproduced at base `60189f6` in a
  scratch worktree (842 tests, 0 failures, same nonzero exit):**
  1. The `StareTests` bundle SEGFAULTS mid-run (`xctest … exited with unexpected signal code 11`, the
     message spliced into the middle of a test name) and `swift test` exits 1 even with zero XCTest
     failures. The base commit does exactly the same, so the nonzero exit is toolchain noise, not a
     regression — but it also means a whole-bundle run can SKIP suites silently: `SettingsColumnSymmetryTests`
     and `SettingsWindowSizingTests` are absent from the full-run log entirely, because they sort after
     the crash point. That is why they were verified through the filtered run, where they ran 6/6 green.
     Any future "full suite is green" claim in this repository needs the started/passed case counts, not
     just the `Executed N tests` line.
  2. `SettingsBarPreviewTests.testTheMinimumWindowWidthKeepsEveryBarItem` fails by 0.067 pt
     (`73.0` vs `73.0677`) when the settings tests are run on their own, and passes inside a full run. It
     does the same at base, so it is an order/environment sensitivity that predates this work, not a
     B7 effect — pinned by running that one filter against both trees.

- **L20** (owner's manual pass on L18-L19, verbatim asks): "hay que hacer que la imagen que se inserte no
  ocupe la pantalla completa. Quitar el uso de opt+ para poder editar y que se pueda editar con el tool
  'v'"; "no funciona aun se achica hasta casi desaparecer"; "si funciona, pero el la session de this
  session hay que cambiarla para el historial siempre que haya algo no importa de que session. Y bajalo
  al final para que encema este el clear"; "revisa capture que es el que esta roto"; plus a new one: the
  Pointer Highlight section's settings button wrapped to two lines.
  **Two regressions, one cause.** `SettingsCardStack.sizeThatFits` answered a `.infinity` height
  proposal with `.infinity` — and every pane's cards live in a `ScrollView`, whose scroll-axis proposal
  is exactly that. Each card got an unbounded height: the Capture pane broke and the Pointer Highlight
  button wrapped. The probe: with the guard removed the render test dies at
  `Fatal error: view origin is invalid: (389.0, nan)`, which is the class of breakage the owner saw.
  `sizeThatFits`/`placeSubviews` now take a proposal only when it is finite, and the regression is
  pinned by `testATwoColumnPaneLaysOutInFiniteSpace` (a real render, since no pure function can see it).
  **B7 needed both floors.** `contentMinSize` alone does not survive an auto-layout content view, so the
  window now also carries `minSize` (the frame floor derived from the content floor) and
  `windowWillResize` clamps — the delegate is the one place a live drag passes. `SettingsWindowController`
  became an `NSObject`/`NSWindowDelegate` for it; `testALiveResizeIsClampedToTheMinimumFrame` pins the clamp.
  **B3 and B4.** A paste is fitted into 60 % of the visible area (`BoardImage.insertedAreaFraction`), so a
  screen capture reads as an object on the page instead of covering it, and the layer is claimed by the
  select tool (V) rather than ⌥ — the modifier is gone from `mouseDown` and from both drag tests.
  **History pane.** It reads the persisted `CaptureHistoryStore` (any session) instead of the session's
  in-memory list, opens a stored capture through the same `onReopen` editor handoff, clears the store,
  and the Clear card sits above the list. Its three tests were rewritten to the store-backed pane.
  **Evidence**: `--filter BoardImage` 17/17, `--filter "SettingsWindowSizing|SettingsColumnSymmetry|CaptureHistoryPane"`
  30 tests 0 failures, whole suite 1020 started / 1020 passed / 0 failures (the single `signal code 11`
  line is the pre-existing second-runner crash recorded in L19).

- **L21** (owner's third pass): the sidebar row for "Pointer Highlight" wrapped to two lines the moment
  it became the selected row, jumping the whole list; the board's image now inserts and resizes with V,
  but Shift did not hold the shape and the move ran away from the pointer.
  **The jump.** The row's label is `.lineLimit(1)` now, and the sidebar went 190 → 214 pt. Note what the
  measurement says and does not say: at 190 the longest title fit in semibold by about half a point, so
  the old width was not *provably* the cause — SwiftUI's metrics for that string disagree with `NSFont`
  by fractions, and a row sitting on that edge wraps in the app while measuring fine in a test. What the
  test pins therefore is the SLACK (≥ 12 pt over the longest title in semibold,
  `SettingsSidebarWidthTests`), not "it fit": at 190 that guard fails, at 214 it passes. The `lineLimit`
  is the hard guarantee that the list can never jump again, whatever the numbers do.
  **The move.** `mouseDragged` applied the drag's ABSOLUTE travel — measured from the grab point — as a
  DELTA on top of the already-moved rect, so every event re-added the whole travel: three events of
  40 pt moved the layer 120 pt. That is the owner's "se mueve demasiado". A move is now an absolute
  destination computed from the placement captured at grab (`ImageGesture.move(grab:startPageRect:)`),
  which is faithful at any zoom. RED observed: with the old arithmetic the test reads 120 pt where 40
  was asked, and 75 where 25 was.
  **Shift.** The corner grips now hold the start rect's aspect ratio through
  `EditorCropRule.lockedRegion` — placed beside the free `region` rule in `CaptureEditor.swift` so every
  surface that resizes with these handles shares one answer instead of each writing its own aspect
  maths. The first cut anchored the dragged edge instead of the opposite one and the test caught it
  (maxX 680 where 500 was expected).
  **Evidence**: `--filter BoardImageLayerTests` 10/10, `--filter SettingsSidebarWidth` 2/2, whole suite
  1023 started / 1022 passed / 0 failures (the one count is the truncated line from the pre-existing
  segfault in L19).

- **L22** (closing the backlog): **B2** landed as two monitors — a LOCAL one for clicks in Stare's
  own windows (another window of ours, the board) and a GLOBAL one for every other app, because neither
  sees both worlds and a paste-style palette has to close on the first click anywhere. Mouse events
  need no accessibility grant, unlike the keyboard monitor. The decision itself is a value rule
  (`hides(forClickOnPanelWindow:insidePanelFrame:)`) and a click inside the panel's frame counts as the
  panel's even when the window beneath took it; both monitors are torn down in `hide()`, pinned by
  `CaptureHistoryOutsideClickTests` (3 tests).
  **B4 is closed too, except the part that was never the V tool.** Shift-aspect lives in
  `EditorCropRule.lockedRegion`, beside the free `region` rule, so the board's image layer and the
  editor's element grips resize through the SAME aspect maths: the editor's `.layerResize` now reads
  Shift as well, which was safe because nothing else in `CaptureEditor` binds it. The owner's "no
  importa qué elemento sea" holds wherever an element is resized with grips; the crop marquee keeps its
  free rule, because the crop is the frame, not an element.
  **Evidence**: whole suite 1026 started / 1024 passed / 0 failed / 0 skipped, with the single
  pre-existing `signal code 11` line from L19 accounting for the two-count difference in the log;
  installed build verified at each step.

- **L23** (owner: "regresamos y no se guardo ... los cambios de las card en overlay, pointer y demas"):
  nothing was lost — every change is in the working tree, nothing was ever committed — but the SYMMETRY
  was gone, and the cause was L20's own fix. Making `SettingsCardStack` answer an `.infinity` proposal
  with its content height was what stopped the Capture pane from exploding, and that answer is also the
  only thing the equalisation had been riding on: the cards live in a `ScrollView`, so NOTHING in the
  chain ever proposes a column more height than its own content, and "take the height you are given"
  therefore never fires. Every build installed so far was either broken (the first one, infinite
  heights) or ragged — the symmetry had never actually reached the screen.
  The recovery is `SettingsColumnPair`, a `Layout` that measures both columns itself, keeps the taller
  measurement and places BOTH at it with a finite proposal; the inner `SettingsCardStack` then shares
  that height among its cards, so a lone card matches the pair beside it and both columns bottom out
  together. The rule it drives is pure and pinned (`SettingsColumnPair.placements`,
  `testThePairPlacesBothColumnsAtTheTallerColumnsHeight`); the finiteness render test still guards the
  other direction.
  **Also fixed here**: the drag test's `XCTAssertEqual(after.size, before.size)` was brittle — the
  round trip through page space at zoom 1.25 leaves `99.99999999999997` where `100` is meant, so it
  failed a full run for a rounding artefact. The real invariant is that a move never resamples, and it
  is now asserted on the image's own pixel dimensions.
  **Evidence**: whole suite 1026 started / 1024 passed / 0 failed (the two-count gap is the pre-existing
  segfault splice from L19); installed 21:04.

- **L24** (rendered the panes and looked at them): B8's equalisation is REVERTED. The renders the
  selftest already produces (`/tmp/stare-settings-<area>-<appearance>.png`) show the truth my tests
  could not: with `SettingsColumnPair` in place the columns still ended ragged in Overlay and Whiteboard,
  and Capture spread its cards over the whole viewport. The probe says why — `PAIR ideals=[316.75,
  893.25]`: measuring a column's ideal INSIDE the pane's `ScrollView` feeds the previous stretch back
  into the measurement, so the shorter column reports the viewport height and "the tallest column" is
  meaningless. Two different mechanisms (a flexible frame, then a `Layout` that hands both columns a
  height) fail the same way, because both need a measurement taken outside the stretch, and a SwiftUI
  `ScrollView` gives no such pass for opaque `ViewBuilder` columns.
  So the pane columns are back to the shipped `HStack` of two `VStack`s, each as tall as its own cards;
  `SettingsCardStack` and `SettingsColumnPair` are gone. **B8 stays open** as its own unit, to be done
  with a per-row `Grid` (the owner's own first clause: "en una fila ambas card tengan la misma altura"),
  which equalises rows natively without measuring anything — and with the render loop as the verifier,
  which is the lesson here: a cosmetic layout change in this project is not verified by a pure test, it
  is verified by looking at the pane.
  What replaces the tests that went with the reverted types: `SettingsPaneLayoutTests` renders EVERY
  pane at two widths and fails on any view laid out in unbounded space, plus a case pinning that a pane
  sizes to its cards instead of to the viewport it is scrolled in — the exact shape of both regressions.
  **Evidence**: whole suite 1026 started / 1024 passed / 0 failed; renders inspected for overlay (light),
  capture (dark), whiteboard (dark); installed 22:14.

- **L25** (B8, solved — and this time looked at): the columns are ROWS now. `SettingsColumns` takes
  the two columns as card LISTS and lays them out as a `Grid` with one `GridRow` per card of the longer
  column, each row holding one card from each side (a clear filler when a side is out of cards). A row
  is as tall as its taller card and both cards fill it, so the two cards of a row end on the same line —
  the owner's own first clause. Nothing is measured: the row height is what `Grid` computes for itself,
  which is why this shape does not repeat L24's feedback loop.
  Two things had to be right for it to be visible, and the first render showed only one of them: the
  CELL has to fill the row (`.frame(maxHeight: .infinity)` in the cell) and the CARD has to fill the
  cell — `SettingsCard` was still sizing its background to its own content, so the grid equalised frames
  nobody could see. With the card filling, Overlay's *Laser* now ends on the same line as *Drawing* and
  Pointer Highlight's *Motion* matches *Shape*; both confirmed by looking at
  `/tmp/stare-settings-{overlay,marker,capture,whiteboard}-*.png`.
  **The cost, named**: pairing a short card with a very tall one leaves the short card mostly empty —
  in Capture, *Destination* carries ~190 pt of content and is stretched to ~800 because it shares a row
  with *File name*, whose helper text makes it tall. That is what "both cards in a row the same height"
  means when the pairing is uneven. If the empty expanse reads worse than the ragged bottom, the pane's
  own pairing (which card sits beside which) is the thing to change, not the layout.
  **Evidence**: `SettingsPaneLayoutTests` (bounded space at both widths, pane sizes to its cards, and the
  row plan for 2-vs-1, 2-vs-3, 0-vs-3), whole suite 1026 started / 1024 passed / 0 failed, installed 22:25.

- **L26** (which panes get two columns, decided by looking): the rule now is TWO columns only when the
  pairing is even; a column with a hole, or a short card beside a tall one, goes to one column.
  - **Pointer Highlight keeps two** (2-vs-2: Shape/Stroke beside Motion/Colour). It is the only pane
    whose cards pair naturally, and it is the one the owner approved on sight.
  - **Capture → one column.** *File name* carries a paragraph of helper text: at 376 pt it wrapped to
    ~14 lines and towered over *Destination*, which then stretched to ~800 pt and sat 80 % empty. At the
    single-column width the same paragraph takes three lines and every card is its own height.
  - **Overlay → one column.** Drawing and Displays against a lone Laser is a 2-vs-1 shape: a hole in the
    second row and Laser stretched for nothing.
  - **Whiteboard → one column.** Same 2-vs-1 shape (Background+Pages against Board).
  Judged on the rendered panes (`/tmp/stare-settings-{capture,overlay,whiteboard,marker}-*`), not on
  reasoning about them: the three single-column panes show no empty card and no hole, and the capture
  pane's tall card shrank by two thirds.
  **Evidence**: whole suite 1026 started / 1024 passed / 0 failed; installed 22:40.

## Delivery (branch `feat/board-and-settings-polish`)

Three work-unit commits, and the slice sizes are recorded because two of them ran
past the ~400-line review guidance:

- `960966d` **fix(board)**: the pasted image's orientation, fit, select-tool move
  and Shift resize, and Escape clearing the layer (Sources + 2 test files; 375
  insertions, 51 deletions).
- `feat(history)`: the thumbnail preference and the outside-click dismissal
  (7 files; 277 insertions).
- `feat(settings)`: the window floor, the on-disk history pane, the row grid for
  two-column panes and the sidebar row (8 files; 531 insertions, 137 deletions —
  **past the slice guidance**: it is one coherent shell change but it would have
  been two commits if split as window/sidebar and panes/history-pane).

Push, PR and merge stay the owner's decision; the branch is based on a local
`main` that is 96 commits ahead of `origin/main`, which is pre-existing and not
part of this work.
