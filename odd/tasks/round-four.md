# Round four: what the third pass left broken or unfinished

## Specs

- **S1** (verbatim): "cualquier haccion sobre el menu en el historial debe hace que se cierre el historial".
  Acting on a history menu item closes the sheet.

- **S2** (verbatim): "en el editor 'v' al movel se muevel el marco azul y despues la marca". Dragging with
  the select tool must move the mark itself; today the selection frame moves first and the mark follows.

- **S3** (verbatim): "en el editor 'b' no pinta pero en dibujo si funciona el pixelado". The blur tool paints
  in the drawing overlay and still does not in the editor.

- **S4** (verbatim, with a screenshot): "sigue igual" — in the editor's palette the spotlight's cell is ~400 pt
  wide where its neighbours are ~28 pt, because the wrapper that carries its shape menu has no fixed frame.

- **S5** (verbatim): "no esta resuelto sigue mostrando el custom cursor del tool activo sobre la barra y sobre
  el window title y los botones de la ventana del editor". The tool cursor must apply only over the image;
  over the editor's own chrome — palette, title bar, window buttons — it is the arrow.

- **S6** (verbatim): "el editor debe mostrarse en el dock como una app mas porque sino se queda la ventana
  abirta y se puede perder. Ademas si se abre desde finder una imagen debe salir la opcion de abrir con stare
  y abra el editor". While an editor is open the app is a regular app in the Dock, and an image opened from the
  Finder with Stare lands in the editor.

## Tasks

| ID | Specs | Task | Route | Commit |
| --- | --- | --- | --- | --- |
| T1 | S4, S5 | The spotlight's cell and the cursor over the editor's chrome | worker | uncommitted |
| T2 | S1, S2, S3 | History closes on action; select moves the mark; blur paints | worker | uncommitted |
| T3 | S6 | Dock presence and Open With | worker | uncommitted |

## Log

- **L1** (owner, 2026-11-26, verbatim): the six quotes above, sent as one message with a screenshot of the
  editor's palette where the spotlight cell spans roughly a third of the bar.
- **L2** (worker, 2026-11-26, T1–T3 closing pass, all six S#): S1 — an acted history menu action now runs its
  act and then the pick's own `onClose` seam (`CaptureHistoryPanelModel.perform`), so the sheet closes and the
  panel's hide restores focus; arming Delete stays open on purpose (the confirm happens on the standing sheet)
  and the confirming delete closes like the rest — 6 model-level tests, one panel-level hidden-hook test.
  S2 — the editor's draw replaces the dragged mark with its ONE selection preview on the drawn set for the
  whole drag (`drawLiveMark`), so the ink and the dashed chrome land together and the drop journals exactly one
  step (live-ink-probe test: old spot vacated mid-drag, ink at the dragged spot, one ⌘Z per drag).
  S3 — blur marks on the editor's live canvas paint the redaction through the ONE dispatch
  (`MarkRenderer.redactionPatch`, the compositor's own crop rule via `drawLiveBlur` — same `DrawingSession`
  stamp) instead of the 0-width outline stroke; live-view pin inside the mark, stripes kept outside it.
  S4 — the spotlight's AppKit cell takes its neighbours' 28×26 back (fixed frame on the
  `SpotlightToolButton` in `ToolbarView.toolButton`; the right-click shape menu is the same view's own and
  unaffected); the stretch pin measured 118 pt against the fix at a widened window (the defect reproduces at
  spare row width, not at preferred width).
  S5 — the editor's one cursor decision `CaptureEditorCanvas.cursor(atWindowPoint:)`: the armed tool's glyph
  (or the gesture pair) only over the image; the arrow over the palette row, the title bar and the window
  buttons; the content now owns the same delivery tracking area every other cursor surface installs
  (`.cursorUpdate` + `.activeAlways` + crossings) and routes its handlers and the canvas's exit through the
  decision — no second ambient `set()`; leaving the image and re-entering it both pin the pair.
  S6 — `CaptureEditorController.dockActivationPolicy(forEditorCount:)` (0 → accessory, any editor → regular)
  applied at open and at the last close, so the Dock shows Stare exactly while an editor window exists
  (launch stays the accessory LSUIElement contract); the app delegate bridges the system's open-files event
  into `OverlayController.openFileInEditor(at:)`, which decodes and hands the file through the ONE
  `openCaptureEditor`; the bundle's Info.plist declares png/jpeg/gif/tiff at rank Alternate (offered, never
  the default thief).
  Focused run `swift test --filter "CaptureEditor|CaptureHistoryPanel|ToolbarLayout"` exit 0 — 107 cases
  passed (95 StareTests + 12 StareCoreTests), 0 failed, additions 21 (S1×7 incl. panel level, S2×1, S3×1,
  S4×1, S5×4, S6×7). Two deliberate exclusions: the Dock icon's REAL visibility in Finder/Cmd-Tab and the
  Finder "Open With" menu are runtime system appearances — the owner's eye closes those; `LSUIElement` stays
  true, so the Dock presence rides the runtime flip, not a launch change.
