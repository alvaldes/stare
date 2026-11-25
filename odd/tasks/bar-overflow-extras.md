# Bar overflow: the `⁞` that holds the extras, and the pool as the bar's hidden section

Worktree `stare-wt-bar-extras`, branch `feat/bar-overflow-extras`, off `main` at `60189f6`, so the
capture-history work in the main worktree is never touched. The bar carries too many tools for a vertical
dock; the extras move behind a `⁞`, and the Settings pool becomes the place those extras actually live.

Bring `main` in as it advances (`git merge main`) so the merge at the end stays small.

## Specs

- **S1** The bar gets a `⁞` for the tools that are not the main ones, so it stops growing:
  "En el bar ya hay muchas cosas y esto hace que sea demasiado grande sobre todo para vertical y para eso
  entre las cosas que podemos hacer es poner unos '⁞' para tools extras como el spotlight y algun otro que
  no sea los principales."
- **S2** The pool is not a graveyard: it is the bar's hidden section, reached from the `⁞`, organised the
  way Bartender organises its menu bar — one ordered strip, a divider you drag, and what falls past the
  divider still reachable from the icon:
  "Para el pool recuerda la idea que teniamos y usa lo que bartender puede ofrecer porque ellos ya pensaron
  en como hacer que su UX/UI fuera la optima."
- **S3** On a fresh install the visible bar holds the drawing tools — pen, highlighter, arrow, rectangle,
  ellipse, text, eraser — and the extras behind the `⁞` are line, number, blur, spotlight and laser
  (owner's choice, see L3). Every tool stays movable between the two sections.
- **S4** The Settings pool stops being inert: it always lists the tools behind the `⁞`, in their order,
  says what it is, and never collapses to a lone separator chip on a fresh install:
  "mejorar la experiencia de la pool ... en settings".
- **S5** The Settings preview shows the real bar, `⁞` included, in the current orientation and without
  scrolling, and it shows what is behind the `⁞` when you open it there:
  "mejorar la experiencia de ... el prevview en settings".
- **S6** A tool behind the `⁞` keeps its key: pressing the spotlight's key selects the spotlight whether it
  sits on the bar or behind the `⁞`, and the bar shows that it is the active tool.

## Tasks

| ID | Specs | Task | Route | Commit |
| --- | --- | --- | --- | --- |
| T1 | S1-S3 | Model: one ordered strip with a divider index, the pool derived from it, legacy decode, defaults | pending | |
| T2 | S1, S6 | The `⁞` button on the real bar and the hidden palette it opens | pending | |
| T3 | S4 | The Settings pool as the hidden section: always listed, ordered, draggable both ways | pending | |
| T4 | S5 | The Settings preview shows the `⁞`, the divider, and the hidden palette | pending | |
| T5 | S1-S6 | Docs: README, CHANGELOG, and the ODD log for this batch | pending | |

## Log

- **L1** (user, verbatim): "En el bar ya hay muchas cosas y esto hace que sea demasiado grande sobre todo
  para vertical y para eso entre las cosas que podemos hacer es poner unos '⁞' para tools extras como el
  spotlight y algun otro que no sea los principales. Esto junto con mejorar la experiencia de la pool y el
  prevview en settings va a ser lo que vas a trabajar en un worktree separado para no interferir en main.
  Siempre que puedas traete los cambios para que al momento del merge sean menos los conflictos. Para el
  pool recuerda la idea que teniamos y usa lo que bartender puede ofrecer porque ellos ya pensaron en como
  hacer que su UX/UI fuera la optima."
- **L2** (decision, S2): the pool is the bar's hidden section, not a separate "removed" bucket — a tool is
  either on the bar or behind the `⁞`, never nowhere. Bartender's own model: one strip, one divider, the
  hidden run behind the icon.
- **L3** (decision, S3): visible by default = pen, highlighter, arrow, rectangle, ellipse, text, eraser;
  behind the `⁞` = line, number, blur, spotlight, laser. Reversible from Settings.
- **L4** (process): work happens in `stare-wt-bar-extras`; the main worktree's uncommitted capture-history
  changes are left alone, and this branch merges `main` whenever it moves.
- **L5** (evidence, session start): the repo has no earlier written record of "the pool idea" — `odd/tasks/`
  mentions the pool only as the organiser's off-bar bucket (`v0.5.md` S5/L7, `bar-pane-organiser.md`), and
  that same round recorded the symptom this batch fixes: on a fresh install every tool sits on the bar, so
  the pool shows only the Separator chip and looks inert (`bar-preview-and-cursors.md` L-note).
