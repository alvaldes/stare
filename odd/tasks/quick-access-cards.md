# C3: the capture card as a small command surface

## Specs

- **S1** (verbatim): "puedes hacer que las cards funcionen como en este video
  https://cleanshot.com/video/home/quickaccess.mp4". The post-capture card is the
  busiest moment in the product and should behave like a command surface rather than
  a notice.

- **S2** The card's existing guarantees survive untouched: the pin, the dismiss
  rules, the cursor ownership arbitration, and the fact that the card is not what
  commits the capture.

- **S3** Scope, decided here because the reference could not be studied (the video
  endpoints only yield frames for YouTube and local files): the card gets an explicit
  row of actions — copy, save, annotate, pin, discard — plus drag-out of the image to
  another app. Nothing CleanShot-specific is invented; every action maps to
  something the app already does.

## Tasks

| ID | Specs | Task | Route | Commit |
| --- | --- | --- | --- | --- |
| T1 | S1-S3 | The action row and the drag-out, with the existing guarantees intact | worker | uncommitted |
| T2 | S1-S3 | Docs: CHANGELOG and this log | worker | |

## Log

- **L1** (owner, 2026-11-25, verbatim): "- puedes hacer que las cards funcionen como
  en este video https://cleanshot.com/video/home/quickaccess.mp4".
- **L2** (scope decision): the reference video was unreachable, so the work is scoped
  to the actions the app already owns plus drag-out, which is the part any user would
  name first if asked what a capture card is for. Anything beyond that waits for the
  video as a local file.
- **L3** (S1-S3, worker, 2026-11-25): the card is a small command surface. An action
  row (26 pt strip under the picture, centred, reading order copy → save → annotate →
  pin → discard, the destructive one at the right end away from where the hands
  start) and a drag-out. Each action routes through a path that already existed —
  no second road was built anywhere:
  - **copy** — `OverlayController.copy(_:to:)`, the capture tail's own pasteboard
    write (the one `deliver`, `deliverHistoryPick`'s clipboard branch and the
    capture's write-failure fallback all answer). New closure seam
    `CaptureCardController.onCopy`, wired in `wireEditor`.
  - **save** — `CaptureFile.write(_:preference:date:)`, the folder destination's
    writer `deliver` uses, preference read at action time. The failure rule is the
    delivery's own: nothing writable → the capture lands on the clipboard exactly
    as `deliver`'s non-folder/failure branches behave. It is NOT treated as a new
    capture — neither history gets an entry, because the capture was already
    delivered before the card existed and the card never re-commits (S2). A folder
    destination's re-save deliberately writes a second file with a fresh name.
  - **annotate** — the card's own `onOpen` → `openCaptureEditor`, the ONE editor
    handoff the click and the history pane's reopen already share (T3).
  - **pin** — the corner pin's own `togglePin` + `onPin` →
    `OverlayController.pinImage` → `PinnedImageCoordinator`; the row's pin is a
    second door into the SAME path, not a new one.
  - **discard** — the close's own `closeTapped` → `CaptureCardController.dismiss`.
  - **drag-out** — `mouseDragged` used to put the bare image (TIFF) on the drag
    pasteboard; it now offers an `NSFilePromiseProvider` in PNG, the file drag
    other apps read (Finder/Mail et al. read it as an `NSFilePromiseReceiver`).
    Taking the promise writes the capture through the capture file path's own
    encoder, `CaptureFile.data(for:format:)`, in the app's own naming idiom
    (`Stare-<date-at-time>.png` — the default template's `date/at/time` shape,
    rendered by a local formatter because the card cannot read the persisted
    template without receiving a preference it does not carry; nothing tokeny is
    invented). The promise's write runs serially off the main thread.
  - Where each lived, confirmed by test comparisons: the row's copy must produce
    the delivery path's exact bytes, and the row's save must produce
    `CaptureFile.data`'s exact bytes for the same pixels.
  - **Pins (re-derived, each with its canary):**
    - The corner pin and close controls were KEPT, and the row's pin/discard
      carry their own identifiers (`captureCard.rowPin` / `captureCard.rowDiscard`)
      instead of reusing the corner buttons'. The first draft shared the corner
      pin's identifier with the row's pin, which made "the pin button" ambiguous
      for identifier walks; the corner controls' placement guarantees (top-right,
      close last, never covered) are pinned by an existing test I must not edit
      (`PinnedImageWindowTests`), so they keep the original identifiers.
    - Click-to-open still fires on mouseDown, unchanged. Moving it to mouseUp
      would have made drag-out logically cleaner but breaks the press behaviour a
      test outside my surfaces pins; the drag still begins from the card's own
      press-and-drag (the real flow as shipped).
    - The row is a permanent strip, NOT a hover-reveal: the video was unreachable
      (L2) and the reveal choreography is the part of the reference I refused to
      invent. The card grows by the strip rather than overlaying the capture, so
      no capture pixel is ever hidden — a card whose picture hides itself while
      the pointer rests on it would be the reference's blind guess, not Stare's.
    - `CaptureCardView`'s dead private `copyToPasteboard()` was removed: it was a
      second pasteboard writer nobody could reach, exactly what S3 forbids.
    - **Canary — live drag sessions under xctest:** beginning a real
      `NSDraggingSession` in a test and letting the test tear the source window
      down crashed the whole test process (SIGSEGV inside `objc_release` during
      xctest's autorelease scope pop; reproduced five times, and a crash report
      of the same shape from 2026-11-21 shows the signature predates this work).
      Two things refused to fix it: a nested runloop drain inside a live session
      spun forever. The drag test therefore keeps the window ordered out and held
      strong until process end (one window per run, an honest deliberate hold),
      the session-begins test asserts only what the card owns (`lastDragSession`,
      the begin path), and the PROMISE payload is asserted off a custom
      `NSPasteboard` the test writes the provider onto — which is exactly what a
      drag session does for one item — read back through the receiving side
      (`NSFilePromiseReceiver`). The app keeps the real path; only the test's
      teardown jumped through the harness's hoop.
    - Landing's demo port (`landing/src/demo/card.ts`) mirrors
      `CaptureCardView.preferredSize` and the dismiss policy: the strip changes
      the card's height there too. NOT this worker's surface — the landing
      session must re-port `rowStripHeight` into `demo/card.ts`, or the demo and
      the app drift.
  - **Refused to invent:** hover-reveal choreography (L2), a save-panel replica
    of the editor's (`saveFromCard` routes through the one file writer instead),
    per-action feedback pills on the card (hints remain the capture tail's), a
    share menu, copy-filename, keyboard shortcuts on the row, and dragging from
    the row's buttons (button presses are consumed by the controls).
  - **Verification:** `swift test --filter CaptureCard` (the actions, the cursor
    routing and the existing card tests): 23 tests, 0 failures, exit 0 — 10 new
    action/drag tests, all prior card tests passing. Full suite, unpiped:
    `swift test > .build/w20.log 2>&1; echo EXIT=$?` → EXIT=0,
    `Executed 916 tests, with 0 failures` (StareCoreTests, baseline unchanged) and
    `Executed 428 tests, with 0 failures` (StareTests; baseline 412 + this task's
    10 new tests in `CaptureCardActionsTests`; the remaining 6 are the concurrent
    filename-card worker's, not this task's). One anomaly recorded honestly: in one focused run
    `testTheRowAnnotateSharesTheClickOpenHandoff` reported 559 s inside the batch
    (2 s standalone; the machine carried leftover xctest processes killed by hand
    at the time) — the repeat runs and the full suite are all fast.
- **L4** (S4, worker, 2026-11-25): the owner used the card and said the row
  repeated the top-right controls; the row goes, the four commands become one
  control per corner, annotate becomes the click on the picture, the drag
  stays, and the borders quiet down. What changed and what it was drawn where:
  - **The corner layout** — copy top-left, save bottom-left, pin top-right,
    discard bottom-right (mirrored columns, the owner's reading order;
    destructive at the bottom). The pin keeps the top-right corner it has
    always held *because it must*: `PinnedImageWindowTests`
    (outside this task's surfaces, not edited) pins the corner pin's
    placement and its uncovered click area to that corner, so the mapping
    grew around it. Every control still routes through the path that already
    existed — `OverlayController.copy(_:to:)`, `saveFromCard` (→
    `CaptureFile.write`), the shared pin door, `dismiss` — nothing new was
    built. Save still never writes a second history entry (unchanged rule,
    unchanged test).
  - **Annotate on the picture** — the old `annotateTapped` and the row
    button are gone; `mouseDown` → `onOpen` already WAS the click-open and
    still fires on mouse-down (the rule a test outside this file pins), and
    the drag that begins from the same press still starts in `mouseDragged`
    unchanged (proven by the drag tests, not assumed).
  - **The card carries no plate any more**: `preferredSize` is now the
    aspect-held thumbnail widened only to
    `max(_, minimumContentWidth=132)` / raised only to
    `max(_, minimumContentHeight=56)` so the corner controls keep their
    click areas; the picture fills `bounds`, clipped to the plate's 10 pt
    rounding.
  - **Where the borders were drawn and what they measure now** — both lived
    in `CaptureCardView.draw(_:)`. The BLACK border was not a stroke: it was
    the dark plate itself, a fill of `CGColor(gray: 0.08, alpha: 0.92)` over
    the card inset 1 pt behind the 6 pt-inset thumbnail — a capture inside a
    near-black frame, plus the 1 pt hairline separator that drew the row's
    top edge under the picture. Both are gone. The PINNED border was a 2 pt stroke of
    `CGColor(red: 0.36, green: 0.66, blue: 1, alpha: 0.95)`; it is now a
    1 pt stroke of the same hue at alpha 0.45, inset half a width so the
    line sits inside the layer's rounded clip. Measured by rendering the
    card's `draw` into a 4× bitmap and sampling: un-pinned, 0.5 pt / 2 pt /
    5 pt inside both horizontal edges are the capture's own colour (the old
    render's dark plate sat 1.30–1.47 colour distance away at the same
    depths); pinned, the rim's red channel reads above 0.5, while the old
    0.95-weight blend sampled 0.426 red at the same depth, and 1.5 pt inside
    is bare capture again, where the old 2 pt stroke still painted solid
    blue (0.537 colour distance from the fixture).
  - **Pins re-derived** (S4 withdrew every command whose stated meaning
    was the row): the row's own pins died with it — `captureCard.rowPin`,
    `captureCard.rowDiscard`, `captureCard.annotate`, `rowButtonSide`,
    `rowSpacing`, `rowStripHeight`, `annotateTapped` and
    `CaptureCardControlButton`'s smaller `side` parameter all removed, and
    the test-side pins on them (`rowVoice`, `rowButtonsMinY`, the strip's
    aspect math in `CaptureCardTests` — re-derived to the picture-fills-the
    -card rule) went with the row. Kept: `captureCard.pin` / `captureCard.close`
    / `copy` / `save` identifiers (the corner controls' originals), the
    drag canary (L3), the dismiss policy, the cursor ownership, the stack
    rules. New pixel pins carry no constant dependency: the border tests
    measure the render, so the constants cannot drift from the pixels.
  - **Refused to invent:** any hover choreography, per-corner different
    disc styles, keeping `thumbnailCornerRadius` (dead once the picture
    takes the plate's rounding).
  - **Verification (exit 0 everywhere, unpiped for the full suite):**
    - RED before implementation: `swift test --filter
      "CaptureCardTests|CaptureCardActionsTests" > .build/w24-red.log
      2>&1; echo EXIT=$?` → EXIT=1, `Executed 21 tests, with 16 failures`
      — exactly the intended new-behaviour failures (corner voices);
      border pixels; pinned subtlety; plate aspect). All prior card tests
      already green (copy bytes, save bytes + fallback, discard-close path,
      pin state, click-open, both drag tests, cursor).
    - GREEN: same filter → EXIT=0, `Executed 21 tests, with 0 failures`;
      neighbours `--filter "CaptureCard|CardCursor|PinnedImage"` → EXIT=0,
      `Executed 46 tests, with 0 failures` (includes
      `PinnedImageWindowTests`, which still holds the corner pin
      guarantee).
    - Full suite: `swift test > .build/w24.log 2>&1; echo EXIT=$?` → EXIT=0,
      `Executed 919 tests, with 0 failures` (StareCoreTests, baseline
      unchanged) and `Executed 431 tests, with 0 failures` (StareTests;
      baseline 429 + this task's 2 net new: the two border-render tests).
  - **Landing's demo port** (`landing/src/demo/card.ts`) mirrors the card's
    size and dismissal: the strip AND the plate are gone from the app now,
    so the demo must re-port `preferredSize` and the drawing. NOT this
    worker's surface — the landing session must re-port it or the demo
    drifts.
- **L6** (test-suite health, owner: "optimiza los test puede que haya cosas obsoletas o que se estan
  haciendo dobles ... haz que este proceso este optimizado"): the suite took **977 s** and the stall was not
  slowness but a poisoned process. One test began a real `NSDraggingSession`, which never ends in xctest: it
  keeps the GENERAL pasteboard claimed by a file promise nobody requests, and every later read of that board
  waits for it. Measured in that order — the copy test alone **0.2 s**, after the drag test **94 s**, inside
  the whole bundle **932 s**. The fix is three things: the controller owns ONE pasteboard seam (`var pasteboard:
  NSPasteboard = .general`) so a test can point both production writers at a board no drag owns and still
  compare them; the drag test that started a session is retired with the reason written in its place, since the
  behaviour that matters — the card offers its capture as a file promise, named in the app's idiom and written
  through its own encoder — is proven by the test that starts no session; and `setUp` releases the general
  board so nothing is inherited. **Also removed: instrumentation two cancelled workers left behind** —
  `COPYSTAMP` prints inside the production copy path, `CLICKSTAMP` inside the card's copy control, and a test
  that stamped every line it ran. After: whole suite **99.6 s**, 920 StareCoreTests + 439 StareTests, 0
  failures, slowest single test 5.7 s.
