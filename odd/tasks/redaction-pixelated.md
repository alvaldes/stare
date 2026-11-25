# B2: redaction should read as pixelation, not as blur

The owner's item from the 2026-11-25 backlog list, with a CleanShot X reference
image and video.

## Specs

- **S1** (verbatim): "puedes hacer que el blur se vea estilo pixelado asi
  https://cleanshot.com/_ipx/f_avif&q_70&s_760x760/img/home/annotate/redact.png mira
  tambien este video https://cleanshot.com/video/screenshots/redact.mp4". The
  redaction the owner wants shows a hard lattice of large blocks, not a soft blur.

- **S2** The repo already carries a pixelate path (see `PixelateEffect` and
  `RedactionDispatchTests`), so this is a question of which effect a user actually
  reaches and of how the lattice is aligned and sized — not necessarily of writing
  a new effect. That must be established before a design is chosen.

- **S3** Whatever is chosen must be at least as irreversible as what it replaces:
  the existing blur audit recorded that a 15 pt radius holds against deconvolution,
  and that erosion begins at the glyph x-height. Worsening a redaction guarantee to
  gain an idiom is not acceptable.

## Tasks

| ID | Specs | Task | Route | Commit |
| --- | --- | --- | --- | --- |
| T1 | S1-S3 | The redaction the user reaches, the block size and the alignment | worker | 31acaa5 |
| T2 | S1-S3 | Docs: README, CHANGELOG and this log | worker | |

## Log

- **L1** (owner, 2026-11-25, verbatim): "- puedes hacer que el blur se vea estilo
  pixelado asi https://cleanshot.com/_ipx/f_avif&q_70&s_760x760/img/home/annotate/redact.png
  mira tambien este video https://cleanshot.com/video/screenshots/redact.mp4".
- **L2** (exploration, before any design): the primitive exists; the reference does not, to me.
  **What already ships**: `RedactionStyle` has two branches (`.blur`, `.randomizedPixelate`) and ONE dispatch —
  `MarkRenderer.redactionPatch` — feeding preview, capture, board and editor alike, pinned by
  `RedactionParityTests` at pixels-per-point 1. `PixelateEffect` derives its block from the mark
  (`ceil(min(w,h)/2)`, floored at `minimumBlockSize = 8` px), tiles the lattice from the selection's own corner
  snapped down to the pixel grid, and samples a half-block window at a per-cell pseudo-random offset keyed on the
  mark's own UUID, so the grid an inversion would need is never published. The blur keeps its fixed 15 pt radius.
  **The only way a user reaches it** is Settings → Tools → "Starting ink" → *Redaction* picker
  (`SettingsView.swift:1088-1100`), which writes a global preference: the tool is still called **Blur**, there is
  no per-mark choice, and the overlay and editor carry no redaction control at all. So the owner's ask is not
  "build pixelation" — it is "let me get pixelation without knowing a preference exists", and the honest options
  are a different default, a per-mark control, or a rename.
  **What must not weaken** (audit `odd/tasks/capture-extras.md` L4, spec S23): a blurred area must not leave the
  original reconstructible; 12 pt was the smallest safe radius against 11 pt text, so anything exposing a radius
  below ~10 pt must be blocked rather than offered. Same discipline for block size: the 8 px floor and the
  mark-derived size are the security floor, not a taste default.
  **What could not be studied**: the owner's reference image and video are unreachable from this harness — the
  `_ipx` URL serves AVIF that does not decode here, `f_png` returns 404, and frame extraction works only for
  YouTube and local files. No block-to-text ratio, lattice phase, edge treatment or live-preview behaviour was
  invented in this log.
- **L3** (S1-S3, implementation): the shipped default for `redactionStyle` is now
  `.randomizedPixelate` — the memberwise default in `AppPreferences` and the lenient
  decode fallback a stored blob gets when the key is missing or unreadable, and
  nothing else. Three defaults were deliberately left alone, each still `.blur`:
  `Stroke.redactionStyle`'s memberwise default, the `Stroke(persisted:)`
  legacy/unknown decode fallback, and the session restore fallback — a drawing saved
  before B2 keeps painting exactly what it painted. There is no migration of a stored
  `.blur`, unlike the filename template's key: `.blur` was reachable through the
  visible Settings → Tools → Redaction picker, so a stored `.blur` may be a
  deliberate choice and rewriting it would overrule the user. Nothing about the
  effects changed — the 15 pt blur radius, the 8 px block floor, the mark-derived
  block size, the per-mark UUID seed and determinism all stand. The picker keeps
  both options in its existing order; its copy implies no default, so nothing was
  rewritten. Verification: focused `swift test --filter
  'StareCoreTests.(AppPreferencesTests|RedactionPreferenceTests)'` — RED first (41
  executed, 7 failures, all "blur is not equal to randomizedPixelate"), then GREEN
  (41 executed, 0 failures, EXIT=0); whole suite unpiped `swift test > .build/w17.log
  2>&1; echo EXIT=$?` → EXIT=0, StareCoreTests 904 executed (baseline 902 + 2 new),
  StareTests 392 executed (unchanged), 0 failures.
