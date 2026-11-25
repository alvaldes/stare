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

## Tasks

| ID | Specs | Task | Route | Commit |
| --- | --- | --- | --- | --- |
| T1 | S1 | The status bar glyph sized with the system's own items | worker | c5bce43 |
| T2 | S2 | The Settings app mark drawn in colour | worker | c5bce43 |
| T3 | S3 | One cursor table, one entry per tool, the four named shapes | worker | 86c3923 |
| T4 | S4 | The default template matches its documented example; the field previews live | worker | b612a8e |

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
