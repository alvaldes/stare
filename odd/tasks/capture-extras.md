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
| T6a | S23 | Audit blur as redaction: measure what survives a blur mark, and whether the original is reconstructible | worker | |
| T6b | S13 | Pixelate as the second redaction option next to blur (contingent on T6a) | worker | |
| T9 | S16 | Editor zoom and pan, tool keys unchanged | worker | |
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
