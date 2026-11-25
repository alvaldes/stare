# Batch A: the small visible polish — two icons, the tool cursors, the filename template

Four independent items the owner listed together on 2026-11-25. They share a
shape: each is small, visible at a glance, and today contradicts something the
app already promises. No shared architecture, so each is its own commit.

## Specs

- **S1** (verbatim): "el tamanno del icono en el menu de la mac se puede hacer mas
  grande es que comparado con los otros se ve pequenno". The status bar glyph
  reads as smaller than the system items beside it and must sit with them.

- **S2** (verbatim): "el icono en settings no tiene colores porque?" The app mark
  in the Settings window shows no colour and must show the app's own icon, in
  colour, the way the Finder does.

- **S3** (verbatim): "los cursores personalizados de los tools camian y no todos
  son diferentes. por defecto es la cruz excepto los que tienen el propio como
  'v','f','t'." Then, one per tool: "el cursor de pen debe ser un dot o algo asi";
  "el cursor de highligh debe ser el cursor bloque fill"; "el erase un circulo
  sin relleno solo borde"; "el count debe ser un circulo dentro de otro circulo".
  Read together: the cursor is chosen per tool by one table with one entry per
  tool, the crosshair is an explicit default rather than a fallback that catches
  whatever the table forgot, and the four named tools draw the four shapes above.

- **S4** (verbatim): "configura settigns/capture para que por defecto el name
  tempate haga lo que dice el ejemplo: Stare-2026-11-21-at-14-05-33.png y despues
  hay que hacer que lo que se ponga en el name template tenga un preview en tiempo
  real." The default template must produce exactly the shape the field's own
  example shows, and the field must preview what the current template will name
  the file, live, as it is typed.

- **S5** (owner, after looking at the build; verbatim): "1. el icono bajale un tilin al tamanno y esta
  inclinado en la direccion contraria al logo original". The menu bar glyph gets a touch smaller, and its
  tilt must agree with the logo's own angle instead of mirroring it.

- **S6** (verbatim): "2. esta a color pero tiene un shadow que no se de donde salio". The Settings mark shows
  the artwork in colour now, with a drop shadow nobody asked for; it must sit flat, like the Finder's icon.

- **S7** (verbatim): "3.a. el cursor del highlight esta horizontal y debe ser veritcal. la elipse, el rect y
  arrow pasan a ser cursor cruz como la linea." and "3.b. no funciona". The highlighter's beam turns vertical;
  ellipse, rectangle and arrow join line on the crosshair instead of keeping drawn glyphs; and the capture
  editor still shows no tool cursor, so the fix there did not reach the real window.

- **S8** (verbatim): "4. no funciona" over a Settings screenshot whose Name template field is EMPTY while the
  preview reads `Stare-2026-11-21-at-14-05-33.png`. The shipped default only reaches a fresh install: a
  preference stored before it keeps `""`, which routes to the prefix. The owner's install is exactly that
  case, so the default is invisible where it matters.

- **S9** (owner, third look at the mark; verbatim): "2. aun se ve algo mejora el recorte en los bordes
  redondeados". Trimming to the artwork's opaque BOUNDING BOX leaves the baked shadow alive in the four
  corners, because a rounded square's box is exactly where the curve exposes what is behind it. The mark
  must be cut to the shape, not to its box, and show no soft pixel at the corners.

## Tasks

| ID | Specs | Task | Route | Commit |
| --- | --- | --- | --- | --- |
| T1 | S1 | The status bar glyph sized with the system's own items | worker | c5bce43 |
| T2 | S2 | The Settings app mark drawn in colour | worker | c5bce43 |
| T3 | S3 | One cursor table, one entry per tool, the four named shapes | worker | 86c3923 |
| T4 | S4 | The default template matches its documented example; the field previews live | worker | b612a8e |
| T5 | S5 | The menu bar glyph a touch smaller, tilted with the logo instead of against it | worker | 8160d8f |
| T6 | S6 | The Settings mark sits flat: no shadow under the artwork | worker | 8160d8f |
| T7 | S7 | Vertical beam, crosshair for ellipse/rectangle/arrow, and the editor's cursor that actually shows | worker | b5bbaf2 |
| T8 | S8 | The template default reaches a preference stored before it | worker | 4a7eb60 |
| T9 | S9 | The mark is cut to its rounded shape, not to its bounding box | worker | fb2f831 |

## Log

- **L1** (owner, 2026-11-25, the batch-A items of a longer list, verbatim; the rest
  of that list is `odd/backlog.md`): "- el tamanno del icono en el menu de la mac
  se puede hacer mas grande es que comparado con los otros se ve pequenno" /
  "- el icono en settings no tiene colores porque?" / "- los cursores
  personalizados de los tools camian y no todos son diferentes. por defecto es la
  cruz excepto los que tienen el propio como 'v','f','t'." / "- el cursor de pen
  debe ser un dot o algo asi" / "- el cursor de highligh debe ser el cursor bloque
  fill" / "- el erase un circulo sin relleno solo borde" / "- el count debe ser un
  circulo dentro de otro circulo" / "- configura settigns/capture para que por
  defecto el name tempate haga lo que dice el ejemplo:
  Stare-2026-11-21-at-14-05-33.png y despues hay que hacer que lo que se ponga en
  el name template tenga un preview en tiempo real."
- **L2** (exploration, before any edit): the four locations, with the two surprises.
  (a) **The cursor table already exists and is already exhaustive**: `Tool.cursor`
  (`Sources/StareCore/Tool.swift:63`) answers one role per tool with no `default:`,
  `ToolCursor` has 13 roles, and two tests pin the bijection
  (`ToolAndInkTests.swift:224/236`). So S3 is NOT a missing table: it is (i) four
  roles drawn as the wrong shape — `eraser` is a BLOCK, `number` is a HAND, `pen` a
  nib, `highlighter` a chisel — and (ii) the catch: **the capture editor never shows
  a tool cursor at all**, `CaptureEditor.swift:1589-1598` overrides `gestureCursor`
  and `reassertCursor()` so it is arrow-only. That is very likely the owner's "los
  cursores cambian": they change between the editor and outside. T3 fixes the shapes
  and lets the editor answer with the tool's cursor, since the editor is where the
  drawing happens. Every cursor must keep going through `reassertCursor()`, and the
  two monitors (bar at `OverlayController.swift:1757`, card at `:1815`) stay the
  arbiters.
  (b) **The Settings mark is a known bug with a known fix**: `AppMark`
  (`SettingsComponents.swift:354-363`) uses `NSApp.applicationIconImage`, which
  returns a DESATURATED variant on macOS 26; `OnboardingView.swift:232-238` already
  solved it by reading `Resources/AppIcon.icns` first. T2 makes `AppMark` use one
  shared source instead of a third variant.
  (c) The menu bar glyph is an 18×18 pt template vector with the ink at 87 % of it
  (~15.7 pt) — `StatusBarController.swift:240-258`, `isTemplate` must stay, and a
  PDF/bitmap rep is recorded as broken. T1 sizes it up.
  (d) **The filename template already does what S4 asks**: `defaultFileNameTemplate`
  is `""` (`CapturePreference.swift:130`), which routes to the legacy branch and
  yields exactly `Stare-2026-11-21-at-14-05-33.png`, and `exampleName`
  (`SettingsView.swift:1782-1792`) is already a live preview through the same
  `fileName(at:calendar:app:display:)` the write path uses. What is actually wrong is
  narrower and worse: the save panel calls `preference.fileName(at: Date())`
  **without** app/display (`CaptureEditor.swift:1887`), so a `{app}` or `{display}`
  template previews one name and saves the legacy one. T4 makes the default an
  explicit template that documents itself (`Stare-{date}-at-{time}` — byte-for-byte
  the same name the legacy branch produced), keeps `""` meaningful for stored
  preferences, and closes the preview/save disagreement by giving the save panel the
  same inputs the preview has.
- **L3** (S1, T1): the menu bar glyph's ink sized up to system weight. The
  recorded "~15.7 pt of ink at the 87 % inset" turned out to be an estimate over
  the flat box: measuring the real painted bounds (render the actual
  `NSImage(size:flipped:)` glyph into a bitmap and scan the alpha channel) puts
  the old ink at **7.0 × 10.25 pt** inside the 18 pt canvas — the 32°-rotated
  nib covers only a small part of the 64-unit design box, so the 87 % scale was
  never reaching the canvas edges. The nib outline, its holes and the
  `isTemplate = true` at the call site are untouched; what changed is the two
  numbers that now govern the size, both named and both in
  `StatusBarController.swift`: `menuBarGlyphSidePoints = 22` (was hard-coded 18)
  and `nibInkCoverage = 0.80` replacing the fixed 0.87 inset — `place` now
  derives one placement transform by rotating about the shape's centre and
  fitting + centring the rotated outline's bounds to 80 % of the design box,
  so outline and holes share the same derived transform. **Ink after:
  11.0 × 16.0 pt** (measured from the real glyph, in the system 16–18 pt band).
  Clipping could not be fully verified headlessly, so 22 was verified instead
  by probing AppKit headlessly: a default status item button's frame is
  16 × 22 pt, images of 18/20/22 pt keep it at exactly 22 pt (24 and 28 grow
  the button to the image height), and this machine's menu bar measures ~28.5 pt
  tall — so a 22 pt canvas keeps the item at the system's own control height
  with no growth or clip. Tests (`Tests/StareTests/StatusBarGlyphTests.swift`)
  pin the constellation: canvas equals the constant, painted ink ≥ 15.5 pt tall
  and ≥ 10 pt wide and ≤ the canvas, and that the drawn CG representation still
  paints real ink (the broken-PDF regression). RED was observed by scaffolding
  the named constant at the historical 18 pt: measured ink 7.0 × 9.5 pt failed
  the 15.5 pt pin (exit 1); GREEN at 22 pt with the lifted inset (exit 0).
  Focused `--filter "StatusBarGlyphTests|AppIconImageTests"`: 6 tests, 0
  failures; full suite `swift test` exit 0, StareTests 355 / StareCoreTests
  880, 0 failures.
- **L4** (S2, T2): the Settings app mark is drawn from ONE shared colour
  source. `AppIconArtwork` (`SettingsComponents.swift`) now owns the
  icns-first-then-`applicationIconImage` resolution that `OnboardingView`
  already had: `resolve(in:)` reads the given bundle's
  `Resources/AppIcon.icns` and falls back to `NSApp.applicationIconImage`
  only when the resource is missing or undecodable, with the head-testable core
  in `resolve(resourceURL:fallback:)`; `AppIconArtwork.main` caches the
  main-bundle result so neither caller re-decodes the 612 KB file on every
  render tick. `AppMark` now reads `AppIconArtwork.main` (identity behaviour
  untouched: no tint, no template, `accessibilityHidden(true)`, the `size`
  parameter and both call sites unchanged), and `OnboardingView.appIcon` is
  the same shared source (its `let`, once-a-second refresh untouched — the new
  static let only resolved once before). The test target does not receive
  `.icns` resources from SwiftPM, so `Tests/StareTests/AppIconImageTests.swift`
  reaches the repository's real `Resources/AppIcon.icns` by path and pins the
  resolution itself: icns-first decode returning the file's own non-empty
  size and `isTemplate == false`, fallback returned unchanged (by identity)
  for a missing URL and for an undecodable file, plus a pin that
  `Bundle.main` in tests carries no resource, so the fallback branch the app
  relies on under `swift run` is exactly what the tests model. RED was the
  compile failure (`cannot find 'AppIconArtwork' in scope`, exit 1); GREEN
  through the focused filter (4 tests, 0 failures, exit 0) and the full
  suite (355 / 880, 0 failures, exit 0).
- **L5** (S3, T3): the four tools' cursors redrawn as the owner's shapes, and
  the capture editor answers with them. The table was already exhaustive
  (`Tool.cursor`, no default), so only the art and the roles' names moved:
  `penNib→penDot`, `markerChisel→markerBeam`, `eraserBlock→eraserRing`,
  `numberHand→numberRings` (`Tool.swift`, `OverlayView.swift`). The four drawn
  shapes, each readable at 16 pt over both themes via the established
  dark-outline/white-core trick: **pen** = a filled dot (dark disc r 2.9,
  white core r 2.0) sitting exactly on the hotspot (the mark starts where the
  pointer is); **highlighter** = a FILLED horizontal beam 8.4×4.4 pt with flat
  edges (dark body, white core), wider than tall so it never reads as the
  rectangle's square frame; **eraser** = an EMPTY circle, border only, no
  fill (stroked ring r 5.0 centred on the hotspot, the centre stays
  transparent so the pixels under the pointer are visible); **number** = a
  circle inside a circle — two THIN concentric rings (r 5.9 and r 2.7,
  stroked 2.2 dark / 1.0 light via a new `outline` width parameter) so the
  two circles stay two circles instead of welding into one thick ring. The
  explicit name change matters: `numberHand` drew nothing — it was the system
  pointing hand — so the count tool moved from the AppKit set into the drawn
  set (now 11 drawn glyphs, 3 system identities: arrow, I-beam, crosshair).
  **The distinctness audit** (measured, 2× rendered alpha of every drawn
  glyph, painted box + centre/ring scan): one real collision found and fixed
  — the new empty eraser circle would have read EXACTLY like the ellipse's
  cursor, which was drawn as a circle too — so `ellipseRing` is now a true
  OVAL (8.4×6.2, box 11×9 vs the eraser's 13×13). Everything else stayed
  with the numbers: pen 6×6 filled; highlighter 8×4 filled; arrowHead 10×10
  filled at the centre (the shaft crosses it); rectangleFrame 11×11 empty;
  laserSpark 14×14 filled (dot + edge rays — not a crosshair read, the rays
  are short edge marks around a bright dot); blurDots 10×10 (a 3×3 grid, not
  the pen's single dot); spotlightBeam 12×12 filled centre dot + ring. Closest
  surviving neighbours, judged distinguishable at 16 pt: numberRings (14×14,
  hollow centre, inner ring, gap, outer ring) vs eraserRing (one ring, fully
  clear interior) vs spotlightBeam (filled centre dot), and the filled beam
  vs the empty rectangle frame — the fill/hollow and ring-count differences
  are what the tests pin. No drawn glyph reads as the crosshair; the
  crosshair role itself (Line) untouched. **The capture editor now answers
  with the active tool's cursor** (`CaptureEditor.swift`): a new `toolCursor`
  answers `OverlayView.cursor(for: tool.cursor)` only when a TOOL is armed
  (`case .tool(let tool) = state.captureSelection`), `tool`
  `worksInCaptureEditor` — the armed crop keeps the plain arrow (its staged
  rectangle keeps its own pointer vocabulary, as before), a whiteboard-only
  tool (select/text/laser) carried in the detached state answers the arrow,
  and `reassertCursor()` is unchanged in shape — `(gestureCursor ??
  toolCursor).set()`, now `internal` so the test reaches the real path; the
  editor still sets a cursor in exactly one place, the gesture cursors
  (closed/open hand, zoom magnifier) still win. **Tests**:
  `Tests/StareTests/ToolCursorGlyphTests.swift` renders the cursors at 2× and
  scans alpha — the four owner shapes are pinned as measured pixels (pen
  centre+ring filled, small and round; highlighter filled across the centre
  row and wider than tall; eraser centre alpha ≤ 0.01 with border ink at
  r 5; number ink at r 2.7, CLEAR GAP at r 4.3, ink at r 5.9), the ellipse's
  oval-with-empty-centre separation from the eraser, the
  rectangle/spotlight PRESERVE pins, and the 16-pt/hotspot-8,8/no-system-
  fallback contract for every drawn role;
  `Tests/StareTests/CaptureEditorCursorTests.swift` drives the real canvas —
  pen answers with a 16-pt centred glyph and never the arrow, switching to
  the eraser swaps the glyph, an armed crop keeps the arrow, select/text/laser
  never show a cursor in the editor, and an actual synthetic space keypress
  shows the open hand with release handing back the tool glyph through the
  canvas's own `keyDown`/`keyUp`; the bijection pins in
  `ToolAndInkTests.swift:224/236` keep their meaning with the renamed roles
  in the expected map. `SelfTest.toolCursorsReport()` updated: its AppKit
  identity dict now holds three roles (the hand left the system set with the
  number tool), so it now proves every tool owns a distinct role, the three
  system identities (arrow, I-beam, crosshair) are served BY IDENTITY, and
  the remaining TEN roles build as drawn 16-pt glyphs centred on the hotspot
  with one PNG each in /tmp — the visual reading of the four shapes remains
  the owner's check. RED was the compile failure against the old API (unknown
  `.penDot` etc., `reassertCursor` private, exit 1); GREEN through the focused
  filter `ToolCursorGlyphTests|CaptureEditorCursorTests|ToolAndInkTests`
  (23 tests, 0 failures, exit 0); full `swift test` exit 0, StareTests 367
  / StareCoreTests 880, 0 failures.
- **L6** (S4, T4): the name template says what it does and the preview and the
  save path are one answer. **The shipped default is now the explicit template
  `Stare-{date}-at-{time}`** (`CapturePreference.defaultFileNameTemplate`, was
  `""`), which renders the field's own example — exactly
  **`Stare-2026-11-21-at-14-05-33.png`** — byte for byte the name the legacy
  branch produced (the unmodified `CaptureFileNamePreservePinTests` pin through
  `CaptureFile.write` keeps passing). The empty template keeps its current
  meaning for preferences already stored on disk: blobs without the field
  decode to `""` and every sanitisation refusal still stores `""`, both routed
  to `legacyFileName`, so no existing user's names change — the code comment on
  `defaultFileNameTemplate` and on the empty guard inside `fileName(at:)` says
  why the empty case deliberately stays pinned by the two adapted PRESERVE
  tests (`testMissingFieldsTakeStandard`, `testBlobWithoutTemplateFieldDecodesEmpty`
  now compare against standard-minus-template, i.e. the empty stored template).
  **How the editor learned app and display — it could not, and both paths agree
  on the shared fallback.** The overlay handoff that opens the editor carries
  only `(image, CapturePreference, RedactionStyle)` (the handoff sites live in
  `OverlayController.swift`, outside this task's edit surfaces), and any value
  asked at save time would be invented: while the editor window is up Stare is
  the frontmost application, so the capture path's own resolver
  `CaptureAppIdentity.appName(frontmostName:frontmostProcessIdentifier:)`
  refuses `{app}` by its own contract ({app} must name what was captured, never
  the tool), and the only display the editor sees (`window.screen`) is its own
  window's, never necessarily the captured one. So the save panel passes `nil`
  for both — the deliberate refusal — through one shared seam,
  `CaptureEditorCanvas.savePanelFileName(preference:at:calendar:)` (new,
  internal static, used by the real `savePanel` call site where
  `nameFieldStringValue` is set), and the Settings live preview (`exampleName`)
  now calls that same seam with its fixed sample instant instead of the old
  hardcoded `app: "Safari"`, `display: "Built-in"` samples. Result: an `{app}`
  or `{display}` template previews the fallback the save really writes (the
  prefix name, e.g. `Stare-2026-11-21-at-14-05-33.png`), never a name no path
  can produce; the Settings row's detail text was rewritten to say so, and the
  old "sample app and display" wording is gone. The honest boundary is stated,
  not hidden: the OVERLAY's own folder save (`OverlayController.deliver`)
  still knows the app and display at the capture instant and still resolves
  them — the agreement is between the editor's save panel and the preview,
  both of which genuinely cannot know. The live preview already was live over
  the observed model (L2c); it stays live and now agrees. The template's other
  guarantees were untouched: same `parsedTemplate` for validation and
  rendering, safe-set literals, unknown-token/malformed-brace refusal, the
  never-doubled extension, one path component, the `.disabled(isClipboard)`
  state and the 180 pt field width (its pin,
  `SettingsCapturePaneDisabledStateTests`, keeps passing untouched).
  **Tests** (RED first): new `Tests/StareTests/CaptureFileNamePreviewTests.swift`
  — the shipped default through the editor seam renders the documented
  example, the seam's name follows the template as it changes (an `{app}`
  template with no known app degrades to the prefix name; a caller that KNOWS
  the app renders it, pinned at the StareCore level in
  `CaptureFileNameTemplateTests.testRenderedNameFollowsTheTemplateAsItChanges`
  → `Safari.png`), and the save-panel name and the preview name are one call
  with the same inputs (seam == `fileName(at:calendar:app: nil, display: nil)`
  across six templates). RED was the compile failure (`CaptureEditorCanvas`
  has no member `savePanelFileName`, exit 1); GREEN through the focused filter
  (40 tests, 0 failures, exit 0); full `swift test` exit 0, StareTests 370 /
  StareCoreTests 883, 0 failures. One note, honestly: with the non-empty
  default template the prefix is unused on a fresh install, so `SelfTest`'s
  capture-component report line now reads `name=Stare-…png` where it printed
  `name=Selftest-…png` — the check itself (the write lands under the same
  name `fileName(at:)` returns for the same instant) is self-consistent and
  passing. RED overall: first focused run exit 1 (compile failure of the new
  seam), then GREEN 40/0; full suite 1253 tests, 0 failures, exit 0.
- **L7** (S4 follow-up, owner-approved option A): the Name prefix row is no
  longer silently dead. What it was: always editable, whatever the name
  template said — and since L6 the shipped default template is
  `Stare-{date}-at-{time}`, so on a fresh install the prefix never names
  anything while looking alive. **The rule, destination-independent**: the
  prefix field is disabled exactly when `model.capture.fileNameTemplate`
  is non-empty and enabled when it is empty — clipboard and folder saves
  alike. Rationale the owner approved: with the template owning the whole
  name (S4), the control that governs must be the one that looks alive,
  and a destination-scoped exception would leave a rarely-live control
  that lies on the clipboard path anyway. **Wording of the caption** (one
  line, the pane's own caption voice, under the two rows, above the
  preview): "While a template is set it builds the whole file name; clear
  it and the prefix names the files again." The prefix row keeps its
  existing character-set detail for the state where it governs; no card
  was added, and the naming rules, sanitising, legacy empty-template path,
  the L6 preview/save seam and the rendered name are untouched. **The two
  pins that changed** (`SettingsCapturePaneDisabledStateTests`, nothing
  else in that file): both flipped from
  `XCTAssertTrue(pane.prefix.isEnabled)` to `XCTAssertFalse` with the
  canary notes reworded to record WHY — the template owns the name while
  it is set, so the prefix stands down wherever the capture goes (the
  clipboard note), and the same rule sits on the folder destination,
  coming back editable when the template is cleared (the folder note);
  the clipboard-destination and backdrop assertions are exactly as they
  were. **New behaviour pin**
  (`Tests/StareTests/CapturePrefixAndTemplateTests.swift`): rendered
  through the real pane into a real window, the prefix found by its bound
  "Shots" string, never by tree order, at BOTH destinations — template set
  → prefix disabled and the pane's own preview call
  (`CaptureEditorCanvas.savePanelFileName`) promises the template's name
  (`2026-11-21.png`); template cleared → prefix enabled and it promises
  the legacy prefix name (`Shots-2026-11-21-at-14-05-33.png`). Test-first:
  RED observed with the pins flipped against the old always-editable row
  (exit 1; four rule failures, the two name pins inside the new tests
  already passing); GREEN exit 0, focused filter
  `CapturePrefixAndTemplateTests|SettingsCapturePaneDisabledStateTests`
  4 tests, 0 failures (StareTests/0 StareCore). Full suite `swift test`,
  exit 0, StareTests 372 / StareCoreTests 883, 0 failures.
- **L8** (S5, T5): the menu bar glyph a step smaller, and tilting WITH the logo. **The
  size step**: `menuBarGlyphSidePoints` 22 → 20 (the fitted `nibInkCoverage = 0.80`
  mechanism untouched); the painted ink went from **11.0 × 16.0 pt** (L4's
  measurement at 22) to **9.5 × 14.5 pt** (probe replicating the exact new
  placement, alpha > 0.5 at 2×) — one step down, still near the system weight;
  the headless probe still shows a 20 pt image keeping `NSStatusBar`'s button at
  its default 22 pt height. The outline, the holes, the even-odd fill, the clip
  and `isTemplate = true` are untouched. **The tilt, measured and fixed at its
  real cause**: the artwork's nib, measured from the app's own pixels — decode
  `Resources/AppIcon.icns` (512 pt), render at 2×, take the pure-white nib mask
  inside the opaque square (95,910 px; sheen and stroke excluded by threshold),
  principal-axis + tail-end detection — leans **31.997° ≈ 32° off vertical with
  the tip toward the BOTTOM-LEFT**, which matches the SVG source
  (`Resources/app-icon.svg` rotates the nib `rotate(32 32 32)` in its y-down
  design box). The old glyph measured tipping bottom-RIGHT — mirrored, exactly
  the owner's report. The cause was NOT the angle constant: it was CG's
  row-vector concat order — `flip.concatenating(scaled.concatenating(rotate))`
  serves flip FIRST, so the +32° rotation was applied LAST, in AppKit's y-up
  space where its positive sense is mirrored (settled by a transform probe:
  a·concatenating(b) applies a first; the old composite's placed tip vertex was
  (45.69, 7.40) = bottom-right). The fix reorders the same composite to
  `rotate.concatenating(scaled.concatenating(flip))` — rotate and fit in the
  SVG's y-down design box, flip LAST — keeping the artwork's own +32°
  (`nibTiltDegrees = 32`, now named) instead of negating anything; the placed
  tip is (15.17, 6.40) = bottom-left, box exactly centred at (32,32). **Tests**
  (`StatusBarGlyphTests`): new `testGlyphTiltAgreesWithTheArtworkAxis` runs the
  same axis probe over the glyph's ink mask and the artwork's own nib mask and
  pins the same tip side and the same lean within 2.5° of the artwork's
  measurement (artwork also pinned to 32.0° ± 2 and tip bottom-left), so the
  glyph can only disagree with the logo by keying a different angle; the ink
  pins moved to the band **14.0–15.0 pt tall × 9.4–10.6 pt wide** whose UPPER
  bound is what catches a silent revert to the 22 pt canvas (16.0 pt breached
  it from both ends at RED). RED: the new tilt pin measured the glyph
  bottom-right vs the artwork bottom-left, and the 16.0 pt ink breached the new
  upper band — `swift test --filter "StatusBarGlyphTests|AppIconImageTests"`
  exit 1 (the first RED invocation also caught my own helper's argument-label
  typo, exit 1, fixed in the test before the behavioural RED was observed).
  GREEN: same focus, 8 tests, 0 failures, exit 0. Full suite: exit 0,
  StareTests 374 / StareCoreTests 883, 0 failures. The exact "un tilin" feel
  and the in-bar look remain the owner's eye.
- **L9** (S6, T6): the Settings mark sits flat — the shadow's origin found
  before anything changed: **the drop shadow is baked into
  `Resources/AppIcon.icns`'s own pixels**. Evidence: (a) the artwork's SVG
  source carries `filter id="shadow"` — `feDropShadow dx=0 dy=8 stdDeviation=10
  flood-opacity=.3` — on the aurora rounded square, and `Scripts/icons.sh`
  rasterises that very SVG into the icns (there is no separate PNG source
  behind it); (b) measured on the decoded icns at 2×: a 512 pt canvas whose
  opaque square is **412 × 412 pt** (100 px inset of 1024 per side, exactly the
  SVG's `translate(100) scale(12.875)` 824 px square) and **295,497 soft-alpha
  pixels** around that square, capped at the flood opacity's ~30 % — shadow
  ink in the file; (c) no SwiftUI modifier draws one — nothing under
  `Sources/` uses `.shadow()` at all, and both `AppMark` call sites
  (`SettingsView.swift:222, 1948`) were clean. **The fix, at the source that
  owns the mark's presentation**: `AppIconArtwork.resolve` (the ONE shared
  source of L4) now trims whatever it resolves to the opaque shape's own
  bounds (alpha ≥ 0.5 — above the shadow's 30 % ceiling, below the artwork's
  edges, measured at 2×), so the shadow's padding never reaches `AppMark` or
  the setup guide; both branches (icns and the `applicationIconImage`
  fallback) are trimmed, an image that carries no opaque region or is already
  tight comes back unchanged (the fallback-identity pins of
  missing/undecodable still pass), and `trimToOpaqueBounds` is the single new
  seam. The small `#lift` shadow UNDER THE NIB inside the tile stays — it is
  part of the logo art everywhere (Finder, landing), not the canvas-perimeter
  shadow the owner pointed at. **The cost of the crop, stated**: the mark now
  draws the tile edge-to-edge of its `size` frame, so the visible square is
  ~24 % larger in side than the padded canvas made it (512/412) at unchanged
  `size` (32 and 56) and unchanged call sites; identity behaviour untouched —
  no tint, not a template image, `accessibilityHidden(true)`, both call sites,
  the `size` parameter. **Tests** (`AppIconImageTests`): the resolution pin now
  asserts the resolved image's bounds equal the RAW DECODE's own measured
  opaque bounds within ±1 pt and strictly smaller than the raw canvas; a new
  `testTheIcnsArtworkCarriesBakedShadowPadding` proves the evidence itself —
  the opaque square inset ≥ 8 % per side and ≥ 20,000 soft-alpha pixels
  outside it (measured ~295 k). What remains the owner's eye: the flat, in
  colour look at 32/56 pt — a pixel assertion of "no shadow visible" does not
  honestly exist post-trim (the tile's own rounded corners are alpha 0 by
  design), so the tests pin the geometry and the eye pins the rendering. RED:
  `testResolutionPrefersTheRealIcnsArtwork` measured the resolved artwork at
  the raw 512 pt canvas vs the 412 pt opaque bounds (three failures), with the
  evidence pin already green against the unchanged file — focused filter exit
  1; GREEN same focus 8 tests, 0 failures, exit 0; full suite exit 0,
  StareTests 374 / StareCoreTests 883, 0 failures. Deliberately untouched:
  `OnboardingView.swift` (shares the fixed source; no edit needed),
  `SelfTest.swift`, `Scripts/icons.sh` and `Resources/` (the Finder icon
  keeps its baked shadow by design; regenerating it would restyle every icon
  surface the owner did not complain about).
- **L10** (S7, T7): the highlighter's beam turns vertical, three shape tools
  join line on the crosshair, and the capture editor's cursor finally
  arrives in the real window. **The beam**: `drawMarkerBeam` swaps its axis
  — now 4.4 wide × 8.4 tall on the unchanged 16-pt canvas, hotspot still
  centred, still a FILLED block with flat edges built from the dark
  body + light core (the fill trick can't take an outline); what it reads
  as is the vertical swab stroke itself. **The identity changes**: the roles
  `arrowHead/rectangleFrame/ellipseRing` are renamed to
  `arrowCrosshair/rectangleCrosshair/ellipseCrosshair` and are served
  `NSCursor.crosshair` BY IDENTITY in `OverlayView.cursor(for:)`, exactly
  the way `lineCrosshair` already was — the glyphs `drawArrowHead`, the
  rectangle frame and the oval are deleted from the drawn set (11 → 7 drawn;
  4 crosshair roles, 3 other system identities, no sharing between tools:
  the bijection table stays one role per tool, and
  `ToolAndInkTests.testEveryToolHasItsOwnCursorRole` keeps meaning exactly
  that with the renamed expected map). The three drawn shapes the owner's
  report retires also retire the L5 collision note: the oval existed to
  never read as the eraser's circle, and the oval is gone. **The editor
  root cause, measured not guessed**: the canvas's `cursorUpdate` handler
  (L5) could never be DELIVERED — AppKit routes cursor updates (and
  entry/exit crossings) only through a tracking area, and
  `git show HEAD:Sources/Stare/CaptureEditor.swift` contains ZERO
  tracking-area and ZERO `resetCursorRects` references: the canvas declared
  no cursor rects and no area, so nothing ever generated a cursor update
  for it; the window itself was never the problem (`canBecomeKey: true`,
  now pinned by a test), and `mouseMoved` was never delivered either (the
  window did not opt in with `acceptsMouseMovedEvents`). Every cursor
  surface of this app already carries the delivery half — `OverlayView`,
  `CaptureCard`, `ToolbarPanel`, `ToolbarView` all install
  `[.cursorUpdate, .activeAlways, .inVisibleRect]` areas, and
  OverlayView's own comment says why (".activeAlways keeps the tool cursor
  working even when the app is not the active one, which cursor rectangles
  alone do not allow") — the editor's canvas was the one surface missing
  it. The old test passed because it called `reassertCursor()` and the
  handlers DIRECTLY — decision proof with no delivery proof, the
  insufficient evidence the owner's "3.b. no funciona" exposed.
  `NSEvent` has no public constructor for a synthesized cursor update (the
  mouseEvent factory rejects the type at runtime:
  `_NSEventMask64FromType(type) & (MouseMask|NSEventMaskMouseMoved)` fails;
  an `otherEvent` constructor never compiles against this SDK's imported
  Swift signatures at all), so a synthesized cursor update cannot even be
  BUILT with public API and window-server
  delivery cannot be exercised headlessly — the honest boundary. The fix:
  the canvas installs the same area as its siblings in
  `updateTrackingAreas` (`.cursorUpdate`, `.mouseEnteredAndExited`,
  `.activeAlways`, `.inVisibleRect`), re-asserts on `cursorUpdate`,
  `mouseEntered` and — the window now opts in with
  `acceptsMouseMovedEvents` — `mouseMoved`, and on `mouseExited` it hands
  the pointer back to the editor's own chrome (arrow), so the last tool
  glyph never rides over the toolbar. The gesture vocabulary (pan, space,
  ⌘-scroll) and the armed-crop arrow stay ahead of the tool cursor and no
  second `NSCursor.set()` ambient path was added (the exit hand-back is
  this surface's own exit answer). **Tests**: the beam pin is now vertical
  (filled down the centre column, taller than wide by ≥ 2 pt); the three
  crosshair roles answer `=== NSCursor.crosshair`; the every-role
  contract's identity map now names six identity roles and seven drawn
  glyphs; the tracking-area PIN sees AppKit's own pass register it in the
  real window (a runloop spin schedules it in the test host; before the
  fix the canvas owned ZERO areas), plus the `canBecomeKey` diagnosis pin.
  RED: the first delivery attempt (a window-routed synthetic cursor
  update) failed with the NSEvent construction exception, then was proven
  impossible headlessly via the probe; the tracking-area pin's first GREEN
  run failed 0 ≠ 1 until AppKit's scheduling pass was honoured — mechanism
  presence before, delivery in the real window remains the owner's eye
  (the shared pattern already proven on the overlay, bar and cards).
  Full `swift test` exit 0, StareTests 376 / StareCoreTests 890 (the +7 in
  StareCore are the concurrent filename-template worker's), 0 failures.
- **L11** (S8, T8): the template default reaches the install that stored the old one. The owner's capture
  document on disk was written before the shipped default changed, so it held `""` — and `""` routes to the
  legacy prefix branch, so Settings showed an EMPTY Name template field while the preview row right below it
  already promised `Stare-2026-11-21-at-14-05-33.png`. **The migration, on the toolbar's discipline**
  (`ToolbarToolLayout.mayMigrate`, hard-won in `9efcbbd`): the capture document now carries its own `version`
  — `CapturePreference.currentVersion = 2`, stamped first by a new custom `encode(to:)` on everything this
  build writes (it never had one: encode was synthesized, so the unstamped generation is every blob written
  before this change) — and `init(from:)` migrates once, on load, a document that (a) may migrate (unstamped,
  or a readable version below 2 — a version that exists but cannot be READ counts as current and never
  migrates) and (b) whose stored template is the old shipped default (absent, or the empty string). Nothing
  else moves: any other template is one nobody can prove was shipped, so it stays and the lenient sanitising
  decides what it means, which is why the refusal pins (`{bogus}` → `""`, prefix names) pass unchanged. After
  the stamp, an explicitly cleared `""` is the user's choice and survives every save and reload.
  **Reconciliation, on the record**: my instruction said "a missing version must NOT migrate", copied from a
  pattern whose document always had a version. The capture document never did, so that literal rule would
  make migration unreachable and leave the owner's field empty — the reported defect. Implemented instead:
  unstamped migrates, unreadable never does, which is what the cited commit actually enforces.
  Three proven decodes: the owner's byte-for-byte blob (unstamped, `""`) → `Stare-{date}-at-{time}`, still
  rendering `Stare-2026-11-21-at-14-05-33.png`; a custom stored template kept byte for byte at every version;
  `""` at version 2 stays `""` with the prefix naming the files. What the owner sees: the field shows the
  template, the prefix row stands down (L7's rule follows the field), exactly a fresh install's pane.
  Test-first: RED `CapturePreference` has no member `currentVersion`, GREEN 85/0 focused; StareCoreTests
  890/0. Version numbering: none before, 2 after.
- **L12** (S9, T9): the mark is cut to its ROUNDED SHAPE, and the radius is measured, not assumed.
  **The shape**, from the artwork itself: `Resources/app-icon.svg` draws the card as a 64-design-box
  rect with `rx 14.37` inside the `translate(100) scale(12.875)` card — 824 px square inside the 1024
  canvas with a 185 px corner radius. **How measured** (2× render of the resolved image, alpha ≥ 0.5
  scan): the intense edge-row/edge-column offsets (the arc's run-out on each box edge, both ends —
  measured 169/170 px, tightly consistent everywhere) give a first guess, but the EXTREME edge row is
  tangent to the arc and its shallow coverage ramp (the profile climbs 0 → 1 over ~19 px) reads a
  radius a few percent INSIDE the true one. So the true radius is solved from the same alpha map
  deeper in the arc, where the boundary is steep enough for its ≥ 0.5 contour to track it: contour
  offset `d` at depth `k` = initial/2, solved through the arc's own equation
  `d = r − sqrt(r² − (r−k)²)` → `r = d + k + sqrt(2·d·k)`; all eight depth probes (each edge row and
  column, both of whose corners) returned **183–185 px**, consensus **184 px = 92.0 pt** — the
  design's 185 px. The probe spread tolerance and the edge-offset consensus (both `max(6, side/100)`,
  8 px here) refuse any shape the alpha map cannot read as a rounded square; radius zero (sharp
  corners, fully-opaque alpha) or a disagreement keeps the plain L9 box trim — no clipping of images
  that cannot be measured. **What was clipped**: `AppIconArtwork.clipToOpaqueShape` (renamed from
  `trimToOpaqueBounds`; still the one seam behind `resolve`, which stays the single source for
  `AppMark` and the setup guide) renders the bounds-cropped artwork into a fresh bitmap THROUGH
  `NSBezierPath`'s rounded rect at the measured radius, so a pixel outside the shape is fully
  transparent while the shape's bounds stay the card's own — nothing about size, colour, tint,
  template-ness, `accessibilityHidden`, the `size` parameter or either call site moved.
  **Verification numbers**: corner pixels BEFORE the cut (RED run) read alpha 0.098 at the two bottom
  corners (the shadow's `dy=8` biases it down; top corners ≤ 0.05 by the same bias) — AFTER the cut,
  all four corners read exactly **0.0** (named threshold 0.05); the four edge midpoints read 1.0,
  well above the 0.5 pin; the resolved bounds stay the measured 412 × 412 pt card within the ±1 pt
  pin, and the radius pin (92.5 ± 3 pt, plus the 412 pt bounds pin) keeps a future re-raster of the
  icns from silently moving the cut. The scratch probe that measured all of this ran in
  `/tmp/stare-t9-probe` and was removed after the runs. Tests in `AppIconImageTests` (now 9): the
  two new S9 pins (corner transparency, edge midpoints) — RED observed first with corner alpha 0.098
  > 0.05, focused run exit 1 — plus the radius pin, a fully-opaque fallback identity pin (degenerate
  case), and the five pre-existing pins all green. Focused `--filter AppIconImageTests` exit 0, 9
  tests, 0 failures; full `swift test` unpiped exit 0, StareTests 380 / StareCoreTests 890, 0
  failures. What remains the owner's eye: the corners' look at 32/56 pt — the pixels now say the cut
  is exact.
