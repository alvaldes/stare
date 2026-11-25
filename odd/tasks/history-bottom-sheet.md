# B3: the capture history as a full-width panel that slides up

The owner's item from the 2026-11-25 backlog list, with a CleanShot X reference
image.

## Specs

- **S1** (verbatim): "el historial debe verse como un panel del ancho de la
  pantalle que sale desde abajo y ocupa una altura fija como aqui
  https://cleanshot.com/_ipx/f_avif&q_70&s_1360x960/img/screenshots/history.png".
  The history is a sheet the width of the display, anchored to the bottom edge,
  at a height that does not depend on how many captures it holds — a shelf, not a
  window the user has to place and size.

- **S2** The store, the entries and every action the panel offers today survive:
  the panel is re-shaped, not re-invented. Nothing that works now may be lost in
  the move.

- **S3** The existing `⌥⇧I` shortcut, the persisted store and the Clear action keep
  their behaviour; the new shape changes where the panel is, not what it does.

## Tasks

| ID | Specs | Task | Route | Commit |
| --- | --- | --- | --- | --- |
| T1 | S1-S3 | The history as a bottom sheet: full width, fixed height, animated in | worker | 1fa620e |
| T2 | S1-S3 | Docs: README, CHANGELOG and this log | worker | |

## Log

- **L1** (owner, 2026-11-25, verbatim): "- el historial debe verse como un panel del
  ancho de la pantalle que sale desde abajo y ocupa una altura fija como aqui
  https://cleanshot.com/_ipx/f_avif&q_70&s_1360x960/img/screenshots/history.png".
- **L2** (S1-S3, worker, 2026-11-25): the capture history reshaped into a
  full-width bottom sheet; every prior behaviour survived verbatim and the
  keyboard map is untouched.
  - **Geometry rule**: the sheet spans `screen.visibleFrame`'s full width,
    flush to its bottom edge, at `0.42 × visibleFrame.height`, floored at one
    card row plus the header (`minimumShelfHeight(thumbnailSize:)` =
    `t + 92`: one aspect-fit row t + 28, header 38, spacing 10, bottom 16);
    never above the visible height. Measured frame on the reference
    1440-tall display (visible 1416): `(0.0, 0.0, 1440.0, 594.72)`. Screen
    choice unchanged: the one under the pointer. The sheet is a slab rising
    off the bottom edge: `UnevenRoundedRectangle` — round TOP corners only
    (16 pt), window stays rectangular.
  - **Reference (CleanShot composite) — what was copied and what was
    refused**. Copied: full-bleed width, fixed-height bottom shelf, airy
    padding (16 pt), frosted `.regularMaterial`, generous card radius (10 pt
    thumbnail / 12 pt ring), the accent selection ring (the system accent
    `CaptureHistoryCell` already used, not their brand blue). Refused: the
    `All / Screenshots / Videos / GIFs` tabs (Stare's store holds only
    captures — nothing to filter), the verb "Restore" (the pick keeps its
    paste/route semantics), their metadata-less cell (S2 keeps the date +
    pixel-size line), and the single-row-that-overflows-vertically
    composition — the decision kept the wrapping adaptive grid with more
    columns, because S2's row-wise ↑/↓ and the scroll semantics are exactly
    what must keep working (see “A full-width grid simply gets more
    columns”); no contextual action under the selection was built — the
    return key IS the action today.
  - **Animation shape** (net-new: the repo had no window animation): slide
    up from just below the bottom edge, 0.22 s ease-out, order-front at the
    start frame, `makeKey` + `makeFirstResponder(hostingView)` + monitor
    install AT THE END of the open; close slides down 0.18 s ease-in and
    calls `orderOut` then `onHidden?()` exactly once after the exit — the
    exit already has its monitors off and a second `hide()` mid-exit is
    absorbed. `sizingOptions` stay `[]` and the content view autoresizes, so
    SwiftUI cannot resize the window mid-slide. The slide runs only under
    `app.run()` (`NSApp.isRunning`): `NSAnimationContext`'s completion runs
    on the main run loop, which `swift test`/`--selftest` never spin, so
    headless runs take the pre-B3 synchronous order (place → front → key →
    first responder → monitors) and every pinned behaviour is frame- and
    hook-exact. The feel — the slide itself — is the owner's check: what the
    headless run can prove is the frames, the key/first-responder order and
    the once-per-close hook, not the pixels in motion.
  - **Two re-derived pins**: (1) placement — the old “centres on the pointer's
    screen” is now “spans the pointer's screen's visible frame, flush to its
    bottom” (`testTheOpenSheetSpansTheVisibleFrameOfTheScreenUnderThePointerFlushToItsBottom`);
    the screen-under-the-pointer choice itself never changed. (2) the
    outside-click rule's second clause — `hides(forClickOnPanelWindow:insidePanelFrame:)`
    is unchanged code; its MEANING moved with the shape, so it is pinned as
    “a click anywhere in the full-width bottom strip keeps the sheet open”
    over four real strip points (`testAClickAnywhereInTheBottomStripKeepsTheSheetOpen`).
  - **Net-new behaviour**: a re-place on screen-configuration or Space change
    while the sheet is visible — `repositionIfVisible()`, called first from
    `OverlayController.screenParametersChanged`/`activeSpaceChanged` (now
    internal for the tests), before their pre-existing early return; never
    shows a hidden sheet, never animated.
  - **Verification** (all unpiped, `swift test > .build/w16-*.log 2>&1`):
    RED `swift test --filter CaptureHistory…` → EXIT=1, build failed exactly
    on the missing new API (`sheetFrame`, the geometry constants, the then
    private observers). Focused GREEN after the fix cycle (one correction:
    the tests' own flush-edge assertions were labelled against macOS y-up
    coordinates, and the arrow walks pinned their grid to one column
    deliberately instead of leaning on the old panel's never-measured
    `columnCount == 1`) → EXIT=0, 28 tests, 0 failures. Full suite →
    EXIT=0: StareTests **392** (387 baseline + 5 net-new), StareCoreTests
    **902**, 0 failures.
