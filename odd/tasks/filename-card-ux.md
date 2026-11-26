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
