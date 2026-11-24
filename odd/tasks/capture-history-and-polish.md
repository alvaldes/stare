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
- **L11** (slice note): `797d9cd` carries T2a and T2b together (about 1,300 authored lines) because the pick route, the board's image layer and the controller that owns both share `OverlayController.swift`; splitting them would have left a commit that could not build. Delivery shape when publishing: T3, T5 and T1 are three small PRs of their own, and T2 is one PR of two review passes — the history (store, panel, hotkey) and the board's image layer.
