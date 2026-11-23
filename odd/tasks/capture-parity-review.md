# Review guide — feat/capture-parity

One page for reviewing 36 commits without reading 7.839 lines. The branch is a
fast-forward over `main` (`2b9c66c`); the history is already sliced by feature,
one commit per unit, each message saying what and why.

3.240 lines are production, 4.333 are tests, 266 are docs. Read the production
lines below, trust the tests to argue for themselves, and use the "look for"
column as the thing worth being suspicious about.

| # | Feature | Read these first | The invariant | Look for |
| --- | --- | --- | --- | --- |
| 1 | Window capture (`⌥S`) | `WindowCaptureTarget.swift`, `FrontWindowSelection.swift`, `WindowCaptureGeometry.swift`, `OverlayController.captureFrontWindow` | The window only decides what gets cropped; the pixels are the display's, so marks land where they were drawn | That `S` and `⌥S` never receive a frozen base, and that `⌥⇧S` kept meaning "area" |
| 2 | Area drag geometry | `AreaSelectionGeometry`, `AreaCaptureFrame`, `AreaCaptureLoupe`, `AreaCaptureMemory` | A drag freezes on a frame that already exists, and every conversion is in the image's own top-left space | The y conversion in `AreaCaptureLoupe`: it shipped mirrored once, and the tests that missed it all used the display's exact middle |
| 3 | Capture history | `CaptureHistory`, `SettingsHistoryPane`, `OverlayController.openCaptureEditor` | One editor, one handoff: the card and the pane call the same line | That nothing persists to disk, and that the stored image is the delivered one, not a recomposition |
| 4 | Pin a captured image | `PinnedImage`, `PinnedImageWindow`, `CaptureCard` pin button | `⌥⇧P` still pins the drawing; the image has its own entry points | `CaptureCard`'s editor-open and drag-out are byte-for-byte what they were |
| 5 | OCR and QR (`⌥⇧O`) | `TextRecognition`, `TextRecognitionClient`, `TextSelectionWindow` | The clipboard is written only on a non-empty result, and the surface only appears on the pointer's display | That no network call exists anywhere in this path |
| 6 | Downscale on save | `CaptureDownscale`, `CaptureFile` | Off is byte-identical to today; the clipboard never downscales | That `CaptureFile` moved to `StareCore` and the Stare-local shadow is gone — it was inert while every test passed |
| 7 | Annotation depth | `Stroke` (`isFilled`, `arrowHead`), `MarkRenderer` fill and head branches, `DrawingSession.lastTextStyle` | Every mark drawn before this change renders to the same hash | That the keys `9` and `0` are read after the live shortcut map |
| 8 | Spotlight (`D`) | `Tool.spotlight`, `MarkRenderer.drawSpotlight`, `MarkCompositor`'s case | One renderer, so preview and capture cannot disagree | The shroud is exempt from dirty-rect culling on purpose; the comment says why |

## Shared infrastructure worth one look

- `Tests/StareTests/PrimaryScreenTestWindow.swift` — every test window is
  confined to the primary screen. This exists because test runs were
  interrupting the human's other monitors, and `NSWindow.confineToPrimaryScreen`
  delegates to it so there is one implementation.
- `odd/tasks/capture-parity.md` — S1–S24 are the specs and the surface
  authorisations between the two sessions; L1–L21 are the log, including the
  three defects that green suites did not catch.

## The three defects this branch shipped and then fixed

Worth reading as a set, because they share one shape: **the test passed because
its input was the one case where the bug is invisible.**

1. The loupe magnified a vertically mirrored band — every test used `y = 350` in
   a 700-tall display.
2. A Stare-local `CaptureFile` shadowed the new `StareCore` one, so downscale
   was inert in the app while 38 cases passed.
3. `⌥S` swallowed the key on the whiteboard, because the handler was wired on
   one canvas builder and not the other.
