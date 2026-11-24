# What CleanShot X and Shottr have that Stare could use

Analysis, not a plan. Every entry below ends in a verdict: adopt, adapt, defer or
skip. Written in an isolated worktree (`analysis/capture-features`) so the main
checkout stayed untouched. Owner decisions taken after the first pass, and
what is still open, are in §6; what was parked for a later analysis is in §7.

Sources, read directly from the vendors on the date of this analysis:

- CleanShot X feature page (`cleanshot.com/features`) — annotate, background,
  Quick Access overlay, capture modes, recording, video editor, cloud, pin, OCR,
  All-In-One, capture history.
- Shottr homepage (`shottr.cc`) — feature cards, tips and tricks, FAQ, release
  notes up to **v1.10**.
- Stare's own `README.md`, `CHANGELOG.md`, `Package.swift` and `Sources/`, plus
  greps for the capabilities discussed here.

Third-party comparison sites were consulted only for orientation and are never
treated as fact below.

---

## 1. The filter: what Stare is, and is not

Stare's thesis is stated in its own README: **draw on the live screen first,
capture second.** The app under the marks keeps focus, and a capture is a
by-product of pointing at something.

CleanShot X and Shottr invert that. They are **capture first, editor second**:
a frozen image lands in an editor window and you annotate a still picture. That
difference decides most of this document. A feature copied without asking that
question produces two apps fighting inside one menu bar item.

Four invariants worth protecting:

| Invariant | Consequence for feature selection |
| --- | --- |
| Draw first, capture second | Anything that only makes sense on a frozen image is a lower priority than anything that improves the live pass. |
| Nothing leaves the Mac | No accounts, no cloud, no link sharing. Local-only OCR yes; upload no. |
| Keyboard-first, few keys | A feature that needs a new mode, a new window or a pointer-heavy panel costs more than its line count. |
| No editor in the middle | The capture card and the optional editor are the escape hatch, not the main road. |

Scale matters too. Stare is one open-source app on macOS 26+ built on
ScreenCaptureKit, with a marked separation between `StareCore` (testable logic)
and `Stare` (AppKit glue) and a large self-test surface. Both competitors are
commercial products with years of post-processing work. Feature-for-feature
parity is not a goal Stare can win, and not one it should try.

---

## 2. Stare today (verified baseline)

**Has:** live overlay drawing over any app (`⌥⇧A`); pen, highlighter, arrow,
line, rectangle, ellipse, text, numbered step, laser, blur, eraser; eight inks;
undo/redo; pointer-tool selection and move; whole-display and drag-area capture
with marks composited in; capture card (copy, save, drag out, open editor);
editor with the same tools plus a staged crop; whiteboard with pages, pan and
zoom; pin mode that lets clicks pass through; pointer highlight (`⌥⇧M`) with
five shapes, size, band, opacity, glow, click animation, colour, idle fade;
capture to clipboard or folder, PNG/JPEG, filename prefix; every shortcut
rebindable; launch at login; GitHub update check; onboarding and Screen
Recording permission handling.

**Does not have** (grep-verified, not assumed): any Vision/OCR usage, window
capture, capture history, image zoom or pan in the editor, a screen colour
sampler, a self-timer, filename templates beyond a prefix, image pinning (pin
mode pins *marks*, not captured images), and any networking beyond the update
check.

---

## 3. Feature matrix and verdicts

### 3.1 Capture modes

| Feature | CleanShot | Shottr | Stare | Verdict |
| --- | --- | --- | --- | --- |
| Area capture | yes, aspect ratio, edge snapping, crosshair, magnifier, freeze | yes, advanced (freeze, lens `L`, 10× zoom `Z`, cursor slowdown, WASD nudge, `shift` for square) | yes (drag `⇧S`) | **Adapt: freeze + magnifier inside the existing area drag.** |
| Window capture | yes (background or transparent) | yes | no (only display, though `FrontWindowLocator` already finds the front window to name its display) | **Adopt.** The highest value/cost ratio in this list. |
| Fullscreen | yes | yes | yes (`S`) | parity |
| Self-timer / delayed | yes | yes | no | **Parked with §7, not Tier 1.** Its job in both competitors is to let you re-open a menu or re-hover after the hotkey dismissed it. Stare's order is the opposite, so freezing the frame does that job better; a countdown only pays off once a capture can happen without drawing first. |
| Scrolling capture | yes, vertical and horizontal | yes, any app, headline feature | no | **Parked, not dropped (§7).** Large and fragile today (stitching, alignment, incremental capture) and meaningless while Stare is draw-first: you cannot annotate a page that does not exist yet. It becomes coherent the moment Stare grows the capture-then-edit path the owner wants. |
| Repeat last area | yes (All-In-One remembers last selection) | yes | no | **Adopt, cheap.** One stored `CGRect`. |
| Freeze screen | yes | yes (v1.10 default) | no | **Adapt** — see area capture. Freezing at the moment `⇧S` starts turns area capture from racy into deterministic, which is a correctness win, not just polish. |

### 3.2 Annotation

| Feature | CleanShot | Shottr | Stare | Verdict |
| --- | --- | --- | --- | --- |
| Crop with aspect ratio + edge snapping | yes | yes | crop only (staged, adjustable) | **Adapt:** add snapping of the crop box to the front window's bounds. Cheap, uses existing geometry. |
| Pixelate (randomized) | yes, "secure" mode | yes, plus text-only mode | blur only | **Adopt (small):** a pixelate option next to blur. Blur must be audited for redaction safety; randomized pixelation is the honest primitive for hiding content. Text-only erase is **skip** (needs text detection plus inpainting). |
| Arrow styles, curved / bendable | 4 styles | bendable arrows, narrow/curved | one arrow | **Defer bendable** (bezier handles are a new interaction). **Adopt cheap variants:** arrowhead styles and a line-weight control. |
| Filled rectangle / outline toggle | yes | hand-drawn style | outline only | **Adopt, cheap.** One boolean per shape mark. |
| Pencil auto-smoothing | yes | yes | no | **Defer.** Stare's pen is already a path builder; smoothing changes how every existing drawing looks, which is a taste decision, not a gap. |
| Highlighter with smart text-size detection | yes | yes | fixed-width highlighter | **Skip.** Needs text-line detection against live pixels; the payoff does not justify it. |
| Text with predefined styles | 7 presets | styles | free text | **Adopt, cheap:** remember the last text style (size, ink) as the default for the next text mark. |
| Spotlight as a mark | yes | yes | pointer highlight has a Spotlight *shape* but it is not a persistent mark | **Adapt:** reuse `PointerHighlightRenderer`'s spotlight as a persistent annotation. Small, and it makes Stare's own vocabulary consistent. |
| Numbered step counter | yes | yes (step counter) | yes (`C`) | parity |
| Colour picker from the screen + saved palette | yes | yes (TAB, text colour, average colour) | fixed eight inks | **Adapt, small:** let one ink slot be replaced by a colour sampled off the captured frame during a capture. Goes against the fixed-palette simplicity, so it is optional and off by default. |

### 3.3 Output and save

| Feature | CleanShot | Shottr | Stare | Verdict |
| --- | --- | --- | --- | --- |
| Quick Access overlay / card | yes, with position, size, auto-close, swipe, restore, hide | pinned thumbnail | yes, the capture card | **Adapt:** close the specific gaps — auto-close timing as a preference, and pin the *captured image* as a floating window (see 3.4). |
| Drag out to any app | yes ("Drag me") | yes | yes | parity |
| Resize / downscale on save | yes | yes, retina downscale setting | no | **Adopt, cheap and underrated.** A Retina capture is 2× the bytes anyone wants in a chat. One "downscale to 1× (or max width)" preference. |
| Filename templates | limited | yes, template builder (v1.10) | prefix only | **Adapt:** a small token set (date, time, app name, display) instead of a builder. The folder destination already exists. |
| Editable project file format | yes (CleanShot files) | restorable screenshots with editable annotations (v1.10) | marks are editable in-session only | **Defer.** A persisted document format is an architectural commitment. First step: keep recent captures with their mark document *in memory* for the session (see history). |
| Rotate / flip | yes | yes, annotations rotate with the image | no | **Defer.** Low value for a draw-then-capture tool. |
| Backdrop / background tool | yes, 20 backgrounds, presets, auto balance | yes, gradients, shadows, rounded corners | no | **Adapt small, defer large.** Everyone shares these, but it belongs to capture-then-polish. A cheap 20% version: optional padding + rounded corners + shadow saved with the capture. Presets and aspect ratios: skip. |

### 3.4 Retrieval and reference

| Feature | CleanShot | Shottr | Stare | Verdict |
| --- | --- | --- | --- | --- |
| Capture history | yes, up to 1 month, filter, restore, delete | restore previous / next pic | no | **Adopt (in-memory, session-scoped).** Losing a capture because the card drifted out of reach is the single most common way a capture app fails its user. Start with the last N captures in memory; persistence is a later decision. |
| Pin a screenshot as a floating always-on-top window | yes, size, opacity, arrow-key placement, lock mode | yes | pin mode pins *marks* only | **Adopt.** Reuses the card and gives Stare the reference-image workflow both competitors have. `⌥⇧P` semantics need a decision: pin marks, pin image, or cycle. |
| Search by content or transcript | yes (cloud, tags, transcripts) | OCR copies text | no | **Skip.** Cloud-shaped feature, contradicting the local-only invariant. |

### 3.5 Text and data out of pixels

| Feature | CleanShot | Shottr | Stare | Verdict |
| --- | --- | --- | --- | --- |
| On-device OCR | yes, 30+ languages | yes | no | **Adopt.** Highest value per line of code here: Vision's text recognition is a handful of lines, runs locally, and completes the redaction story it already tells (blur hides it, OCR extracts it). |
| QR code reading | yes | yes | no | **Adopt with OCR.** Same framework, same area selection. |
| Ruler / measurement, distance between objects | no | yes, its identity | no | **Parked, not dropped (§7).** A different product today (pixel professionals), and it would add a measuring vocabulary beside the drawing one — but the owner wants it analysed later rather than dropped. |
| Contrast checker (OKLCH / APCA) | no | yes | no | **Parked, not dropped (§7).** Same reasoning as the ruler; revisit both together. |

### 3.6 Out of scope by design

| Feature | Both apps | Verdict |
| --- | --- | --- |
| Screen recording, MP4/GIF, camera, mic, audio | CleanShot's core | **Skip.** An encoder, a video editor and a second app's worth of UI. Stare's `⌥⇧M` pointer highlight already serves the live-presenting case, which is the slice of that job Stare actually wants. |
| Video editor (smart zooms, motion blur, vertical export) | CleanShot | **Skip.** Follows from the previous row. |
| Cloud upload, links, comments, SSO, custom domains | CleanShot Cloud | **Skip. Hard no.** It is the one thing that would invalidate "captures stay on your Mac". |
| S3 / custom upload | Shottr (activated) | **Skip** for now. If it is ever needed, opt-in, user-supplied endpoint, never a default. |
| Click and keystroke visualisation while recording | CleanShot | **Defer, but interesting.** Stare has the click pulse already. Showing pressed keys while presenting (not recording) is an on-thesis differentiator, but it needs an event tap and Accessibility permission — a real cost to the app's permission story. |
| Combine images / image overlays / before-after animation | both | **Defer.** The editor is the right home, but it is thin today; adding composition before adding zoom is the wrong order. |

---

## 4. Recommended sequence

Three tiers. Nothing here is a commitment; the ordering is the argument.

### Tier 1 — closes gaps a capture app is expected to have (small, additive)

1. **Window capture.** Capture the front window instead of the whole display,
   marks composited in. `FrontWindowLocator` already identifies that window.
2. **Freeze + magnifier + remembered rect in the area drag.** Makes `⇧S`
   deterministic (no more chasing a hover state) and precise.
3. **Capture history, in memory, session-scoped.** Reopen the last capture in
   the editor with its marks still editable.
4. **Pin the captured image.** A floating, always-on-top card, distinct from
   pin-the-marks; its opacity and size belong in Settings.

Self-timer left Tier 1 and moved to §7: freezing the frame solves the same
problem from the other direction, and a countdown only earns its keep once a
capture can happen without drawing first.

### Tier 2 — sharpens what Stare already claims to be good at

6. **On-device OCR + QR** from the same area selection, result on the
   clipboard. Pairs naturally with blur and pixelate.
7. **Pixelate next to blur**, with blur's redaction quality audited first.
8. **Save-time downscale** (Retina 2× → 1×, or a max width).
9. **Annotation depth, cheap subset:** filled/outline shapes, arrowhead
   styles, remembered text style, persistent spotlight.

### Tier 3 — deliberate, only with a written decision

10. **Editor zoom and pan.** The editor is the thinnest surface relative to the
    competitors' editors. Zoom is what makes annotating a capture precise.
11. **Filename templates** (tokens, not a builder).
12. **Cheap backdrop:** padding, rounded corners, shadow on save.
13. **Composable canvas:** add another capture or a pasted image into the
    editor (Shottr's "combine", CleanShot's drag-in).

**Written and skipped:** screen recording, GIF, cloud, text-only erase,
highlighter text detection, video editor, S3.

**Parked, not dropped (§7):** scrolling capture, self-timer, ruler and
contrast checker.

---

## 5. Traps

- **Becoming two apps.** Recording or a full editor with layers pulls Stare
  into CleanShot's product category, where it has no advantage and would have
  to charge.
- **Settings creep.** CleanShot's answer to every trade-off is a preference.
  Stare's Settings is already eight panes deep. Every new preference should
  displace a decision the app could make itself.
- **Modes.** Each new mode (window, scrolling, recording) doubles the mental
  model of a keyboard-first app. Window capture is worth it because it fits
  inside the *existing* flow; scrolling capture is not, because it needs its
  own.
- **A document format.** "Editable project files" is where a small capture app
  becomes an application with a file type, a save dialog, migration and
  compatibility promises. Session history gives most of the benefit with none
  of that commitment.
- **Feature-list parity as a goal.** Both competitors are priced products with
  teams; their feature list is their moat. Stare's moat is that there is no
  editor in the middle. Copying their list erodes it.

---

## 6. Decisions taken, and what is still open

### Decided

- **Scope is the complete list, not a taste of it**: Tier 1 and Tier 2 now,
  Tier 3 after they land.
- **Process**: implementation happens in a worktree isolated from `main`, so
  the in-flight corrections on `main` keep moving untouched.
- **Parked instead of deleted**: scrolling capture, self-timer, ruler and
  contrast checker go to §7 for a later analysis rather than the bin.

### Still open before the first line of code

1. **`⌥⇧P` semantics.** Today the key pins the *drawing*: the overlay stops
   taking input, the toolbar hides, the marks stay painted, and every click
   lands in the app underneath. The competitors' "floating screenshot" pins an
   *image*: a borderless always-on-top window you can move, resize and fade,
   with its own life independent of any drawing session. Those are different
   objects with different click rules, so the choice is:
   - **A — keep it as is.** Marks only. Cheapest, and the image case stays
     unserved.
   - **B — one key, context-dependent.** `⌥⇧P` pins the image when a capture
     exists and the marks otherwise. Same key, different result depending on
     hidden state: the classic surprise in a keyboard app.
   - **C — two entry points, no overloading (recommended).** `⌥⇧P` keeps
     pinning the marks exactly as today; the capture card grows its own pin
     action with its own shortcut. Each object keeps the click semantics it
     actually wants: marks are deliberately click-through, a pinned image
     wants dragging, resizing and a close button.
2. **What "complete" includes.** Tier 1 and Tier 2 are 9 items and a lot of
   Settings surface; Tier 3 (editor zoom, filename templates, cheap backdrop,
   composable canvas) is where the editor starts to become a second product.
   Confirm the cut line, and whether Tier 3 lands in this same worktree after
   the Tier 1+2 merge or waits.
3. **Settings collision.** The work in flight on `main` touches
   `SettingsView.swift` and `SettingsComponents.swift` — and Tier 1 needs new
   preferences (history length, pinned-image size and opacity, downscale).
   Either new panes go in new files with the smallest possible edit to the
   shared registry, or this work waits for that branch to land.
4. **History persistence.** Session-only memory, or captures that survive a
   restart? The second implies a store and a retention question.
5. **OCR surface.** A new global shortcut, a key inside the overlay, or "copy
   text" on an existing capture card? Each costs a different amount of
   keyboard budget.
6. **Blur honesty.** Should blur be re-examined for redaction before pixelate is
   added, given the README promises concealment?
7. **Downscale default.** Always 1×, a max width, or off until asked. Affects
   every existing capture the moment it ships.

---

## 7. Parked for a later analysis

These are explicitly wanted by the owner, not rejected. Each needs its own
analysis before it can become a task, and each one changes what Stare is, so
they are not "small additions" to the tiers above.

### Scrolling capture

- **Why it matters to the owner:** Stare should also allow capture first and
  annotate afterwards. Once that path exists, a page taller than the screen is
  a legitimate thing to capture and then mark up.
- **What it requires:** a capture-then-edit entry point (currently absent by
  design: `⌥⇧A` is an overlay over the live screen, and `S` freezes one frame);
  incremental frame capture through ScreenCaptureKit with scroll detection;
  stitching that survives sticky headers, fixed sidebars and lazy loading;
  a progress and cancel surface; and a memory ceiling for pages that can run to
  six figures of pixels.
- **What must be decided with it:** where the captured page lives before it is
  annotated (editor window or overlay), and whether the draw-first overlay ever
  gets a "scrolling area" mode — my recommendation is that it does not, and
  that scrolling capture belongs to the capture-first surface only.
- **Verdict to test in that analysis:** whether it is one feature or the first
  feature of a second surface.

### Ruler and contrast checker (Shottr's pixel-pro identity)

- **Why it matters to the owner:** not settled yet, worth an analysis.
- **What it requires:** a measuring interaction (arrow keys plus pointer, with
  the measurement imprintable as a mark), logical-versus-physical pixel
  handling on Retina, colour sampling with OKLCH and an APCA contrast readout,
  and a vocabulary that does not collide with the drawing tools' keys — `↑ ↓ ←
  →` and `TAB` are already spoken for or free depending on the mode.
- **Tension to resolve:** these are inspection instruments for people building
  interfaces, not annotations for people pointing at things. Serving both means
  either a mode (which a keyboard-first app pays for twice) or a separate
  lightweight window.
- **Verdict to test in that analysis:** whether Stare wants an inspection
  surface at all, or whether "point at a pixel-accurate thing" is already
  served by the capture, the editor and the magnifier.
