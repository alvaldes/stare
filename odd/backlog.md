# Backlog

Known work that is not being done right now. One entry per item: what the user
sees, why it happens, and where it lives. Add at the top; newest first.

Everything from the owner's 2026-11-25 list is shipped except the one item nobody
could specify, plus the follow-ups that need something only he can hand over.

## The references, as local files — so the work can be measured instead of guessed

- **What the owner sees**: four items were built from his words plus the app's own
  idioms, because the CleanShot references cannot be reached from this harness: the
  image endpoints serve AVIF that does not decode, `f_png` returns 404, and video
  frames only work for YouTube and local files. That is recorded in each feature
  doc's log (L2 in `editor-chrome.md`, `quick-access-cards.md` and
  `editor-bar-parity.md`).
- **What is unmeasured**: the crop frame's proportions and its handle behaviour
  (`https://cleanshot.com/video/screenshots/crop.mp4`), the spotlight's shape set
  against its reference image, the background tool's shape in the editor
  (`https://cleanshot.com/video/screenshots/bgtool.mp4`), the card's gestures
  (`https://cleanshot.com/video/home/quickaccess.mp4`), and how far the redaction's
  lattice is from `redact.png`.
- **How to close it**: save any of those to a local file and name the path. Each is
  then a comparison against real evidence rather than a design decision taken blind.
- **Reported**: 2026-11-25.

## The landing demo mirrors the card and the bar

- **What the user sees**: the marketing demo under `landing/` draws its own copy of
  the capture card and the bar. The card grew a 26 pt action strip and the bar's
  inks now fold, so the demo's mirror of both is out of date.
- **Why it is not in this list as a task**: `landing/` is owned by another session
  in this same working tree, and edits there from here would collide.
- **Where**: `landing/src/demo/card.ts` and the bar/demo sources beside it.
- **Reported**: 2026-11-25, by the worker that changed the card.
