# D4: the file-name card reads as a chain, not as prose

## Specs

- **S1** (verbatim, the owner's verdict after using it): "mejor aunque falta pulir el
  UX/UI". The card works — the template names the file, the preview follows, the
  prefix stands down — and it reads badly: four blocks of prose, three controls and a
  preview line, with the rule about which control governs explained in a sentence
  instead of shown.

- **S2** Nothing about the naming behaviour changes. This is presentation only: the
  rendered name, the migration, the sanitising and the disabled prefix rule all stay
  exactly as they are.

- **S3** The card must show, not tell: one visible chain from prefix or template to
  the file name that will be written, with the prose cut to what a user needs to know
  before typing.

## Tasks

| ID | Specs | Task | Route | Commit |
| --- | --- | --- | --- | --- |
| T1 | S1-S3 | The card's layout and copy | worker | uncommitted |
| T2 | S1-S3 | Docs: CHANGELOG and this log | worker | |

## Log

- **L1** (owner, 2026-11-25, verbatim): "- 4. mejor aunque falta pulir el UX/UI",
  written while looking at the capture pane after the template work shipped.

- **L3** (S1-S3, T1): the card now reads as one chain. Layout before: a
  prefix row, a template row carrying four blocks of prose (~460 chars,
  wrapped to many lines in the column — the reason the pane went
  single-column), a rule caption, and a preview line "Files are named like
  <name>" with the governing rule only told. Layout after:
  - The rows swapped, template first — it governs by default
    (`defaultFileNameTemplate`) — and the chain sits beneath: one line,
    `[Template] → Stare-2026-11-21-at-14-05-33.png`, with the governor as an
    accent chip and the name in monospaced caption (new `FileNameChain` view
    + file-scope `FileNameSource`, both in `SettingsView.swift`), replacing
    the "Files are named like" lead.
  - The template row's detail, cut to two short lines: "Tokens: {date} ·
    {time} · {app} · {display}, plus letters, numbers, hyphen, underscore
    and dot — anything else isn't kept. The .png or .jpg extension is added
    automatically." (was: the four blocks about folder saves, fallbacks when
    unknown, and the extension).
  - What moved where: "Folder saves:" became the caption's first sentence
    ("Templates apply to folder saves. While a template is set it builds the
    whole file name; clear it and the prefix names the files again." — the
    rule sentence kept verbatim); "…come from the capture itself; when they
    aren't known…falls back to the prefix" became a hint shown only under
    the chain, and only when the typed template uses {app} or {display}
    (`CapturePane.templateCanBeRefused`) — the moment a refusal shows
    (pre-capture app/display are unknowable; unknown tokens and unsafe
    characters cannot be stored at all, so "anything else isn't kept" in the
    detail is that whole fact). The prefix row's detail is unchanged.
  - Behaviour untouched (S2): same `CaptureEditorCanvas.savePanelFileName`
    call at the fixed 2026-11-21 14:05:33 instant inside
    `exampleName`, same disabled rules, no new TextField. Motion: `.easeOut(duration: 0.12)`
    on the chain's governor handover, the repo's one idiom.
  - Verification (TDD): RED was a compile failure (`cannot find
    'FileNameChain' in scope`; `swift test --filter CaptureFileNameCardTests`,
    exit 1); GREEN: the same filter, exit 0, Executed 6 tests, 0 failures.
    PRESERVE: `swift test --filter "CapturePrefixAndTemplateTests|
    SettingsCapturePaneDisabledStateTests|CaptureFileNamePreviewTests"`, exit 0,
    Executed 7 tests (2+4+... the three suites' cases), 0 failures — the
    field count (4 = prefix, template, 2 backdrop fields), the
    prefix-disabled rule and its caption survive unchanged. Full suite
    unpiped: `swift test > .build/w20b.log 2>&1; echo EXIT=$?` → EXIT=0,
    StareTests Executed 418 tests (baseline 412 + the 6 new),
    StareCoreTests Executed 916 tests, 0 failures.
    Chain-name-per-token pin:
    ""/"{date}"/"{time}"/"{date}_{time}" → the template's own name,
    "{app}"/"{display}" → "Shots-2026-11-21-at-14-05-33.png" (prefix-name
    fallback, exactly what the save panel writes).
  - Not done: T2 (docs) left alone as asked; no change to naming, migration
    or sanitising; row order is the one presentation change on top of the
    chain (template first so the chain reads top-down).

- **L4** (S4-S5, worker, the owner's verdict that drove it, verbatim):
  "D4- Con Name template creo que no hace falta tener Name prefix porque
  este ya suple lo que hace el prefix. por lo demas funciona bien pero no
  agrega info en el previe cuando agrego por ejemplo {app}".
  - What was removed (S4): the card's Name prefix row — the TextField and
    its `prefixRowDetail` constant are gone (`SettingsView.swift`); the
    template supersedes it, and a control the template always overrides has
    no business in the pane. The card is now the template row, the caption,
    the chain and the conditional {app}/{display} hint; the pane's TextField
    count went 4 → 3 (template + the two backdrop fields).
  - How the fallback still works without a control (S4): nothing about
    naming changed — the stored `fileNamePrefix` keeps working exactly as
    before when the template is empty (`CapturePreference.fileName(at:)`'s
    legacy branch renders the prefix name byte for byte), a user who clears
    the template still gets a name, and the pane still says what that name
    will be: the chain's source chip names the governing control as
    `Prefix` (`FileNameSource.source`, decision unchanged) and `exampleName`
    renders the same `CaptureEditorCanvas.savePanelFileName` call. The only
    copy change: `templateRuleCaption` now says "clear it and the stored
    prefix names the files again" — the value, never a control that is no
    longer there; `tokenFallbackHint` is untouched and still truthful
    (the Settings preview cannot know a FUTURE capture's app/display).
    Leftover from the earlier unit fixed: switching destinations from a
    stored clipboard choice prefills `CapturePreference.defaultDestinationFolder`
    (`~/Downloads`), never the `~/Documents` the previous build baked into
    `destinationSelection`/`folderPath` — the pane never states a folder the
    app does not use; `destinationSelection` went internal for the pin.
  - Where app/display now come from (S5): ONE resolution in
    `OverlayController.deliver` — hoisted above the destination branch, so
    `CaptureAppIdentity.appName(frontmostName:frontmostProcessIdentifier:)`
    and `screen(for: canvas.displayID)?.localizedName` resolve for EVERY
    capture, the folder save's tokens and the handoff registering the pair
    (`editorIdentities.register`, a `CaptureEditorIdentity`) with the loot
    read again by `openCaptureEditor`. The ledger (`EditorIdentityLedger`,
    `OverlayController.swift`) keys by `ObjectIdentifier` and — knowingly —
    RETAINS the images it keys: a non-retaining key was unsound (a freed
    CGImage's address gets recycled, so one capture's identity silently
    reached for another — caught by the RED eviction probe, where the count
    never grew at all); the bound is `OverlayController.identityLedgerLimit`
    = 16 recent captures, and nothing is held that the session history does
    not already hold. The identity rides the handoff
    `openEditor(image, capture, redactionStyle, identity)` →
    `CaptureEditorController.open(image:capture:redactionStyle:app:displayName:)`
    (trailing optionals, every existing call site compiles unchanged) →
    `CaptureEditorWindow` → `CaptureEditorContent` → the canvas's ONE
    `CaptureEditorContext` = `CaptureEditorCanvas.fileNameContext`.
  - Which value each path ends up with (S5): the save panel's default name
    field (the file-name preview the user sees) and the file the panel
    writes are BOTH rendered by the one
    `CaptureEditorCanvas.savePanelFileName(preference:at:calendar:app:displayName:)`
    call from that one context — a capture the ledger holds previews its
    REAL app (`{app}` → e.g. `Finder.png`) and display (`{display}` → e.g.
    `Desk.png`) and writes that same name (the panel writes `panel.url`,
    whose default is this same value); an identity no capture exists for —
    this editor's own composed variant, a capture from a previous session,
    an evicted one — is `.unknown` on BOTH paths, the tokens refuse, and
    both render the prefix-name fallback exactly as the Settings preview
    documents: no silent fallback vs. save mismatch. The injected test
    handoff (`editorHandoff:`) keeps its old (image, capture) shape; the
    production closure widened and reads the identity.
  - Verification (TDD): RED was a compile failure — the new seams did not
    exist (`destinationSelection` private; `CaptureEditorIdentity`/
    `fileNameContext`/ledger unresolved; `swift test --filter
    "CaptureFileNameCardTests|CapturePrefixAndTemplateTests|
    SettingsCapturePaneDisabledStateTests|CaptureFileNamePreviewTests"`,
    exit 1). GREEN: same filter, exit 0, Executed 18 tests (6+7+3+2),
    0 failures. PRESERVE: `swift test --filter "CaptureEditorBackdropTests|
    CaptureEditorDeliveryTests|CaptureEditorChromeTests|
    CaptureEditorCursorTests|CaptureEditorEraserTests|CaptureEditorZoomTests|
    CaptureHistoryTests|CaptureCardActionsTests"`, exit 0, Executed 58
    tests, 0 failures — the editor chain's constructors with defaulted
    optionals, the nil-identity panel name
    (`Stare-2026-11-21-at-14-05-33.png`, byte for byte) and the legacy
    prefix branch survive unchanged. Full suite unpiped:
    `swift test > .build/w26.log 2>&1; echo EXIT=$?` → EXIT=0,
    StareCoreTests Executed 919 tests, StareTests Executed 436 tests
    (baseline 431 + the 5 net new: +4 in CaptureFileNamePreviewTests, +1 in
    CapturePrefixAndTemplateTests's prefill pin; the card and
    disabled-state pins were re-derived, their counts unchanged), 0 failures. S4 canaries: the re-derived
    field-count pins name S4 in their messages
    (`CaptureFileNameCardTests.testThePaneCarriesExactlyItsThreeTextFieldsWithNoPrefixRowLeft`,
    `CapturePrefixAndTemplateTests.testTemplateSetNamesTheFileForEachDestinationAndThePrefixRowIsGone`,
    `testTemplateEmptyHandsTheNameBackToTheStoredPrefixForEachDestination`,
    the folder-prefill pin, and the absence pins in
    `SettingsCapturePaneDisabledStateTests`); S5's pins carry the values
    (`Finder.png`, `Desk.png`) and both-path-agreement.
  - Not done: T2 (CHANGELOG/docs) left alone as before; no change to
    naming, migration, sanitising or the disabled-template-on-clipboard
    rule. The ledger keeps an evicted capture's identity unknown by design
    — the fallback both paths agree on — not a stale name.
