# Backlog

Known work that is not being done right now. One entry per item: what the user
sees, why it happens, and where it lives. Add at the top; newest first.

All entries below arrived together on 2026-11-25 as the owner's own list
(verbatim quotes kept). Index by cost, cheapest first — the order is a reading
aid, not a commitment:

1. Menu bar icon is small (A1) — one number.
2. Settings icon renders without colour (A2) — needs a diagnosis first.
3. The tool cursors (A3) — one coherent unit, five shapes.
4. The filename template's default and its live preview (A4) — the only item
   that contradicts what the app promises today.
5. Area capture: the loupe and the guides (D3) — exists, needs a preference.
6. Capture editor: same environment as outside (B1) — the biggest coherence win.
7. Background tools belong in the editor (B4).
8. The capture history as a bottom panel (B3).
9. Pixelated redaction (B2) — reference material to study first.
10. The crop frame (C1) — same.
11. Spotlight shapes (C2) — a design constraint, not just code.
12. Cards like CleanShot's quick access (C3) — the largest single piece.
13. `Update monthly` (A5) — the owner's words do not say what it is.

---

## A5. "update monthly option" — needs the owner to say what it is

- **The ask, verbatim**: "update monthly option".
- **Why it is not an entry yet**: nothing in the app mentions a monthly option.
  It could be an update check, a paid plan, a reminder, or a typo for something
  already planned in `odd/tasks/release-0.3.0.md`. Recording a guess here would
  be worse than asking.
- **Needs**: one line from the owner, then it becomes an entry like the rest.

## A4. The filename template's default does not do what its example promises, and the field has no preview

- **What the user sees**: the Settings capture pane offers a name template whose
  example reads `Stare-2026-11-21-at-14-05-33.png`, but a default that does not
  produce that shape. "configura settings/capture para que por defecto el name
  tempate haga lo que dice el ejemplo: Stare-2026-11-21-at-14-05-33.png". Then:
  "y despues hay que hacer que lo que se ponga en el name template tenga un
  preview en tiempo real".
- **Why**: the example and the default are stored separately and drifted. A
  template is also opaque by nature — the user types tokens and only learns what
  they produce when a file lands on disk, which is exactly the feedback loop a
  preview closes.
- **Where**: `Tests/StareCoreTests/CaptureFileNameTemplateTests.swift` and
  `CaptureFileNamePreservePinTests.swift` name the type; the field itself is in
  the Settings capture pane (`Sources/Stare/SettingsView.swift`). To be located
  precisely before changing.
- **Watch out**: the preview must render the SAME thing the save path writes, or
  it becomes a second implementation of the naming and drifts again. The
  redaction batch already learned this ("one dispatch" was intent, not code).
- **Reported**: 2026-11-25.

## A3. The tool cursors change under the pointer, and not every tool gets its own

- **What the user sees, verbatim**: "los cursores personalizados de los tools
  camian y no todos son diferentes. por defecto es la cruz excepto los que
  tienen el propio como 'v','f','t'." Then the shapes, one per line:
  - "el cursor de pen debe ser un dot o algo asi"
  - "el cursor de highligh debe ser el cursor bloque fill"
  - "el erase un circulo sin relleno solo borde"
  - "el count debe ser un circulo dentro de otro circulo"
- **Why**: the cursor is chosen by a path that is not one switch per tool, so
  some tools fall back to the crosshair and some inherit a shape that belongs to
  a neighbour. A drawing app's cursor is the tool's loudest signal and it is
  currently unreliable.
- **Where**: the tool cursor mapping in the app layer (to locate: `Sources/Stare`
  around `OverlayView`/`EditorState`); the card's cursor already has its own
  arbitration (`CardCursor`), which is a worked example of the same problem.
- **Direction**: one table, one entry per tool, no fallbacks except an explicit
  "this tool uses the crosshair". Then the five shapes above.
- **Reported**: 2026-11-25.

## A2. The app icon in Settings has no colour

- **The ask, verbatim**: "el icono en settings no tiene colores porque?"
- **Why it might**: an app mark drawn as a template image (tinted monochrome by
  AppKit) or a symbol instead of the bundle icon. Diagnosis first, then a fix.
- **Where**: `Sources/Stare/SettingsComponents.swift` (`AppMark`) and the pane
  headers that use it.
- **Reported**: 2026-11-25.

## A1. The menu bar icon reads smaller than its neighbours

- **The ask, verbatim**: "el tamanno del icono en el menu de la mac se puede
  hacer mas grande es que comparado con los otros se ve pequenno".
- **Why**: the glyph is drawn from a path at a fixed size rather than sized to
  the menu bar's own metric, so it sits short next to system items.
- **Where**: `Sources/Stare/StatusBarController.swift` (the comment at the top of
  the file says the glyph is drawn from a path there).
- **Reported**: 2026-11-25.

## B4. Every capture-background control belongs in the editor

- **What the user sees**: the background (padding, colour, gradient, shadow,
  ratio) is configured in Settings today, away from the image it decorates.
  "todo lo del backgound del capture debe estar en el editor
  (https://cleanshot.com/video/screenshots/bgtool.mp4) en settings solo si quiere
  que se tome por defecto con o sin."
- **Why**: Settings describes a default; the choice is per capture and belongs
  where the capture is. The reference keeps one toggle in Settings ("by default
  with or without") and the rest in the editor.
- **Where**: `Sources/StareCore/CaptureBackdrop.swift`, the Settings capture pane,
  and the capture editor's own toolbar (`Sources/Stare/CaptureEditor.swift`).
- **Watch out**: this depends on B1 — moving controls into the editor's bar only
  makes sense once the editor has the real bar.
- **Reported**: 2026-11-25.

## B3. The capture history should be a bottom panel, screen-wide

- **What the user sees**: the history opens as a pane/panel of its own shape
  instead of sliding up from the bottom edge at a fixed height, the way the
  reference does: "el historial debe verse como un panel del ancho de la pantalle
  que sale desde abajo y ocupa una altura fija como aqui
  https://cleanshot.com/_ipx/f_avif&q_70&s_1360x960/img/screenshots/history.png".
- **Why**: a fixed-height, full-width sheet is predictable and never covers the
  thing being captured; a free-floating panel has to be placed and reasoned about
  every time.
- **Where**: `Sources/Stare/CaptureHistoryPanel.swift`,
  `Sources/StareCore/CaptureHistory.swift` for the store.
- **Reported**: 2026-11-25.

## B2. Redaction should read as pixelation, not as blur

- **What the user sees**: the blur tool produces a soft blur where the reference
  produces a hard pixel lattice: "puedes hacer que el blur se vea estilo
  pixelado asi
  https://cleanshot.com/_ipx/f_avif&q_70&s_760x760/img/home/annotate/redact.png
  mira tambien este video
  https://cleanshot.com/video/screenshots/redact.mp4".
- **Why**: a blur is reversible in principle (a deconvolution can recover shape)
  and reads as "unfinished" next to the reference; pixelation is the
  expected idiom for hiding content.
- **Where**: `Sources/StareCore/MarkRenderer.swift` and `PixelateEffect.swift`
  (the repo already has a pixelate path — see `RedactionDispatchTests` — so this
  may be a matter of which one the blur tool reaches, and of the lattice's
  alignment).
- **Watch out**: the blur audit recorded that a 15 pt radius holds against
  deconvolution; swapping the tool must not weaken that guarantee.
- **Reported**: 2026-11-25.

## B1. The capture editor should look and behave like the app it lives in

- **What the user sees, verbatim**: "el entorno del edit capture debe ser el
  mismo que el de afuera: misma barra configrada, orientacion, no fija arriba y
  horizontal".
- **Why**: the capture editor carries its own toolbar, pinned horizontally at the
  top, ignoring the orientation and layout the user configured. Two bars in one
  app is a coherence bug, and the editor is where most of the drawing happens.
- **Where**: `Sources/Stare/CaptureEditor.swift` and the capture editor's
  toolbar construction in `Sources/Stare/OverlayController.swift`; the outside
  bar is `ToolbarPanel`/`ToolbarView` and already honours
  `toolbarOrientation`/`toolbarBorder`.
- **Watch out**: the editor's bar needs the capture-only tools (crop, page, the
  capture actions) that the outside bar does not have, so "same bar" means the
  same geometry, materials and placement rules — not necessarily the same item
  list. That boundary is the design decision.
- **Reported**: 2026-11-25. **Blocks**: B4, C1 and C2 read badly until this is
  done.

## C3. The capture card should behave like CleanShot's quick access

- **What the user sees**: the post-capture card is a card; the reference behaves
  like a small command surface with its own gestures, drag-out and actions:
  "puedes hacer que las cards funcionen como en este video
  https://cleanshot.com/video/home/quickaccess.mp4".
- **Why**: the card is the busiest moment in the product — the user has just
  captured something and is choosing where it goes.
- **Where**: `Sources/Stare/CaptureCard.swift`, `Tests/StareTests/CaptureCardTests.swift`,
  and the card's placement/dismiss rules in `OverlayController.swift`.
- **Watch out**: the card already carries a pin, a dismiss rule and a
  cursor-ownership arbitration; this is the largest single piece in the list and
  needs the video studied before a spec exists.
- **Reported**: 2026-11-25.

## C2. Spotlight should not be limited to a circle or an oval

- **The ask, verbatim**: "el spotlight hoy es ciruclar/ovalado pero no tiene
  porque serlo puedes hacer que tenga otras formas (como aqui
  https://cleanshot.com/_ipx/f_avif&q_70&s_760x760/img/home/annotate/spotlight.png)
  sin crear mas tools?"
- **Answer to the question**: yes, without new tools — the same spotlight tool
  can pick its shape from a control (a modifier key, or the arrow buttons), the
  way the rectangle tool already varies between plain, rounded and ellipse.
- **Why**: a circular mask is one shape of a family; the tool's job is "dim
  everything but this".
- **Where**: `Sources/StareCore/Tool.swift` (the spotlight case) and the spotlight
  rendering in `MarkRenderer.swift`.
- **Needs**: the owner's choice of the shape set and of how the shape is picked.
- **Reported**: 2026-11-25.

## C1. The crop frame should be the reference's, not blue dots

- **What the user sees**: the crop carries a blue dotted treatment; the reference
  draws a frame with handles: "para el crop del editro puedes usar este marco
  (https://cleanshot.com/_ipx/f_avif&q_70&s_760x760/img/home/annotate/crop.png) en
  vez del azul dots que tiene ahora, mira este video para que veas como debe
  funcionar https://cleanshot.com/video/screenshots/crop.mp4".
- **Why**: the frame is the affordance; dots read as a selection fill.
- **Where**: `Sources/StareCore/AreaSelectionGeometry.swift`, `EditorCropRule`
  and the crop drawing in `Sources/Stare/CaptureEditor.swift`.
- **Needs**: the video studied — the reference's crop also changes behaviour
  (aspect presets, rotation), not only paint.
- **Reported**: 2026-11-25.

## D3. An area capture should appear with its loupe and its guides

- **What the user sees**: the reference's area capture shows a magnifier and
  dotted guides at the pointer ([Image#3] in the 2026-11-25 message: a crosshair
  with a magnified patch and dotted rules across the screen).
  "al hacer screenshot de un area quiero que saga la lupa y las guias estas (dots
  lines). Esto es algo que sepuede configurar si se quiere o no pero por defecto
  esta activado."
- **Why**: the guides are the only thing that tells you what the edge will land
  on, and the loupe removes the retry loop on small targets.
- **Where**: `Sources/StareCore/AreaCaptureLoupe.swift`,
  `AreaCaptureFrame.swift`, `AreaSelectionGeometry.swift` and the area overlay
  view; the preference belongs with the other capture preferences.
- **Reported**: 2026-11-25.
