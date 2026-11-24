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

- **B1** "en settings se debe de poder configurar el tamanno de los preview en la grilla del historial"
- **B2** "al historial le falta un comportamiento como maccy que si doy click afuera se cierra"
- **B3** "la imagen del historial si se pega en la pizarra pero no centrada"
- **B4** "la imagen en la pizarra debe de poder ajustarse como mismo se hace con el cursor tool (V) en las demas marcas y si se ajusta el tamano debe de poser mantener la forma si se hace el ajuste con shift presisonado. Esto del shift presionado es para todo lo que hace el tool 'V'"
- **B5** "un detalle es que la imagen se inserta invertida - /Users/alvaldes/Library/Application Support/dev.alvaldes.stare/CaptureHistory/captures/39E94DD1-2481-46FB-A833-543435EB2CD9.png"
- **B6** "el esc en la pizarra no borra la imagen"
- **B7** "settings debe tener un min de ancho y altura al que se puede achicar"
- **B8** "las card en settings que estan en 2 col deben de verse bien y para eso deben tener un estilo donde se trate de que en una fila ambas card tengan ls misma altura o que la combinacion de varias en una col sea la altua de la card de la otra col asi queda simetrico todo."
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
