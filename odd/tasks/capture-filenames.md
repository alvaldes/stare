# Filename templates and the save backdrop

T10 and T11 of the capture-parity split, stacked on the peer's branch because both live in the folder
writer that branch introduced (`Sources/StareCore/CaptureFile.swift`). Branch `feat/capture-filenames`, off
`feat/capture-parity` at `ae2d799` — the peer's T7 commit `9f053b1` plus its record. Specs are quoted from
`odd/tasks/capture-parity.md`, which is present here.

## Specs (quoted from `odd/tasks/capture-parity.md`)

- **S17** "Plantillas de nombre de archivo por tokens (fecha, hora, app, display) sobre el destino carpeta
  que ya existe. El prefijo actual sigue funcionando."
- **S18** "Backdrop barato al guardar: padding, esquinas redondeadas y sombra, opcionales. Sin presets, sin
  ratios, sin fondos importados."
- **S21** "Cada cambio de comportamiento con resultado determinístico arranca en RED con un test que falla, y
  termina en GREEN. Lo que dependa de píxeles reales de pantalla se documenta como check manual en la fila
  del commit, y se verifica a mano antes de cerrar la tarea."
- **S22** "Tests y docs van con el código en la misma unidad de trabajo. Toda preferencia nueva o tecla nueva
  se refleja en README (`## Every tool is one key away`, `## Settings`) y en CHANGELOG (`## Unreleased`)."

## Tasks

| ID | Specs | Task | Route | Commit |
| --- | --- | --- | --- | --- |
| T10 | S17 | Filename templates by token over the folder destination; the current prefix keeps working | worker | 4bc30d1 |
| T11 | S18 | Optional backdrop on save: padding, rounded corners, shadow — padding before any downscale | worker | 2f17ebd |

**Ordering that is not negotiable, from the peer's handoff.** `CaptureFile.write` is the single writer for the
folder path and takes `preference`, `date`, `scale`. A filename template lives inside it; the backdrop has to
pad before scaling so the padding is never resampled. New preference fields are appended at the end of
`CapturePreference` and decoded leniently — never inserted between existing fields. `SettingsView.swift` is
mine on this branch for the Capture pane; if the peer needs a row later they tell me first.

## Log

- **L1** (peer handoff, verbatim surface): "`Sources/StareCore/CaptureFile.swift` (NEW): the folder writer
  moved here from a private enum that lived inside OverlayController.swift. Same API plus a trailing optional
  `scale:` argument, so existing call sites compile unchanged. Your T10/T11 write work belongs in this file
  now". Their T7 commit is `9f053b1`; the branch tip with its record is `ae2d799`, which is this branch's base.
- **L2** (decision, mine): T10 and T11 are stacked on the peer's branch instead of cherry-picking their T7
  into `feat/capture-extras`. A cherry-pick applies (only CHANGELOG and README conflict), but it would put a
  copy of their feature in my branch and confuse both reviews; stacked, the rebase onto `main` is mechanical
  the day their branch lands.
- **L3** (evidence, T10): tokens are `{date}`, `{time}`, `{app}`, `{display}`; fields appended after
  `maxSaveWidth` and decoded leniently; the naming lives in `CaptureFile.write`, which gained trailing
  optional `app:`/`displayName:`; the prefix sanitiser is reused. An unknown token, malformed braces, an
  unsafe literal or an unavailable value all fall back to today's prefix name, so a half-wired template
  cannot emit a broken path, and a substituted value cannot traverse (the separator filters through the
  safe set; the extension is always appended). 17 tests, the PRESERVE pin run before and after the change.
  4bc30d1.
  **Known gap**: `{app}` and `{display}` are refused at the real call site because the one line that
  supplies them lives in `OverlayController.deliver`, the peer's file. Asked them to add it; until then
  those two tokens fall back to the prefix name by design. The Settings preview shows sample values, which
  becomes exactly true once that line lands.
- **L4** (evidence, T11): `CaptureBackdrop` composes at full resolution before `scaled()` — padding, rounded
  corners and a fixed-style shadow, each optional and off by default; the capture itself is blitted 1:1 at an
  integer offset, so the backdrop never resamples the pixels it is wrapping, and the padding is never
  resampled on its own. Clamps: padding 0–128, radius 0–64 and again at compose to at most half the shortest
  side, so a silly preference cannot blank the image; worst-case growth is bounded. 19 tests, with the
  backdrop-off save pinned byte-identical before and after. The shadow's *look* is the manual check: it is
  geometry and interior equality in tests, and CoreGraphics-rendered to the eye in a real save — including
  the JPEG-with-transparent-margin corner case the worker flagged and did not test.
