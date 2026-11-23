<div align="center">

<img src="Resources/app-icon.svg" width="112" alt="Stare app icon">

# Stare

**Draw on your screen, then paste it anywhere.**

An open-source menu bar app for macOS. Press `⌥⇧A` to draw over any app,
press `S` to capture the screen with your marks, and paste the image into a
chat, an issue or a doc.

[**Website**](https://stare.alvaldes.workers.dev) ·
[**Try it in your browser**](https://stare.alvaldes.workers.dev/#try) ·
[**Download**](https://github.com/alvaldes/stare/releases/latest)

<a href="https://stare.alvaldes.workers.dev">
  <img src="docs/assets/landing-hero.png" alt="Stare: draw on your screen, then paste it anywhere" width="860">
</a>

</div>

## Three keys, start to finish

From "look at this" to an image in someone's chat, without leaving your keyboard.

1. **Press `⌥⇧A`.** A clear sheet covers every display, even full-screen apps.
   The app underneath keeps focus.
2. **Mark it up.** Arrows, highlights, boxes, circles and numbered steps, in
   eight inks. Every tool is one key.
3. **Press `S`, then paste.** Your screen and your marks land on a card in the
   corner. Copy it, save it or drag it out.

**Presenting? Point at it.** Press `⌥⇧M` and a ring follows your pointer, so
everyone watching your screen knows where to look. Clicks and focus stay with
the app you're presenting.

Lives in the menu bar · No account to create · Captures stay on your Mac · Open source

## Install

Stare runs on **macOS 26 or later**.

```sh
brew install --cask alvaldes/tap/stare
```

Or download [Stare.dmg](https://github.com/alvaldes/stare/releases/latest/download/Stare.dmg),
open it and drag Stare to Applications.

<details>
<summary>First launch from a browser download</summary>

Stare is not notarized (there is no Apple Developer account behind it), so a
DMG downloaded in a browser is stopped the first time you open it. Choose
**Done**, then open **System Settings → Privacy & Security** and click
**Open Anyway** next to "Stare.app" was blocked. Removing the quarantine flag
also works:

```sh
xattr -d com.apple.quarantine /Applications/Stare.app
```

Homebrew does not quarantine its downloads, so `brew install --cask` opens
Stare without this step.

</details>

**Permissions.** Drawing works without any permission. To capture the screen,
Stare asks for **Screen Recording** once (System Settings → Privacy & Security →
Screen Recording), and updates keep the grant.

**First run.** The first time Stare starts, a setup guide shows the app icon
and one line about what Stare does, then the permission it needs — Screen
Recording — and why. Its button opens System Settings right at the Screen
Recording pane, so you only have to flip the switch. When you come back, Stare
notices the grant on its own, enables **Continue**, and Continue opens
Settings. If macOS granted the permission but the running session cannot see
it yet, the guide offers a **Restart Stare** button. Closing the guide without
granting still marks it as seen — it never reopens by itself — and you can
reopen it any time from the menu bar with **Setup Guide…**.

## Every tool is one key away

| Keys | What they do |
| --- | --- |
| `⌥⇧A` | Start drawing over any app |
| `⌥⇧W` | Open the whiteboard |
| `⌥⇧M` | Point at things with the pointer highlight |
| `⌥⇧P` | Pin your marks so clicks pass through |
| `P` `H` `A` `L` `R` `O` | Pen, highlighter, arrow, line, rectangle, ellipse |
| `T` `C` `F` `B` `E` | Text, numbered step, laser, blur, eraser |
| `1`–`8` | Red, orange, yellow, green, blue, purple, white, black |
| `S` · `⇧S` · `⌥S` | Capture the display · drag to capture an area · capture the front window |
| `⌘Z` · `⇧⌘Z` | Undo · redo |
| `Esc` | Clear and leave |

<details>
<summary>More shortcuts</summary>

| Where | Keys |
| --- | --- |
| Drawing | Hold `⇧` for a straight line with the pen or highlighter, or a square or circle with the rectangle or ellipse · with the pointer tool, drag a box to select everything under it and hold `⇧` to add to the selection · hold `⇧` while dragging a capture area (`⇧S`) to force a square · the `⇧S` area drag runs on a frozen frame that exists before you press it — the screen as it was when you entered drawing mode, refreshed in the background after each capture — so what you see while choosing is the frame that gets captured no matter how short the drag is, a magnifier follows the pointer over the frozen frame so the exact pixel edge is visible (without Screen Recording the drag runs live and the magnifier stays away) — and `Esc` cancels the drag and brings the live screen back |
| Drawing | The `⇧S` area capture remembers the last rectangle for the session: press `⇧S` again and the old area is already framed — `Return` captures it as is, dragging chooses a new one — and leaving the overlay forgets it |
| Drawing | `Esc` clears the marks, and `⌘Z` brings back everything it cleared |
| Whiteboard | `⌘←` `⌘→` change page (going past the last one adds a page) · `⌘B` flips the page between white and black · hold space and drag to pan (the pointer becomes a grabbing hand) · pinch, `⌘` + scroll or `⌘+`/`⌘−` zooms, `⌘0` resets pan and zoom |
| Whiteboard | `S` captures the marks over the page colour, no Screen Recording needed · `Esc` closes the board and keeps the pages for the session |
| Capture card | Hover keeps it on screen · click opens the editor · drag it into another app |
| Editor | Same tools and inks · `⌘Z` undo · `⇧⌘Z` redo · `Esc` cancels a crop, then closes · an applied crop stays editable: drag its edges to adjust it, and `⌘Z` returns the previous crop |

All of these — the four global shortcuts and each tool's key — can be
rebound in Settings.

</details>

## Settings

Every preference Stare has lives in its Settings window (**Settings…** in the
menu bar): a resizable window with a sidebar of sections, where every change
applies immediately. The sections:

- **General** — the drawing frame, which displays to draw on, where the palette opens, the toolbar's orientation and which screen edge it docks to, which tools it shows and in which order, how long the laser lasts, whether marks and board pages survive quitting Stare (until the machine restarts, on by default), launch at login, and update checks.
- **Tools** — the ink drawing starts with, a shortcut for each tool, and the palette's position reset.
- **Shortcuts** — the four global shortcuts (`⌥⇧A`, `⌥⇧M`, `⌥⇧P`, `⌥⇧W`) with a key recorder and conflict checks.
- **Pointer Highlight** — the style of the `⌥⇧M` highlight: five shapes (Ring, Squircle, Rhombus, Dot, Spotlight), size up to 240 pt, band width, border style (Solid or Dashed), opacity, glow, the click animation (Scale or Rotate), colour and idle fade, with a live preview drawn by the same renderer the overlay uses.
- **Capture** — where captures go (the clipboard or a folder), the file format for folder saves, and the file-name prefix.
- **Whiteboard** — the page colour a new board opens with — White, Black or System, which opens pages white in light mode and black in dark mode — how many pages it opens with, which displays the board covers (every one or only the active display), and whether its border is drawn.
- **Permissions** — the live Screen Recording status, with a link to System Settings.
- **About** — the version and one line about the app.

All preferences persist together in one stored document, so an existing
install keeps the pointer settings it already had.

## Questions

<details>
<summary>How is it different from a screenshot tool?</summary>

You mark up the live screen first and capture second. There is no editor in
between unless you want one, so pointing at something takes a couple of key
presses.

</details>

<details>
<summary>Does drawing take focus away from the app I am using?</summary>

No. The app underneath stays active, so you can draw over it and keep working
in it.

</details>

<details>
<summary>Where do my captures go?</summary>

Each capture appears as a card in the corner of the screen. Copy it, save it,
or drag it into another app. Stare does not upload anything.

</details>

## Build it yourself

```sh
swift build
swift test
Scripts/bundle.sh release install   # builds Stare.app and copies it to /Applications
```

Architecture, signing, releases and the decisions behind them are in
[docs/DEVELOPMENT.md](docs/DEVELOPMENT.md). The website lives in
[`landing/`](landing/).

## License

[MIT](LICENSE) © 2026 Angel Valdés
