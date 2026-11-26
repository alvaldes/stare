# C1 + C2: the editor's crop frame and the spotlight's shapes

Two backlog items about how the editor's chrome reads.

## Specs

- **S1** (verbatim, C1): "para el crop del editro puedes usar este marco
  (https://cleanshot.com/_ipx/f_avif&q_70&s_760x760/img/home/annotate/crop.png) en vez
  del azul dots que tiene ahora, mira este video para que veas como debe funcionar
  https://cleanshot.com/video/screenshots/crop.mp4".

- **S2** (verbatim, C2): "el spotlight hoy es ciruclar/ovalado pero no tiene porque
  serlo puedes hacer que tenga otras formas (como aqui
  https://cleanshot.com/_ipx/f_avif&q_70&s_760x760/img/home/annotate/spotlight.png) sin
  crear mas tools?" — answered: yes, one tool, several shapes.

- **S3** No new tools. The spotlight keeps its one button and picks its shape from a
  control; the crop keeps its one mode and changes only how its frame is drawn and
  how it is grabbed.

## Decisions taken here (the reference could not be studied)

- **C1**: the blue dotted treatment becomes a frame of corner brackets and four edge
  handles in the accent colour, with the region dimmed outside it. Dragging inside
  moves the crop, dragging an edge or a corner resizes it, and Shift keeps the
  aspect ratio. That is the well-understood idiom the reference is an instance of;
  no CleanShot-specific behaviour is invented.
- **C2**: three shapes — rectangle, ellipse and a rounded rectangle — cycled with a
  control on the spotlight's own button (a modifier click or the arrow keys, pinned
  by a test), never a second tool.

## Tasks

| ID | Specs | Task | Route | Commit |
| --- | --- | --- | --- | --- |
| T1 | S1, S3 | The crop frame and its grab rules | worker | 3d811b6 |
| T2 | S2, S3, S4 | The spotlight's two shapes without a second tool | worker | uncommitted |
| T3 | S1-S3 | Docs: CHANGELOG and this log | worker | |

## Log

- **L1** (owner, 2026-11-25, verbatim, two entries of one backlog list): the two
  quotes above.
- **L2** (decision): neither reference could be fetched — the image endpoints serve
  AVIF that this harness does not decode and the video endpoints only yield frames
  for YouTube and local files — so both designs are specified from the owner's words
  plus the idioms the app already uses. The owner can hand the references over as
  local files later; these implementations are then measured against them rather
  than guessed at.

- **L3** (S1-S3, 2026-11-25). _The crop frame._ `drawCropOverlay` draws, in
  view space, four corner brackets (two 18 pt arms per corner) and four
  16 pt handles centred on the edge midpoints, stroked 2.5 pt with round caps
  in the app's selection accent (0.25, 0.55, 1 — the same blue the overlay's
  chrome draws), over the shipped 0.35 shroud; no segment runs along an edge
  between bracket and handle, and the old white border and grip squares are
  gone. The geometry is the pure `CropFrame` beside `EditorCropRule`. The
  grab rules are unchanged (already the reference idiom: `EditorCropRule.handle`
  grabs corners then edges, the interior moves, `region(from:dragging:in:)` /
  `region(from:movedBy:in:)` resize and move), and one new rule joined them:
  **Shift on a crop-adjusting drag** holds the START rectangle's aspect ratio
  through `EditorCropRule.lockedRegion` — the exact rule the canvas layers
  already resized with — without touching the staged-crop contract (Return
  confirms, Esc and a tool pick cancel, exactly one journal step;
  `CaptureStagedCropTests` still pins it). _The spotlight's shapes._
  `SpotlightShape` (rectangle → ellipse → rounded rectangle, `next` cycles
  exactly that order) is a property of the mark, appended last after
  `redactionStyle` on both `Stroke` and `PersistedStroke`: explicit encode,
  lenient decode to the current default (`.ellipse`), unknown raw values fall
  back — a legacy document, which never named the field, renders byte for
  byte as it always did, pinned by raster equality. `DrawingSession.begin`
  takes the armed shape and stamps it only on spotlight marks;
  `EditorState.spotlightShape` rides the `arrowHeadStyle` disposition (armed,
  never persisted, detached surfaces keep the ellipse) and both minting sites
  (the drawing overlay's `mouseDown` and the capture editor's) stamp it. The
  control is **⌥-click on the spotlight's own button** — the owner-approved
  route — carried by `SpotlightToolButtonView` (an AppKit-backed press surface
  hosting the unchanged SwiftUI cell, because the modifier at the click
  decides), shared by the drawing bar and the editor chrome, and the plain
  click stays a plain tool pick. In render, the ellipse keeps T8b's
  byte-exact preview and the radial-gradient dim untouched; the rectangle and
  the rounded rectangle (16 pt corner radius, clamped into the region's half
  sides, `PathBuilder.spotlightPath` / `roundedRectanglePath`) cut the same
  dim weight (0.55, source-over black) along their own silhouette — no
  feather band on the flat shapes; dimming and blending of the shipped look
  never changed. _Verification._ Focused: `swift test --filter "Spotlight"`
  EXIT=0 (36 tests), `--filter "CaptureCrop"` EXIT=0 (36 tests incl. the new
  crop-frame ones). Full suite unpiped `swift test > .build/w19.log 2>&1;
  echo EXIT=$?` → EXIT=0: StareTests 412 (+8), StareCoreTests 916 (+12),
  0 failures (baseline 404 + 904). Crop frame judged in pixels over the real
  editor window (`CaptureCropFrameTests`): accent present at the four corners
  and four edge midpoints, no accent at the inter-gap probes (100,110 and
  190,110), no white grips at any of the eight anchors, inside brighter than
  the dimmed outside on the same flat picture (0.50 vs ≈0.37), plus the three
  behavioural drags (edge resize → 30×60, interior move → exact
  content, Shift drag → 36×36 from a 30×30 start, each Return-cut region equal
  byte for byte to `CGImage.cropping(to:)` of the same rect). Spotlight shape
  render evidence (sampled row/column, 2 px/pt sampling): interior clear and
  far corner at the 0.45 weight for all three shapes; the row probe left of
  the region reads 0.45 for the two flat shapes and the ellipse's eased ramp
  keeps ≈0.94; the corner probe reads 1.00 (rectangle), 0.45 (rounded's dish
  edge) and ≈0.94 (ellipse) at the same point; inside/outside the rounded dish
  is 1.00 / 0.45. Chose not to do: no CHANGELOG (T3's job), no persistence or
  Settings knob (S3), no extra tool, no toolbar pixel-pin for the marked
  spotlight cell (the SwiftUI cell is unchanged and `ToolbarGripperTests`
  already pins the bar's render path).

- **L4** (S4, 2026-11-25). The owner rejected the ⌥-click control and cut the offer
  to two shapes (_"opt+click no es una buena forma de hacer y me interesa solo el
  elimpse y el redondeado"_), keeping everything else. **The control.** A
  **context menu on the spotlight's own button** — right-click over the non-key
  bar opens it: a modifier click was a hidden gesture, and a context menu is the
  standard mechanism for a button on a bar that cannot become key (a popover
  needs key status; a context menu does not). The menu is `SpotlightToolButtonView.menu(for:)`,
  built fresh each time the user opens it: its two items are `SpotlightShape.menuChoices`
  — application-ordered: **ellipse, rounded rectangle** — titled with the shape,
  the armed one check-marked (`.on`), and picking an item arms the shape through
  `EditorState.spotlightShape` exactly as before; the plain click stays a plain
  tool pick, and the shape operates identically on the capture editor's chrome.
  The tooltip and the accessibility label now read "right-click changes the
  shape: <armed>" — still naming the armed shape, S4's requirement. `SpotlightShape.next`
  (the ⌥-click cycle it fed) is gone, and the three-shape cycle pin of L3 is
  re-derived by the two-shape menu pins. **The withdrawn shape.** `SpotlightShape.rectangle`
  is out of `menuChoices` but stays an enum case, raw value `"rectangle"` and a
  `CaseIterable` member: a mark drawn in the last build keeps decoding and
  rendering exactly the rectangle it was drawn as — nothing anyone drew is
  thrown away, only the offer is withdrawn. Everything else is byte-for-byte
  the L3 story: the ellipse's T8b pins and the legacy-mark raster pin all pass
  untouched; the rounded rectangle keeps its clamp-rounded corners;
  append-last, leniently-decoded persistence unchanged; the minting sites and
  the drawing overlay unchanged. **Verification.** RED: `swift test --filter
  "SpotlightShapeTests"` EXIT=1 (missing `menuChoices`). Focused:
  `swift test --filter "Spotlight"` EXIT=0 — 50 tests (37 StareCoreTests, 13
  StareTests) — inc. the new `testTheControlOffersExactlyTheTwoShapesTheOwnerWants`,
  `testTheSpotlightButtonSContextMenuOffersExactlyTheTwoShapesWithTheArmedOneChecked`,
  `testPickingAShapeFromTheMenuArmsTheNextMarkWithIt` (menu pick → armed state →
  minted mark carries the shape), `testTheEditorChromeSMenuMatchesTheDrawingBarS`,
  and `testAMarkPersistedWithThePlainRectangleStillDecodesAndRenders` (round-trip
  decode plus raster equality). Full suite unpiped `swift test > .build/w23.log
  2>&1; echo EXIT=$?` → EXIT=0: StareCoreTests 919 (+1), StareTests 429 (+1), 0
  failures (baseline 918 + 428). Chose not to do: no CHANGELOG edit (CHANGELOG.md
  still says ⌥-click on line 59 — the parent's call; the file is not on this
  task's edit surface), no Settings knob (S3), no popover (needs key status),
  no hidden modifier gesture anywhere.
