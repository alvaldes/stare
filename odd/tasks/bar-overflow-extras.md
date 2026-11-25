# Bar overflow: the `⁞` that holds the extras, and the pool as the bar's hidden section

Worktree `stare-wt-bar-extras`, branch `feat/bar-overflow-extras`, off `main` at `60189f6`, so the
capture-history work in the main worktree is never touched. The bar carries too many tools for a vertical
dock; the extras move behind a `⁞`, and the Settings pool becomes the place those extras actually live.

Bring `main` in as it advances (`git merge main`) so the merge at the end stays small.

## Specs

- **S1** The bar gets a `⁞` for the tools that are not the main ones, so it stops growing:
  "En el bar ya hay muchas cosas y esto hace que sea demasiado grande sobre todo para vertical y para eso
  entre las cosas que podemos hacer es poner unos '⁞' para tools extras como el spotlight y algun otro que
  no sea los principales."
- **S2** The pool is not a graveyard: it is the bar's hidden section, reached from the `⁞`, organised the
  way Bartender organises its menu bar — one ordered strip, a divider you drag, and what falls past the
  divider still reachable from the icon:
  "Para el pool recuerda la idea que teniamos y usa lo que bartender puede ofrecer porque ellos ya pensaron
  en como hacer que su UX/UI fuera la optima."
- **S3** On a fresh install the visible bar holds the drawing tools — pen, highlighter, arrow, rectangle,
  ellipse, text, eraser — and the extras behind the `⁞` are line, number, blur, spotlight and laser
  (owner's choice, see L3). Every tool stays movable between the two sections.
- **S4** The Settings pool stops being inert: it always lists the tools behind the `⁞`, in their order,
  says what it is, and never collapses to a lone separator chip on a fresh install:
  "mejorar la experiencia de la pool ... en settings".
- **S5** The Settings preview shows the real bar, `⁞` included, in the current orientation and without
  scrolling, and it shows what is behind the `⁞` when you open it there:
  "mejorar la experiencia de ... el prevview en settings".
- **S6** A tool behind the `⁞` keeps its key: pressing the spotlight's key selects the spotlight whether it
  sits on the bar or behind the `⁞`, and the bar shows that it is the active tool.

## Tasks

| ID | Specs | Task | Route | Commit |
| --- | --- | --- | --- | --- |
| T1 | S1-S3 | Model: the shipped bar keeps the drawing tools, the pool holds the extras, an uncustomised saved bar upgrades | inline (parent) | 2d5138d |
| T2 | S1, S6 | The `⁞` on the real bar: the control, the extras column/row, the collapse, the active-tool symbol | inline (parent) | 2d5138d |
| T3 | S4 | The Settings pool as the bar's hidden section: titled, worded, never inert | worker | ed576a5 |
| T4 | S5 | The Settings preview shows the `⁞` and the draft's hidden tools | worker | ed576a5 |
| T5 | S1-S6 | Docs: README, CHANGELOG, and this log | inline (parent) | d7b31f6 |

**Slice note.** The `20570 authored changed lines in 96 commits since origin/main` the commit hook reports is the
unpublished `main` history this branch sits on, not this batch: T1+T2 are ~250 authored lines across six
files. Delivery shape when publishing stays the owner's call, and `main` is merged in whenever it moves.

## Log

- **L1** (user, verbatim): "En el bar ya hay muchas cosas y esto hace que sea demasiado grande sobre todo
  para vertical y para eso entre las cosas que podemos hacer es poner unos '⁞' para tools extras como el
  spotlight y algun otro que no sea los principales. Esto junto con mejorar la experiencia de la pool y el
  prevview en settings va a ser lo que vas a trabajar en un worktree separado para no interferir en main.
  Siempre que puedas traete los cambios para que al momento del merge sean menos los conflictos. Para el
  pool recuerda la idea que teniamos y usa lo que bartender puede ofrecer porque ellos ya pensaron en como
  hacer que su UX/UI fuera la optima."
- **L2** (decision, S2): the pool is the bar's hidden section, not a separate "removed" bucket — a tool is
  either on the bar or behind the `⁞`, never nowhere. Bartender's own model: one strip, one divider, the
  hidden run behind the icon.
- **L3** (decision, S3): visible by default = pen, highlighter, arrow, rectangle, ellipse, text, eraser;
  behind the `⁞` = line, number, blur, spotlight, laser. Reversible from Settings.
- **L4** (process): work happens in `stare-wt-bar-extras`; the main worktree's uncommitted capture-history
  changes are left alone, and this branch merges `main` whenever it moves.
- **L5** (evidence, session start): the repo has no earlier written record of "the pool idea" — `odd/tasks/`
  mentions the pool only as the organiser's off-bar bucket (`v0.5.md` S5/L7, `bar-pane-organiser.md`), and
  that same round recorded the symptom this batch fixes: on a fresh install every tool sits on the bar, so
  the pool shows only the Separator chip and looks inert (`bar-preview-and-cursors.md` L-note).
- **L6** (design, T1/T2): the model stays two runs — `items` on the bar, `pool` behind the `⁞` — instead of
  collapsing into one list plus a divider index. The pool already normalises, orders and round-trips, and
  every organiser rule and its fuzz test survive untouched; only the shipped default and the meaning of
  the second run change. The `⁞` closes the tool run; the extras open as a second column of the same pill
  (a second row when the bar lies flat), never as a popover — `ToolbarPanel.canBecomeKey` is false, so a
  popover over the bar cannot work, and a second window would need its own placement model.
- **L7** (evidence, T1/T2): 848 `StareCoreTests` + 285 `StareTests`, 0 failures, exit 0 — run as
  `swift test --skip CardCursorRoutingTests` because that class segfaults (see L8). Rendered the real bar to
  `/tmp` at both orientations and read the PNGs: vertical closed 44×742, vertical holding every tool 44×810,
  vertical open 100×742, horizontal closed 748×42, horizontal open 748×96. The open state was rendered by
  temporarily flipping the `@State` default and reverted before the commit; the scratch test was deleted.
- **L8** (defect found, not mine): `StareTests.CardCursorRoutingTests` dies with signal 11 in the app test
  bundle, and it does so on `60189f6` too — verified in a throwaway detached worktree of the baseline, so
  the crash predates this branch. It is the reason a plain `swift test` exits 1 here; the suite is verified
  with that class skipped. Out of scope for this batch: it belongs to the cursor batch that landed on
  `main`, and it must be fixed before anything can claim a clean full suite.
- **L9** (honest numbers, S1): the shorter default only buys 68 pt in the vertical bar (742 against 810),
  because five tools leave the column but four separators and the `⁞` join it. The two structures that
  dominate the vertical bar now are the eight inks (224 pt) and the five-item tail (150 pt). Folding the
  inks into a two-column grid in the vertical bar is the next real cut; it is a visible change nobody asked
  for, so it is the owner's call and not part of this batch.
- **L10** (evidence, T3/T4): the pool card is `BarPane.poolCardTitle` / `poolCardSymbol` /
  `poolCardHelp` now — "Behind the ⁞", the control's own glyph, and a caption that says the tools are one
  click away while drawing, keep their shortcuts, and move by dragging either way. No organiser mechanic
  changed: chips in pool order, dashed end zone, Separator source chip, `canLeave`, the main-actor hop. The
  stage's bar is built by the `BarPane.previewToolbar` seam pinning `toolPool: model.toolbarTools.hiddenTools`,
  so the preview draws the draft's `⁞` and opens the draft's extras. Verified: 848 `StareCoreTests` + 288
  `StareTests`, 0 failures, exit 0 (`--skip CardCursorRoutingTests`, L8). The open-overflow preview test opens
  the real control with a synthetic press and reads the render — two saturated bands, the inks preserved at
  the minimum width, the extras' accent scaled by the same fit factor — no hard-coded pixels.
- **L11** (wording, T3): two strings still named the pool as a place to dump things —
  "Drop to pool" on the end zone and the stage's "Drag a tool out of the pool onto the bar". They read
  "Hide it here" and "Drag an item off the bar to hide it behind the ⁞" so the pane speaks one vocabulary;
  no test pinned either string.
- **L12** (review): native review `review-fb9d873ce481f600` approved and burned for `60189f6..def1993`,
  three lenses (risk, readability, reliability), five non-blocking findings: the data WARNING that mirrors the
  assess escalation (a rebuilt full bar is indistinguishable from an untouched one), the vertical open-overflow
  column having no executed assertion, the `⁞` accent conflating "extras open" with "hidden tool armed", and
  two naming ones (`ToolbarToolLayout.hiddenTools` against `ToolbarView.hiddenTools`; `overflowButton` deriving
  `marked` from a second copy of the predicate `ToolbarOverflowSpec.symbolName` already answers).
- **L13** (blocker found by the independent verifier, fixed): the upgrade decided on layout identity at EVERY
  decode, so the bar a user rebuilds by dragging the five extras back — byte-identical to the v0.5 shipped bar
  — was rewritten to the shipped default on the next launch. That contradicted S3's "every tool stays movable
  between the two sections", the README's "Settings decides what sits on the bar" and the round-trip invariant,
  and the layout fuzz never visited that one layout. RED observed first
  (`ToolbarOverflowMigrationTests.testAFullBarTheUserRebuiltSurvivesASave`), then fixed with a stored
  `version` — `ToolbarToolLayout.currentVersion = 2`, so a document this build wrote is never migrated again
  and only a version-less blob (the v0.5 and v0.4 shapes) goes through the upgrade — plus
  `legacyStandardIdentifiers` pinned as a literal so adding or regrouping a tool later cannot silently stop
  the migration. Six new tests, including "the upgrade moves the bar and nothing else in the stored blob" and
  "a rearranged full bar is left exactly as saved". Verified after the fix: 854 `StareCoreTests` + 288
  `StareTests`, 0 failures, exit 0 (`--skip CardCursorRoutingTests`, L8).
- **L14** (follow-ups this batch does not take): R3-002 — the open overflow's vertical column has render
  evidence (L7) and the horizontal case has an executed pixel test, but no assertion pins the vertical one;
  a measurement test would need a seam that only exists for tests, so it stays a recorded gap. R3-003 and the
  two readability findings are cosmetic. `SelfTest` was not run by the verifier (it needs a live session).
- **L15** (review, second round): native review `review-1ee20395d7ecf028` approved and burned for the corrected
  candidate (`60189f6..9a56b71`, lenses risk + reliability). Four non-blocking findings, two of them new: the
  version guard read an unreadable version as 0 (`try? … ?? 0`, so a garbled field re-ran the upgrade), and the
  open-overflow assertion covered only the horizontal preview.
- **L16** (re-verification, then fix): the independent verifier closed the blocker through the REAL persistence
  path, not just the codec — a version-less v0.5 blob seeded into `UserDefaultsPreferenceStore`, migrated, the
  full bar rebuilt with the organiser's own drops, then three further launches returning exactly that bar — and
  proved sensitivity by running the same probe on `def1993`, where it failed. It also left one advisory: the
  v0.4 `tools`/`hidden` branch ignored `version` entirely. Both that and the review's garbled-version hole are
  the same defect class, so they were fixed together: a document migrates only when it carries **no** version
  at all, a readable older version still upgrades, and anything this build cannot read is treated as current
  and left exactly as stored (`mayMigrate`). RED observed on the two new pins against `9a56b71`, GREEN after
  (`ToolbarOverflowMigrationTests` 8/8). Suite: **856 `StareCoreTests` + 288 `StareTests`, 0 failures,
  exit 0**.
- **L17** (review, third round, closing): native review `review-03e559230787d0bb` approved and burned for
  `60189f6..9efcbbd`. Five non-blocking findings, none new: the one-time upgrade still maps a version-less blob
  that normalises to the v0.5 bar onto the shipped one (intended, bounded, L13), a v0.5 save that happens to be
  identical to the old shipped bar cannot be told apart from an untouched one (inherent to a version-less
  legacy shape), the vertical open-overflow column still has no executed assertion, and the two cosmetic ones
  (the pixel heuristic that locates the `\u2049`, and the control's accent conflating "open" with "a hidden tool
  armed").
  **Accepted gap, on the record:** the open-overflow render test lives on the Settings preview, whose stage is
  pinned to the horizontal bar by design (v0.5: a vertical bar distorted the pane), so the vertical open column
  has render evidence (L7) but no assertion. Closing it needs a seam that exists only to open a private view
  state (or a pixel-aimed synthetic click on the real bar); the layout is cosmetic and reversible, three
  reviewers named it non-blocking, and the honest line is to leave it recorded rather than grow the view for
  the test.
