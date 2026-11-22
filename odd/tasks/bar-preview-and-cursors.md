# Bar preview, sidebar focus, pool, gripper and bar cursor

Six defects reported against the merged Settings rework and the bar. Branch
`fix/bar-preview-and-cursors`, off `main` at `1bbff32` plus the uncommitted
picker-alignment fix.

## Specs

- **S1** The Settings bar preview must never render vertically, whatever the bar's orientation is:
  "en bar en vertical en el preview de settings se ve verical pero eso no debe ser, en el preview
  siempre haz que se vea horizontal para no romper nada."
- **S2** The bar preview must show the bar whole; today it is cut:
  "hay que analizar un poco mas esta ventana porque no se ve el bar por completo sino que se corta."
- **S3** The blue focus ring must not be on the selected sidebar item when Settings opens; it appears
  only once the user starts tabbing: "siempre se ve ese borde azul sobre el item captura de menu, ese
  focus no debe verse de primera, sino hasta que se aplique el primer tab".
- **S4** The bar/pool organiser must actually work in both directions, not just look like it does:
  "la opcion \"In the pool\" funciona porque no creo que lo haga".
- **S5** The gripper's dots must use the same colour as the other tools' glyphs, so it reads in the
  light theme too: "el gripper tiene un color que no es el mismo que los otros tools en el tema light
  y por eso se ve mal en fondos blancos del tema light".
- **S6** Hovering the bar must not keep the active tool's cursor; the bar owns its own cursor over
  its whole area, not only over the gripper: "lo del cursor encima del toolbar no funciona aun sigo
  viendo el mismo que tiene el tool. Solo funciona la mano agrarrando sobre el gripper".

## Diagnosis so far

- **S1/S2** `BarPane.toolbarStage` (`Sources/Stare/SettingsView.swift:615-642`) hosts the real
  `ToolbarView` inside a `ScrollView` whose axis follows `model.toolbarOrientation`, capped at
  `maxHeight: 240` when vertical, and `syncToolbarPreview()` copies the orientation into
  `toolbarPreviewState`. So a vertical bar renders vertical in the preview, and the bar — wider than
  the stage — is scrolled instead of shown whole.
- **S3** `sidebarButton(for:)` is a plain `Button` (`SettingsView.swift:211-247`); the window's first
  responder lands on it, so macOS draws the focus ring on the selected row before any keyboard use.
- **S5** The gripper draws its own dots in `ToolbarGripper.draw(_:)` (`Sources/Stare/ToolbarView.swift`,
  from line 128); every other item is an `Image(systemName:)` with `foregroundStyle`, so the two colour
  sources have to be reconciled in light and dark.
- **S6** The gripper alone installs cursor rectangles and a `cursorUpdate` (`ToolbarView.swift:98-126`),
  and `frameInWindow` exists only for the gripper. The bar's other items have no cursor of their own,
  so whatever the overlay sets for the active tool wins over the whole bar.

## Tasks

| ID | Specs | Task | Route | Commit |
| --- | --- | --- | --- | --- |
| T1 | S1 | Render the preview horizontal always: pin `toolbarPreviewState.toolbarOrientation`, drop the orientation-driven scroller axis | inline (parent) | 86e6b14 |
| T2 | S2 | Fit the whole bar in the stage (scale to the stage width instead of scrolling) and re-render the fixtures | inline (parent) | 86e6b14 |
| T3 | S3 | Focus ring only after the first Tab: suppress the effect until keyboard navigation starts | inline (parent) | b7fc4c7 |
| T4 | S4 | Verify the organiser in both directions (bar→pool and pool→bar) and fix what does not land | worker | cc82031 |
| T5 | S5 | Give the gripper the same colour source as the other tool glyphs | worker | 4479402 |
| T6 | S6 | Make the bar own its cursor over its whole area, not just the gripper | worker | 4479402 |

**Slice note.** 3035 authored changed lines over nine commits once T4 lands — past the ~400-line
slice, and the units are independent by nature. Delivery shape when publishing: a chained PR, one
slice per concern (preview fit; focus ring; bar colour and cursor; organiser tests), never one diff.

## Log

- **L1** (user, verbatim): the six bullets quoted in S1-S6.
- **L2** (evidence): carried into this branch is the previous, installed, uncommitted fix
  `Sources/Stare/SettingsView.swift` + `SettingsComponents.swift` (pickers anchored trailing). It is
  not part of this feature's commits.
- **L3** (evidence): `SettingsView.swift:615-642` is the stage; `621` chooses the scroller axis from the
  model, `622-632` host the real bar, `636` caps the vertical case at 240 pt.
- **L4** (evidence, T1/T2): the preview's orientation has exactly one write site now
  (`toolbarPreviewState.toolbarOrientation = .horizontal`), so the model can no longer reach it. The
  scroller is gone: the bar measures itself and is scaled to `cardsWidth - SettingsMetrics.stageChrome`,
  the stage's lead column, spacing and padding having become tokens so the fit factor subtracts exactly
  that chrome. Fixture `stare-settings-bar-light.png`: the eight ink swatches, undo/redo/clear/close and
  the gripper are all inside the stage box instead of scrolled out of sight. 86e6b14.
- **L5** (evidence, T3): the sidebar suppresses its focus effect until a local key monitor sees a Tab
  (keyCode 48); the monitor is removed with the window. The ring is a live-window behaviour, so the commit
  pins the mechanism, not a pixel: b7fc4c7.
- **L6** (evidence, T5): the gripper drew its dots in AppKit, where the bar's `ultraThinMaterial` never
  reaches the fill, so they held one grey while the SF Symbol glyphs tracked the appearance — measured
  128 vs 121 in light and 124 vs 155 in dark. The dots are SwiftUI shapes on `.secondary` now and measure
  identical in both. 4479402.
- **L7** (evidence, T6): a panel that can never become key has its cursor rectangles ignored, and the
  hosting view's `cursorUpdate` only ever won over the gripper — which is why the hand was the only bar
  cursor that worked. `OverlayController` now watches the pointer while the bar is on screen and answers
  through `ToolbarGripperView.barCursor`: hand pair over the gripper, arrow over the rest. Live hover is
  not headlessly testable; the arbitration is pinned point-by-point. 4479402.
- **L8** (evidence, T4): no defect reproduced. All three delegated directions already write the one
  `model.toolbarTools` draft, and nine new tests now drive the real `BarPane` handlers on a real
  `PreferencesModel` (the pane and its handlers lost `private`, behaviour unchanged). Two findings came
  back for the parent: (a) on a fresh install every tool sits on the bar, so "In the pool" shows only the
  Separator chip and the dashed zone — it looks inert until something has been pooled, which is the most
  likely cause of the doubt; (b) a bar→bar drag across a placed separator drops the separator even though
  `[eraser, sep, pen]` was reachable, which needs separator relocation inside `GeneralPreferences` and is
  outside this batch. cc82031.
- **L9** (verification, whole batch): `swift build` exit 0; `swift test` exit 0 with `StareCoreTests`
  535 executed / 0 failures and `StareTests` 98 executed / 0 failures (633 total, 9 of them new);
  `./.build/debug/Stare --selftest` exit 0 with zero `result=FAIL` lines, `settings panes result=PASS
  areas=10` and `settings window result=PASS`. Two behaviours stay manual by nature and are handed to the
  reviewer: the sidebar focus ring (a live window's first responder) and the pointer over the bar (an
  AppKit panel hover).
