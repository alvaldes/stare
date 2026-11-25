# D3: an area capture shows its loupe and its guides

The owner's item from the 2026-11-25 backlog list, with his own reference image of
a crosshair, a magnified patch and dotted rules spanning the screen.

## Specs

- **S1** (verbatim): "al hacer screenshot de un area quiero que saga la lupa y las
  guias estas (dots lines)". While an area selection is being drawn, the pointer
  carries a magnified view of what is under it, and dotted guides mark the
  selection's edges out to the screen's edges so the eye can follow a line to the
  edge before committing.

- **S2** (verbatim): "Esto es algo que sepuede configurar si se quiere o no pero por
  defecto esta activado." Both are preferences, and both start ON: a user who
  dislikes them turns them off; nobody has to discover them to get the good
  default.

- **S3** The rule the repo already lives by, applied here: whatever the guides and
  the loupe draw must come from the same geometry the selection commits, so the
  lines can never promise an edge the capture does not take.

## Tasks

| ID | Specs | Task | Route | Commit |
| --- | --- | --- | --- | --- |
| T1 | S1-S3 | The loupe and the guides, drawn from the selection's own geometry | worker | d13d7ec |
| T2 | S2 | Two preferences, on by default, wired to the drawing | worker | d13d7ec |
| T3 | S1-S2 | Docs: README, CHANGELOG and this log | worker | |

## Log

- **L1** (owner, 2026-11-25, verbatim): "- al hacer screenshot de un area quiero que
  saga la lupa y las guias estas (dots lines) [Image#3]. Esto es algo que sepuede
  configurar si se quiere o no pero por defecto esta activado." The image shows a
  crosshair at the pointer, a circular magnified patch beside it, and dotted rules
  running from the pointer to the screen edges.
- **L2** (exploration, before any edit): the half of S1 that already ships, and the half that does not.
  The **loupe is built and live**: `Sources/StareCore/AreaCaptureLoupe.swift` is a pure planning enum (side
  120, magnification 4, pointer gap 24, flips per axis, clamps to the display), and `OverlayView.drawAreaLoupe`
  (`OverlayView.swift:1319-1371`) draws it during the drag, gated on `isSelectingArea` + `areaLoupePoint` +
  `frozenAreaBase`. `TextSelectionWindow` reuses the same plan for the ⌘-text surface, so the geometry has two
  consumers already. **The guides do not exist at all**: nothing in `Sources/` draws a rule from the selection's
  edges to the display's edges — the only dashes in the app are mark-selection chrome, the whiteboard's page
  chrome, and the pointer highlight's band. So this task is the guides, plus the two preferences the owner
  asked for, plus an honest check of why he asked for a loupe that is already there.
  Two constraints worth naming before any code: the drag's rect is already the crop rect (`selectionRect` at
  mouse-up is what `deliver` crops with), so the guides must read THAT property and nothing else (S3), and the
  only correct painting surface is `OverlayView.draw(_:)` — chrome must never become a stroke or grow
  `committedBounds`. Preferences follow the append-only discipline: new fields appended last in `CodingKeys`,
  decoded with `try? … ?? default`, encoded explicitly, and no `currentVersion` bump without a real migration.
- **L3** (S1-S2, worker): the GUIDES now exist and BOTH pieces of chrome are configurable.
  **What was drawn** — `Sources/StareCore/AreaCaptureGuides.swift` is a pure plan type modelled on the loupe's
  plan/paint split: `guides(for:bounds:)` takes exactly the overlay's `selectionRect` and its display's `bounds`
  and answers the rules as zero-width/zero-height segments (`Guide.line`, with `dotLength` 1, `gapLength` 3,
  `lineWidth` 1). `OverlayView.drawAreaGuides` paints them dotted (dim dark rule under a dim white dotted top
  stroke — the loupe ring's dark-under/bright-on-top trick), in `draw(_:)` inside the area-selection branches,
  after the shroud, never a `Stroke`, never in `committedBounds`.
  **The three decisions** — (1) which edges: each of the selection's FOUR edges extends both ways, out to this
  display's edges — eight rules in the open, fewer near the perimeter; (2) before a rect exists the guides do
  NOT follow the pointer — a pointer without a selection edge has nothing to extend, and a line not tied to
  `selectionRect` could claim geometry the capture does not honour (S3); `nil` and the empty mouse-down rect
  both draw nothing; (3) the clipping is the rect intersected with `bounds` (the same clamp area capture
  already relies on; each `OverlayView`'s bounds ARE its display's edges), plus dropping any edge coincident
  with a display edge — a rule there could only imply a farther edge that does not exist.
  **The loupe's answer** — the loupe DOES reach the owner today: it paints in every `⇧S` drag on a real display
  canvas as long as Screen Recording is granted (which his captures imply his is): the gate is
  `isSelectingArea` + `areaLoupePoint` + `frozenAreaBase` (`OverlayView.drawAreaLoupe`), and the frozen base is
  either stocked when the canvas is built (`OverlayController`'s wiring → `captureAreaFreezeFrame`) or captured
  for the drag itself — both require `captureDisplay`, which fails without Screen Recording, and then the drag
  stays honest and runs live with no loupe. So the users who never see it are exactly the ones without the
  permission (nothing truthful to magnify) and whiteboard drags (deliberate scope rule). The most likely
  reason he asked is simply that his build predates the loupe.
  **Preferences** — `showAreaLoupe` and `showAreaGuides` appended to `CapturePreference` AFTER
  `backdropShadow`, encoded explicitly, decoded `try? … ?? true`, `currentVersion` stays 2, both default ON;
  exposed to the overlay through `EditorState.showAreaLoupe`/`.showAreaGuides` mirrors (the `pointerStyle`
  pattern; detached state keeps ON in memory); a new "Area drag" card with the two toggles sits second in the
  capture pane's list; no `TextField` was added (the pane's disabled-state test still counts exactly its 2
  text fields beyond prefix and template). Turning one off removes exactly that piece of chrome and leaves the
  other painting — proved in pixels both ways.
  **Verification numbers** — bitmap assertions on the real view (`NSBitmapImageRep.colorAt`, real `NSEvent`s,
  primary-screen-confined window): a dot ON the right-edge rule at (400, 450) reads (0.65, 0.78, 0.67) over the
  frozen green scene and its α 0.32 shroud (scene alone there: (0.07, 0.61, 0.14)); a dot on the top-edge rule
  at (650, 100) likewise; with the selection flush against the display's left edge NO rule paints along that
  edge (full-column scan clean); the loupe's ring and crosshair read near-white at (544, 335) and (544, 394)
  during a drag over a magenta frozen frame; turning either preference off clears exactly its pixels and
  leaves the other. Pure: AreaCaptureGuideTests pass (eight exact rules for an open rect, whole-display →
  none, nil/empty → none, flush-edge and overhanging-rect clipping, off-origin display). Decoding: a stored
  blob written before both fields existed decodes BOTH ON with the rest intact; garbage values fall back to
  ON; the version stamp stays 2. Suites: AreaCaptureGuideTests 9, CapturePreferenceTests 33 (28 pre-existing,
  all still green), AreaCaptureGuidesViewTests 4, AreaCaptureLoupeViewTests 10; full-suite counts recorded at
  delivery.
