# Capture extras: blur audited, pixelate, editor zoom, filename tokens, backdrop

My half of the capture-parity split with the agent working in `../stare-capture-parity`. The source of
truth for specs and decisions is `odd/tasks/capture-parity.md` on branch `feat/capture-parity`; the spec
lines below are quoted from it verbatim, because that file is not on this branch. Branch
`feat/capture-extras`, off `main` at `2b9c66c`.

## Specs (quoted from `odd/tasks/capture-parity.md`)

- **S13** "Pixelate junto a blur: cuando se oculta contenido sensible se puede elegir pixelado
  aleatorizado además del blur actual. Antes de exponerlo, el blur se audita como herramienta de
  redacción (S23)."
- **S16** "Editor: zoom y pan, para anotar con precisión sobre una captura. No cambia las teclas de las
  herramientas."
- **S17** "Plantillas de nombre de archivo por tokens (fecha, hora, app, display) sobre el destino carpeta
  que ya existe. El prefijo actual sigue funcionando."
- **S18** "Backdrop barato al guardar: padding, esquinas redondeadas y sombra, opcionales. Sin presets, sin
  ratios, sin fondos importados."
- **S21** "Cada cambio de comportamiento con resultado determinístico arranca en RED con un test que falla,
  y termina en GREEN. Lo que dependa de píxeles reales de pantalla se documenta como check manual en la
  fila del commit, y se verifica a mano antes de cerrar la tarea."
- **S22** "Tests y docs van con el código en la misma unidad de trabajo. Toda preferencia nueva o tecla
  nueva se refleja en README (`## Every tool is one key away`, `## Settings`) y en CHANGELOG
  (`## Unreleased`)."
- **S23** "Auditoría de blur, previa a S13: un área cubierta por blur no debe dejar reconstruible el
  contenido original. Si no se sostiene, el pixelado aleatorizado pasa a ser la primitiva de redacción y
  el README se corrige."
- **S4** (from the same document, binding on me) "Settings: toda superficie nueva de preferencias va en
  archivos nuevos; los archivos compartidos (`SettingsView.swift`, `SettingsComponents.swift`) reciben
  sólo la edición mínima de registro."

## Tasks

| ID | Specs | Task | Route | Commit |
| --- | --- | --- | --- | --- |
| T6a | S23 | Audit blur as redaction: measure what survives a blur mark, and whether the original is reconstructible | worker | 8fea337 (record) |
| T6b | S13 | Pixelate as the second redaction option next to blur (contingent on T6a) | worker | |
| T9 | S16 | Editor zoom and pan, tool keys unchanged | worker | 36a6a72 |
| T10 | S17 | Filename templates by token over the folder destination; the current prefix keeps working | worker | |
| T11 | S18 | Optional backdrop on save: padding, rounded corners, shadow | worker | |

**Sequencing.** T6a and T9 start immediately: neither touches the save pipeline. T10 and T11 both write the
saved file, and the peer's T7 (downscale on save) lives in the same file — `Sources/StareCore/CaptureFile.swift`.
That file has one owner at a time: I wait for the peer's T7 commit and rebase onto it before touching it.

**Files.** Mine exclusively: `Sources/StareCore/BlurEffect.swift`, `MarkRenderer.swift`, `CapturePreference.swift`,
`CaptureFile.swift`, `Sources/Stare/CaptureEditor.swift`, plus new files and their tests. Not mine, do not
touch: `OverlayController.swift`, `OverlayView.swift`, `FrontWindowLocator.swift`, `WindowCaptureTarget.swift`,
and the `AreaCapture*`/`AreaSelection*`/`FrontWindow*`/`WindowCaptureGeometry` files in StareCore.

## Log

- **L1** (user, via the peer's relay, confirmed by the human): split the remaining capture-parity work by file
  ownership; I take T6, T9, T10, T11 and the peer takes T3, T4, T5, T7, T8. The human chose T6 and T9 first.
- **L2** (decision, mine as offered to the peer): no new Settings pane. T6's pixelate is a second option on
  the existing blur control, T10 and T11 belong in the existing Capture pane, and T9 needs no preference —
  so the shared five-line registration in `SettingsView.swift` is not touched at all.
- **L3** (rule, the peer's, binding): no test orders a window without the primary-screen helper; verification
  runs one test class per invocation; docs ride with the code; nothing pushed to the peer's branch and no
  merge into `main` without the human saying so.
- **L4** (evidence, T6a): the blur is one `CIGaussianBlur` whose radius is a fixed constant — `BlurEffect.defaultRadius = 15` pt, multiplied by the backing scale, never proportional to the mark and with no user control anywhere. With that radius no cheap attack recovers either fixture: downscale/upscale, unsharp deconvolution, thresholding and deconvolution-plus-threshold all fail, and Vision OCR reads nothing in the blurred region on both the small-text and the 40 pt headline fixtures, while it reads both originals. Pearson correlation against the original is 0.17 for small text and 0.93 for the large plate, and against a low-passed original 0.43 and 0.95: only the presence, position and extent of a redacted block survive, which is inherent to any in-place primitive that respects the mark silhouette.
  **Verdict: S23 holds at the shipped parameters**, so the spec's fallback clause does not trigger — the randomized pixelate is a second *option* (S13), not a replacement, and the README does not need correcting. The structural caveat is the radius-to-glyph ratio: 12 pt was the smallest radius in the sweep that stayed safe against 11 pt text, so anything that later exposes a radius below roughly 10 pt would erode S23 and must be blocked instead of offered.
- **L5** (evidence, T9): the zoom is a pure `EditorViewport` in StareCore — zoom about a point, pan, clamped so
  the capture never leaves the viewport, the fit as the fixed point of every transition — and the editor
  composes it with the existing crop space. The save target stays fit-sized, which is what makes a pen line
  drawn at 3× save byte-identical to the same line drawn at the fit, and a blur drawn at 3× diffuse exactly
  the same rect; both are pinned. 19 tests (8 pure, 11 through the canvas), the four neighbouring editor
  classes still green, tool keys untouched. 36a6a72.
  **Manual checks**: zoom feel on trackpad and wheel, the hand cursors under space-drag, pinch about the
  pointer, and the scroll-pan direction convention — deltas are taken raw, and synthesized events cannot
  confirm the felt direction.
  **Found, not fixed** (pre-existing, outside T9): the editor canvas never routes the eraser to
  `DrawingSession.erase`, so eraser strokes commit as invisible no-ops.
- **L6** (slice note): T6a + T9 are 1104 authored lines over three commits, past the ~400-line slice. T6a is
  a record, T9 is one unit (pure viewport, editor composition, tests, docs). Delivery shape when publishing:
  this branch as one PR per task once the peer's T7 unblocks the save path, never T6b + T10 + T11 together.
