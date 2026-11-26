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
| T1 | S1, S9 | Blur and spotlight answer the crosshair; the area-mode cursor stops leaking | worker | |
| T2 | S2 | Right-click a history capture for its actions | worker | |
| T3 | S6, S7 | The About card's symbol, and command-comma from any mode | worker | |
| T4 | S3, S4, S5 | The editor's select and blur tools, and the spotlight's cell | worker | |
| T5 | S8 | A capture includes Stare's own windows | worker | |

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
