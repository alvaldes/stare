# The editor's Save: write the edits back into the image being edited

## Specs

- **S1** (owner's request, verbatim): "un save no vendria mal en el editor. algo
  como un btn save y que tenga un key cmd+s que salve los cambios en la imagen
  que se esta editando sin tener que descargar para tener otro imagen con los
  cambios."

- **S2** (decided behaviour): `Save` overwrites the image the editor was opened
  from; `Save As…` keeps its current behaviour and is still there for making a
  copy. The sources:
  - a file on disk (the Finder's Open With, or a shortcut that hands a URL):
    Save writes that file, in its own format, through the writer the app
    already uses for captures;
  - the history sheet: Save rewrites that entry's stored PNG and refreshes the
    entry (its pixel size if the crop changed it), so the panel shows the image
    the user now has — never a second entry or a second file;
  - a card, with a folder destination configured: Save writes into that folder
    under the template name, the way a capture would;
  - nothing to overwrite (a card whose destination is the clipboard, a capture
    with no file at all): Save falls back to `Save As…` rather than doing
    nothing, so the button never lies.

- **S3**: everything composes at `composedImage()` — the saved bytes carry the
  backdrop like every other path. One write path only: no second encoder, no
  second history-store call, and the export the app already does (`Save As`)
  must not change for Save.

- **S4**: a Save button in the editor's chrome beside the existing save-as, and
  `⌘S` in the app's main menu routed to the editor window only (the same
  gating the ⌘W item already uses, so Settings and panels are untouched). The
  button must show that it saved — the app's own hint idiom — and must be
  honest when it cannot (no file to overwrite and the folder write failed).

## Tasks

| ID | Specs | Task | Route | Commit |
| --- | --- | --- | --- | --- |
| T1 | S1-S4 | The Save target, the one write path (`CaptureFile.data` + `CaptureHistoryStore.rewrite`), the chrome button and the ⌘S target | worker | |
| T2 | S2-S4 | Tests: `Tests/StareTests/EditorSaveInPlaceTests.swift` (a test per source, ⌘S routing, Save As unchanged) | worker | |

## Log

- **L1** (owner, 2026-11-26, verbatim, S1): "un save no vendria mal en el
  editor. algo como un btn save y que tenga un key cmd+s que salve los cambios
  en la imagen que se esta editando sin tener que descargar para tener otro
  imagen con los cambios."

- **L2** (decision): the behaviour is the decided S2 split — Save overwrites,
  Save As copies — recorded as the spec above; the sources are named exactly
  and every unresolvable case degrades to the Save As panel.

- **L3** (S1-S4, 2026-11-26). _The routing._ `CaptureEditorSaveTarget` —
  `.storedFile(URL)`, `.historyEntry(UUID)`, `.capture` — threads the source
  through the ONE `openCaptureEditor` handoff: the Finder's `openFileInEditor`
  names the file, the persisted history sheet's Edit resolves a holding entry
  from the image `CaptureHistoryStore.image(for:)` hands out (`entry(for:)`,
  identity, never pixels — a foreign image stays a capture), and the card's
  route names `.capture` explicitly. _The one write path._ `CaptureEditorContent.saveInPlace()`
  composes at `composedImage()` (backdrop included, via
  `composedImageForSave(format:)`) and writes through `CaptureFile.data(for:format:)`
  — the panel's own encoder — so a JPEG file keeps its JPEG, a PNG file its
  PNG; there is no second history-store call: `CaptureHistoryStore.rewrite(entryID:with:)`
  replaces the stored PNG in place (same file name, same id and date, pixel
  size refreshed when the crop changed it, index persisted, session cache
  refreshed) so the panel shows the user's image next. The folder save renders
  its name through the ONE `savePanelFileName` call with the capture's own
  `CaptureEditorIdentity` tokens, and `CaptureFile.write`'s stored-backdrop
  pass and downscale stay deliberately out — the editor's composed variant
  already carries its own per-capture backdrop, and composing the STORED
  padding around already-padded pixels would lie about the surface. Delivery
  (`deliverComposed`) is Save As's contract only: an in-place save never
  records a second capture. Nothing to overwrite — a clipboard destination, no
  rewrite — hands to `launchSaveAsPanel()`, the ONE panel route the existing
  Save As already drove, so the fallback behaves exactly as Save As does. _The
  controls._ The chrome carries `Save` (`arrow.down.doc`) beside the unchanged
  `Save As…` (`square.and.arrow.down`); ⌘S is the app menu's `Save Editor`
  item through `EditorSaveShortcutTarget`, the exact retained-target +
  key-window-gate shape the ⌘W `Close Editor` item rides — Settings, floating
  panels and other windows are untouched. The outcome shows in the canvas's
  own hint pill (the crop hint's vocabulary): "Saved to
  <file>", "Saved to the capture history", or the honest "Couldn't save the
  image" for a failed write.

- **L4** (verification, 2026-11-26). `swift test --filter
  "EditorSaveInPlaceTests"`: exit 0, Executed 17 tests, with 0 failures. Full
  suite (unpiped): `swift test > .build/w39.log 2>&1; echo EXIT=$?` — exit 1:
  StareCoreTests Executed 920 tests, with 0 failures; StareTests Executed 527
  tests, with 2 failures — exactly the two known `TextSelectionWindowTests`
  failures (`testEveryExitRestoresThePreviousCursorAfterTheCrosshair`,
  `testTheSurfaceBecomesKeySoEscapeCanArriveWithoutActivation`), the
  test-order cases the baseline records, none of this task's. The suite run
  adds 17 (this file's tests) over the 510-count baseline, and
  `CaptureEditorWindowCloseTests` needed no change — the launch call stayed in
  the one-line shape its S8 canary reads.

- **L5** (the owner's two reports, corrected 2026-11-26). _Cause one —
  "si se guarda pero no se actualiza el orden ni el preview en el capture
  history"._ Two halves. The ORDER half: `rewrite` replaced the entry in
  place and kept its slot, so a changed capture stayed where it was — an
  edit is a new version of that capture, so the rewrite now also MOVES the
  entry to the FRONT of the newest-first array and persists the move with
  the index (id, date and file name stay the capture's own; the entry
  keeps the capture's date even at the front — an edit re-versions the
  capture, it does not re-date it). The PREVIEW half, twice over: (a) live
  re-read — the store cannot tell a visible sheet, so the overlay's ONE
  rewrite seam (`wireEditor`) now runs `captureHistoryPanel.model.refresh()`
  after a successful rewrite, `MainActor.assumeIsolated`, the same assumed
  hop the launch path owns; and (b) the re-RENDER half — an in-place save
  keeps the entry's id and, without a crop, every field, so a value-equal
  cell input would be a skipped SwiftUI re-render with the OLD pixels on
  screen; the model's `refresh()` now bumps a published `revision` and the
  grid keys its `ForEach` on it (`.id(model.revision)`), the pattern the
  Settings history pane's `historyRevision` already uses for its own
  post-Clear re-read. A closed-and-reopened sheet reads the same store
  state, so both opens agree. _Cause two — "el icono que le pusiste a
  save en el editor no indica lo que la accion y como esta pegado junto
  a save as se confunde, asi que hay que buscar otra solucion"._ Judged
  shape: ONE labelled SPLIT control replacing both glyph buttons. Justification:
  the click arm carries the WORD "Save" — what a click overwrites is on
  its face, no tooltip asked and no glyph guessed, which no glyph could
  honestly give — and the chevron arm opens a menu carrying "Save As…"
  under its own visible label, so nothing reading "save" sits beside
  another thing reading "save" again; the word arm performs exactly the
  in-place save (the ⌘S route unchanged) and never opens a panel, the
  menu item performs exactly the Save As panel and never overwrites, each
  tested doing exactly that. AppKit-backed cell (`ToolbarSplitActionView`,
  NSStackView of an unbordered word NSButton + a small chevron NSButton,
  `NSMenu.popUp` built fresh per opening) — the spotlight's menu-bearing
  cell precedent; the toolbar's glyph path is untouched for every other
  action. _The numbers_ (focused, short runs only — the full suite was
  NOT run): the RED build failed exactly on the new API (`ToolbarAction
  has no member 'label'/'menuItems'`), then `swift test --filter
  "EditorSaveInPlaceTests|CaptureHistoryPanelTests|CaptureEditorChromeTests"`
  > .build/a3.log — exit 0, Executed 42 tests, with 0 failures
  (CaptureEditorChromeTests 5 — pinning the
  bar unchanged; CaptureHistoryPanelTests 19 = 17 + the open-sheet
  reflection test + the revision test + the wiring canary, net +2;
  EditorSaveInPlaceTests 18 = 17 − the old glyph-beside-glyph shape test −
  the old Save-As-copy test + the one-labelled-control test + the both
  -arms affordance test + the front position store test). The wiring canary names its report in
  `testTheOverlayRewriteSeamRunsTheOpenSheetsReRead` — the overlay's
  `captureHistoryPanel.model.refresh()` call is what makes a visible
  sheet re-read, so a refactor must not drop it. _Not done_: the
  SETTINGS history pane (`SettingsHistoryPane`) is not on this task's
  edit surfaces, so an editor save does not live-refresh a pane standing
  open in Settings — it re-reads when Settings next re-renders rows (the
  store side is complete there); reported to the owner rather than
  widened into. _History_ (the honest limits, superseded in part): the
  earlier form of this entry recorded that only the NEXT open showed the
  saved pixels — that open-sheet limitation is what causes one above
  fixed; the limits that still stand: a file whose format the writer
  does not name (TIFF under Open With) has no honest overwrite — Save
  falls back to the Save As panel (pinned by the extension switch's
  default branch).
