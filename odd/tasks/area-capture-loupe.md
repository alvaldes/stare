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

- **S4** (owner, after using the build; verbatim): "la guia y la lupa debe salir desde que se presiona shift+S no
  al hacer click. y cuando arrastro se quedan 2 guias digamos la que se registro al hacer click y la que esta en
  el puntero pero debe haber solo 1 la del puntero." The guides are the POINTER'S crosshair, not the selection's
  edges: one vertical and one horizontal rule running through the pointer to this display's edges, present from
  the moment area mode arms (no click needed), and during a drag the origin's rules must not be drawn — only the
  pointer's. The loupe appears from that same moment. This supersedes L3's decision that nothing is drawn before
  a rect exists.

## Tasks

| ID | Specs | Task | Route | Commit |
| --- | --- | --- | --- | --- |
| T1 | S1-S3 | The loupe and the guides, drawn from the selection's own geometry | worker | d13d7ec |
| T2 | S2 | Two preferences, on by default, wired to the drawing | worker | d13d7ec |
| T3 | S4 | The guides follow the pointer from ⇧S, and only the pointer's during a drag | worker | uncommitted |
| T4 | S1-S2 | Docs: README, CHANGELOG and this log | worker | |

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
- **L4** (S4, the owner using the build, and a correction of L3): the first version extended the selection's
  four edges, which reads as two rules per axis as soon as the drag starts — the origin's and the pointer's — and
  drew nothing at all before the first click. The owner's model is the reference image's: guides ARE the pointer's
  crosshair, they appear when area mode arms, and during the drag there is exactly one per axis, the pointer's.
  L3's third decision ("no guides before a rect exists") is reversed by this.
- **L5** (S4, worker): the guides are now the POINTER's crosshair, armed-state included — the whole model is
  different, not a patch on L3's.
  **What changed** — `AreaCaptureGuides.guides(at:bounds:)` replaces `guides(for:bounds:)`: given the pointer's
  point and this display's bounds it answers exactly two rules, the vertical and the horizontal through the
  point, each spanning the whole display out to its edges. The four-edge extension is gone, so during a drag
  there is exactly ONE rule per axis, the pointer's — the origin's edges are never read and `selectionRect` is
  no longer an input of the plan (the capture is untouched: the guides never enter `committedBounds`, never
  become a `Stroke`, and paint exactly where L3's paint pass paints — same dotLength 1, gapLength 3, dim dark
  under dim white α 0.8 top stroke). The clipping is the same rule per axis: a pointer outside the display's
  span on an axis draws no rule on that axis, no rule sits exactly on a display edge, empty bounds and a nil
  pointer draw nothing.
  **How the pointer is tracked armed (no click)** — three deliveries into one point:
  (1) `beginAreaSelection` reads the pointer straight off the screen at arm time
  (`NSEvent.mouseLocation` through `window.convertPoint(fromScreen:)` — the sync pattern of the pointer
  highlight, NOT a second `NSCursor` path), so the chrome is present before any move at all;
  (2) the canvas now HEARS bare moves: the tracking area gained `.mouseMoved` — the window already opts in
  (`OverlayWindow.acceptsMouseMovedEvents`), and the missing option was why `mouseMoved` (which existed but
  only re-asserted the cursor) never ran; armed moves land the point, as a click's `mouseDown` and every
  `mouseDragged` always did;
  (3) `mouseExited` drops the point while armed, so a pointer on another display draws nothing on this
  canvas; `mouseEntered` places it at once on re-entry, before the first move tick.
  The variable is renamed `areaLoupePoint` → `areaPointerPoint` — the guides read it equally. Preferences are
  untouched: `showAreaGuides` removes exactly the rules, `showAreaLoupe` exactly the loupe (the loupe's
  frozen-frame gate is not moved), and the chrome is still drawn in `draw(_:)` only.
  **Sampled pixels (before, L3's committed build d13d7ec)** — the origin's rules exists ON SCREEN during a
  drag: L3's own bitmap proved it — its right-edge rule at (400, 450) read (0.65, 0.78, 0.67) over the green
  scene and α 0.32 shroud, and the model also ruled x = 100 and y = 100 (the drag's origin) along the same
  shared paint pass, so origin samples like (100, 450) and (650, 100) carried the same ~0.65 chrome min channel
  there; and armed with no click, every rule sample was bare (L3 drew nothing before mousing down) — L4
  records the owner's rejection of exactly this.
  **Sampled pixels (after, this change)** — same real-view bitmap probes (`NSBitmapImageRep.colorAt`, real
  `NSEvent`s, primary-screen-confined window, green frozen frame 1800×1200):
  armed with a bare `mouseMoved` to (400, 200), no click: chrome at (400, 450) on the pointer's vertical rule,
  at (700, 200) on its horizontal, and the loupe's ring paints at (484, 224) (frame (424, 224, 120, 120)) —
  chrome from ⇧S alone, the owner's first half answered.
  mid-drag (100, 100)→(400, 300): the pointer's rule samples (400, 450) and (650, 300) read max-min-channel
  0.655 (the same composited chrome L3 measured), while the ORIGIN's samples (100, 450) and (650, 100) read
  0.0706 — the bare green scene under the shroud's red component, no rule: only the pointer's crosshair
  (measured with an in-test probe print since removed; the suite persists the assertion as
  `hasChromeDot` at the pointer's rules and `!hasChromeDot` at the origin's).
  a pointer parked on a display edge (0, 200) draws no rule along the edge (column scan x = 1 clean outside
  the horizontal rule's own neighbourhood) and keeps the perpendicular rule; a pointer leaving the display
  (`mouseExited`) draws nothing anywhere and a pointer on it draws everything.
  **Verification numbers** — AreaCaptureGuideTests 7 (eight-and-clipping cases replaced by the crosshair's
  two-rules, nil/empty-display, outside-both-axes, edge-drop-per-axis, off-origin, orientation, constants),
  AreaCaptureGuidesViewTests 6 (armed-no-click, drag-only-pointer-rules, edge-clamp, pointer-left, guides-off
  removes-only-guides, detached defaults), AreaCaptureLoupeViewTests 10 all still green (the remembered
  rectangle's render pins its own pointer via `mouseMoved` so the armed seed cannot flick the sampled
  pixels). RED was observed for real: with the plan typed to `at:bounds:` the old suite failed to compile
  (`incorrect argument label … expected 'at:bounds:'`, AreaCaptureGuideTests.swift:23) before the new tests
  were written. Full suite, final state: `swift test > .build/w15.log 2>&1` EXIT=0 — StareTests 387, 0
  failures; StareCoreTests 902, 0 failures (baseline was 904 + 385: the pure guide file went 9 → 7, the view
  guide file 4 → 6; net −0 across both).
- **L6** (S5, owner using the build, verbatim in S5): the chrome goes greyer, the dots go airier and
  smaller, and the armed pointer is ALWAYS the crosshair. Three changes, all pinned:
  **1. Greyer** — the LIGHT stroke of both painters drops from near-white to a mid grey; the dark
  under-strokes are untouched. Guides' top stroke: `CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.8)` →
  `CGColor(gray: 0.75, alpha: 0.9)` (the alpha goes UP so the darker grey keeps its read — the sampled
  grey dot over the dark green scene reads 0.478–0.506 at 1×; L5's white read 0.655 over the same scene,
  so the sampled pixel IS the requested step greyer). Loupe's ring+crosshair top stroke:
  `CGColor(gray: 1, alpha: 0.95)` → `CGColor(gray: 0.75, alpha: 0.95)` (straight ring rows read
  ≈ 0.757–0.780; the crosshair's half-covered rows ≈ 0.49–0.54). Read thresholds re-derived with the S5
  canary: the guides' `hasChromeDot` 0.45 → 0.40, the loupe's `hasRingPixel` 0.6 → 0.45, and the
  loupe-off test's `hasGuideDot` probe widened to radius 4 (the 6.75 pitch keeps a dot inside any ±4
  window; its best sampled row ≈ 0.48 over content-free canvas) — the greys no longer reach the old
  white-height thresholds; contents and scenes still separate cleanly (dark scene ≤ 0.16, grey dot
  ≥ 0.478; light band 0.82, grey dips 0.62–0.77).
  **2. Airier, smaller dots** — the constants in `AreaCaptureGuides`: `dotLength` 1 → 0.75,
  `gapLength` 3 → 6 (the pitch, dot + gap, grows 4 → 6.75) and `lineWidth` 1 → 0.75 — with the round
  cap, that width IS a dot's rendered diameter, so L5's 1.6-pt dot drops to 1.35. The rendered run
  pattern is asserted off the screen, not off the constants: a 1× bitmap probe along the pointer's
  vertical rule finds 24 dots of ≤ 3-row runs at pitch 6.75 (measured centres 432, 438.5, 445.5, 452 …)
  with under half the band bright, over the dark scene each dot's peak 0.478–0.506, and over the light
  (white) band the same dots read as dips to 0.62–0.73 under the 0.82 bare band.
  **3. Always the crosshair while armed** — the single cursor decision is now
  `OverlayView.answeredCursor()`: while `isSelectingArea` the system crosshair answers FOR EVERY tool,
  outside it the same path answers what it always answered (`gestureCursor ?? cursorForTool`).
  `reassertCursor()` draws from that one decision, so there is no second ambient `NSCursor.set()`: arming
  (`beginAreaSelection`) re-asserts, and EVERY disarm restores through the same path — the capture's
  `mouseUp`, `cancelAreaSelection` (Esc) and `confirmPreloadedArea` (Return) each re-assert, so the
  tool's own cursor (drawn glyph or system) is back the moment area mode leaves. Switching tools while
  armed re-asserts too, so the key presses cannot flash a tool cursor back. Asserted for every
  `Tool.allCase` by identity (`=== NSCursor.crosshair` armed, `=== OverlayView.cursor(for: tool.cursor)`
  outside) plus the Esc and drag routes back (a drawn-glyph tool, the pen, is the sharp witness).
  Discipline preserved: computed from the pointer alone, clipped per axis, nothing on a display edge,
  both preferences still remove exactly their own chrome, never a `Stroke`, never in `committedBounds`.
  **Verification** — RED: the first focused run failed to compile (`no member 'answeredCursor'` ×8);
  the intermediate 0.72/α 0.8 grey attempt was then RED in pixels (13 failures: the 1× grey dot peaked
  0.44, under the 0.45 thresholds) before the alpha compensated to 0.9. Focused (`swift test --filter
  AreaCapture > .build/w27-focused-green3.log 2>&1`): EXIT=0 — AreaCaptureFreezeTests 17,
  AreaCaptureGuideTests 7, AreaCaptureFrameTests 11, AreaCaptureMemoryTests 6, AreaCaptureLoupeTests 13,
  AreaCaptureGuidesViewTests 10 (was 6: + the run pattern, the grey pair and the two cursor tests),
  AreaCaptureLoupeViewTests 10 (assertions extended in place, threshold re-derived), 0 failures. Full
  full suite unpiped (`swift test > .build/w27-final.log 2>&1`, the final tree after two comment-only
  polish passes re-verified — an identical earlier run lives in `.build/w27.log`): EXIT=0 — StareTests 440
  (baseline 436 + 4),
  StareCoreTests 919 (baseline 919, the constants pin re-derived in place under the S5 canary), 0 failures
  — the board's own cursor discipline (its `gestureCursor` override feeds the same answered path) travels
  in the suite.
