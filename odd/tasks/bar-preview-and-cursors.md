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
| T1 | S1 | Render the preview horizontal always: pin `toolbarPreviewState.toolbarOrientation`, drop the orientation-driven scroller axis | inline (parent) | |
| T2 | S2 | Fit the whole bar in the stage (scale to the stage width instead of scrolling) and re-render the fixtures | inline (parent) | |
| T3 | S3 | Focus ring only after the first Tab: suppress the effect until keyboard navigation starts | inline (parent) | |
| T4 | S4 | Verify the organiser in both directions (bar→pool and pool→bar) and fix what does not land | worker | |
| T5 | S5 | Give the gripper the same colour source as the other tool glyphs | worker | |
| T6 | S6 | Make the bar own its cursor over its whole area, not just the gripper | inline (parent) | |

## Log

- **L1** (user, verbatim): the six bullets quoted in S1-S6.
- **L2** (evidence): carried into this branch is the previous, installed, uncommitted fix
  `Sources/Stare/SettingsView.swift` + `SettingsComponents.swift` (pickers anchored trailing). It is
  not part of this feature's commits.
- **L3** (evidence): `SettingsView.swift:615-642` is the stage; `621` chooses the scroller axis from the
  model, `622-632` host the real bar, `636` caps the vertical case at 240 pt.
