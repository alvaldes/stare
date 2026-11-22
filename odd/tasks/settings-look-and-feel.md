# Settings look and feel

Rework the Settings window: regroup 31 settings into a natural map, stop wasting space, and keep every live
preview in view while the user edits. Branch `feat/settings-look-and-feel` in worktree
`/Users/alvaldes/Developer/github.com/alvaldes/stare-settings`, off `main` at 3378d5c. `main` keeps working.

## Specs

- **S1** The work happens in its own worktree, off `main`: "vamos a trabajar en otro worktree". Nothing in
  `main`'s working tree is touched; the branch is rebased onto `main` once `main`'s in-flight work lands.
- **S2** Reorganise the settings now that there are many more of them: "Una reorganizacion de settings tiene
  sentido ahora que tenemos muchas mas configuraciones."
- **S3** "Haz que se sienta natural y optimiza los espacios."
- **S4** "los previews no deben estal al fondo porque sino no se ven los cambios que se estan haciendo."
- **S5** "En lo que termina el trabajo que se esta haciendo en main": settings edits in flight on `main`
  (`Sources/Stare/SettingsView.swift`, `Sources/StareCore/GeneralPreferences.swift`) must not be duplicated or
  reverted by this branch.

## Tasks

| ID | Specs | Task | Route | Commit |
| --- | --- | --- | --- | --- |
| T1 | S2,S3,S4 | Three design directions in `design/settings-look-and-feel/`, same grouped sidebar, three preview strategies | inline (parent) | eb14d5c |
| T2 | S3 | Pick one direction with the human — 02, stage-first band | human decision | eb14d5c |
| T3 | S2 | Regroup the sidebar into 6 groups / 10 panes; move Bar, Overlay and Laser out of General | inline + worker | eb14d5c |
| T4 | S4 | Apply the chosen preview placement; the pointer preview and the bar now live in a pinned stage | inline + worker | eb14d5c |
| T5 | S3 | Density and space pass: two columns above 660 pt, 700 pt cap on single columns, switches, tighter cards | inline + worker | eb14d5c |
| T6 | S1,S5 | Self-test coverage for every pane (light + dark), `SettingsAreaTests`, CHANGELOG | inline | eb14d5c |

**Slice note.** The rework is one commit, 2239 authored lines — past the ~400-line slice. It is
atomic by nature: the shell (no longer a ScrollView owner), its components and all ten panes change
together, so any smaller slice would not compile. Delivery shape when publishing: this is a single-PR
size, so prefer `chained-pr` split by pane group (components + shell + IA first, then the panes) if
the user asks to publish.

## Log

- **L1** (user, verbatim): "En lo que termina el trabajo que se esta haciendo en main vamos a trabajar en otro
  worktree para mejorar el look and feel the settings. Una reorganizacion de settings tiene sentido ahora que
  tenemos muchas mas configuraciones. Haz que se sienta natural y optimiza los espacios. Un detalle es que los
  previews no deben estal al fondo porque sino no se ven los cambios que se estan haciendo."
- **L2** (evidence): worktree created at `../stare-settings` from `main` 3378d5c; `main` had 5 modified files
  in flight, 2 of them settings files (S5 risk).
- **L4** (decision): three design directions written to `design/settings-look-and-feel/` — 01 pinned preview rail,
  02 stage-first band, 03 promoted preview column. All three share one grouped sidebar (Capture / Draw / Pointer /
  Board / System, ten panes) and show the Pointer Highlight pane, the worst case for S4. Waiting on T2.
- **L5** (decision, user): direction 02, stage-first band. The preview is a pinned stage above the scrolling cards,
  and the cards below use two columns above 660 pt of width.
- **L6** (evidence, first render): the real `ToolbarView` (12 tools + ink swatches) is wider than the 766 pt stage,
  so it pushed the whole Bar pane past the frame and cut the Placement pickers. The stage now scrolls on the bar's
  own axis; the pane keeps its width and every drop target stays reachable.
- **L7** (evidence, first render): two-column rows wrapped to three and four lines because each control was pinned at
  180 pt next to a long `detail`. Controls dropped to 130 pt in the pointer pane and three details were trimmed.
  Toggles also rendered as plain checkboxes; both scaffolds now set `.toggleStyle(.switch)`.
- **L8** (decision): window default 880×560 → 1000×660, minimum 720×480 → 860×560, so the two-column layout has
  room and folds to one column below it.
- **L9** (evidence): committed as `eb14d5c`. While the branch was open, `main` advanced to `d92edfe` with
  `de9f2a3 fix(settings): apply a drop on the main actor` — a fix inside the organiser drop path this branch
  moves. Rebased onto `d92edfe` with no conflicts; the hop survived the move (`ToolbarOrganiserHooks.deliverPayload`
  with its `@MainActor` closure, no removals in `git diff main`), which is the S5 check.
- **L10** (evidence): `swift test` 527 tests green after the rebase and the settings selftest `exit=0` with
  `settings panes result=PASS areas=10` in light and dark plus `settings window result=PASS`; the rendered
  fixtures under `/tmp/stare-settings-*.png` are what caught the bar overflow and the wrapped rows.
- **L11** (evidence): native review `review-7a1434a8db877d90` on `d92edfe..HEAD` approved, authority burned.
  Five advisory findings, all non-blocking, and what happened to each:
  - `R2-design-json-size-mismatch` — declined: `design.json` records the artboard viewport (1056×744 = label row
    + the 1000×660 window + margins). The window inside is 1000×660 on purpose, which is the size L8 chose.
  - `R2-magic-control-widths` — accepted as later work: 220/180/140/130 should become `SettingsMetrics` tokens.
  - `R2-stray-section-close` — fixed: a duplicate `</section>` in the chosen artboard (4 open / 4 close now).
  - `R3-segmented-130-width` — checked in the render: "Scale | Rotate" fits at 130. The row that did overflow was
    the Colour picker, whose labels are now "Follow ink" / "Fixed".
  - `R3-singlecol-cap-bar` — fixed: BarPane's cards now take `.settingsSingleColumn()`.
- **L3** (evidence): current shell is sidebar (180 pt) + one scrolling pane, 8 areas, `minWidth 720 / minHeight
  480`, default 880×560. 31 editable values. Only two previews exist: the toolbar organiser preview (inside its
  card, above the pool) and `PointerPreviewView` (last card of Pointer Highlight, below all nine controls —
  the S4 defect).
