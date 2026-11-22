# Bar pane: the pool under the preview, and the organiser that works in place

The Settings Bar pane puts the bar on a stage and the pool in a card at the bottom of the pane. The user
wants the pool next to the bar, the preview to say what can leave it, and the bar to be rearranged
without taking every tool out and putting it back.

Branch `feat/bar-pane-organiser`, off `fix/bar-preview-and-cursors` at `b48b52a` (that branch's review
was approved and burned; it is not pushed yet, so this branch chains on it).

## Specs

- **S1** Move the pool so it sits directly under the bar preview:
  "sube el pool para que quede debajo del preview de la bar".
- **S2** The preview must show which items cannot be dragged out of the bar, and the first tool is one of
  them: "hay que diferenciar del preview lo que se puede sacar y lo que no, como el primer tool".
- **S3** Placed separators come off the bar like everything else:
  "los separadores tambien se pueden sacar".
- **S4** The label and note that stand to the left of the bar belong above it, so the bar gets the width:
  "el texto que esta a la izquierda del bar en el preview se puede poner arriba y asi puede ocupar mas
  espacio el bar".
- **S5** The bar rearranges in place; taking a tool out and putting it back is not the way to move it:
  "se debe de poder reorganizar el bar sin tener necesidad de sacar y meter tools".

## Diagnosis so far

- **S1** The pool is its own `SettingsCard(title: "In the pool")` in the Bar pane's card column, below the
  Placement card, while the bar is the pinned stage above them all.
- **S2/S3** Every bar item is wrapped by `organiserWrapped`, so every item is a drag source and a
  two-sided drop target with no distinction between what must stay and what may leave. A placed separator
  can only leave through the pool's dashed end zone (`ToolbarPoolEndDropDelegate`), because the pool chips
  accept tools only (`guard case .tool(let payload)`), and a bar-to-bar drag across a placed separator
  currently drops that separator (found while pinning T4/S4 of the previous batch) — the same normalisation
  that eats it is what makes in-place reordering unreliable.
- **S4** The stage is `SettingsStage`, whose lead column is `SettingsMetrics.stageLeadingColumn` (140 pt)
  beside the content; the fit factor subtracts `SettingsMetrics.stageChrome`, which includes that column,
  and two tests pin the equality (`Tests/StareTests/SettingsBarPreviewTests.swift`).

## Tasks

| ID | Specs | Task | Route | Commit |
| --- | --- | --- | --- | --- |
| T1 | S4 | Move the stage's label and note above the bar and give the bar the whole width: stage layout, the chrome token, the fit factor and the tests that pin them | worker | |
| T2 | S1 | Put the pool directly under the preview, and keep placement and the other cards below | worker | |
| T3 | S2 | Mark the items that cannot leave the bar, and make drag-out refuse on them instead of half working | worker | |
| T4 | S3 | Let a placed separator come off onto any pool target, not only the dashed end zone | worker | |
| T5 | S5 | Make bar-to-bar reordering work in place, including across a placed separator, without the round trip through the pool | worker | |

## Log

- **L1** (user, verbatim): the five bullets quoted in S1-S5, sent as one message after reviewing the
  previous batch in the installed app.
