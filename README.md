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
| `⌥⇧I` | Pin the latest capture as a floating image (draggable, resizable, lockable) — press it again to take the pin down |
| `⌥⇧O` | Recognise the text and QR code in an area you drag — on-device, straight to the clipboard; the screen dims the moment you press, the pointer becomes the same crosshair the area capture uses, and a magnifier follows the drag so the exact pixel edge is visible; `Esc` or a second press cancels it |
| `P` `H` `A` `L` `R` `O` | Pen, highlighter, arrow, line, rectangle, ellipse |
| `T` `C` `B` `D` `F` `E` | Text, numbered step, blur, spotlight, laser, eraser |
| `1`–`8` | Red, orange, yellow, green, blue, purple, white, black |
| `9` · `0` | Toggle whether the next shape is filled · cycle the next arrow's head (plain open, then filled) |
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
| Drawing | `9` toggles whether the next rectangle or ellipse is drawn filled or as an outline, and `0` cycles the next arrow's head between the plain open head and a solid one — the style is a property of the mark, so each shape keeps whatever it was drawn with through undo, redo and the capture. The next text mark also starts with the style the last one was typed at (its size and ink) for the session, and leaving the overlay forgets it |
| Drawing | `D` arms the spotlight: drag a region and everything outside it dims — the region's ellipse stays clear and the dim fades away from it in one soft gradient, wider on a large region and tighter on a small one, settling at its deepest shade far from the light. While you are still dragging, the mark previews as a plain ellipse outline — the ellipse tool's own look, no dim on screen — and the dim paints the moment the mark is committed, so a capture always carries it. The spotlight is a mark like any other: undo, redo, the eraser, the pointer tool's move and the capture editor all treat it as one, it works on the whiteboard too, and it has no ink of its own — the number keys keep choosing inks while it is selected |
| Whiteboard | `⌘←` `⌘→` change page (going past the last one adds a page) · `⌘B` flips the page between white and black · hold space and drag to pan (the pointer becomes a grabbing hand) · pinch, `⌘` + scroll or `⌘+`/`⌘−` zooms, `⌘0` resets pan and zoom |
| Whiteboard | `S` captures the marks over the page colour, no Screen Recording needed · `Esc` closes the board and keeps the pages for the session |
| Capture card | Hover keeps it on screen · click opens the editor · drag it into another app · the pin button in its corner floats the image as a borderless always-on-top window of its own, beside the card in the same screen corner — never in the middle of the display unless you drag it there: drag it anywhere, scroll to resize, ⌥-scroll to change its opacity, and its 📌, ✕ and 🔒 stay visible without hovering — 📌 (the pinned badge) and ✕ close it, 🔒 makes it click-through so you can work underneath it — and each one closes with its ✕ or its 📌 (or `⌥⇧I` takes the frontmost pin down); the pinned images stay on screen no matter what you open or close in Stare, and they never leave your machine |
| Recognise text | Drag the area and the text it holds — and a QR code, if that is what you framed — goes straight to the clipboard: recognition runs on-device with Vision, nothing is uploaded, and everything proceeds without opening a drawing session; the pointer is the crosshair for the whole gesture (it comes back whatever way the gesture ends) and a magnifier follows the drag, showing the display as the gesture opened so the exact pixel edge is visible the way the ⇧S area drag's magnifier does; a missing Screen Recording grant, a selection with nothing in it, or a failed read each say so on screen instead of ever touching your clipboard |
| Editor | Same tools and inks · `⌘Z` undo · `⇧⌘Z` redo · zoom and pan to annotate a fine detail: `⌘+`/`⌘−` zoom, `⌘0` resets to the fit, `⌘` + scroll or pinch zooms about the pointer, plain scroll or space-drag pans (the pointer becomes a hand) · tool keys never change · `Esc` cancels a crop, then closes · an applied crop stays editable: drag its edges to adjust it, and `⌘Z` returns the previous crop |

All of these — the four global shortcuts and each tool's key — can be
rebound in Settings. Two shortcuts are fixed: `⌥⇧I` pins the latest
capture — and takes the frontmost pin down again, so the keyboard can never
stack what it cannot dismiss; the card's pin button is the way to keep
several, and `⌥⇧O` recognises text and QR codes where you drag on-device.
The pin's lock has no key: it is the 🔒 on the pin itself, which stays
drawn and clickable even while locked. A fixed shortcut that cannot act
right now — a pin with nothing captured yet — says so on screen instead of
being a silent dead key.

</details>

## Settings

Every preference Stare has lives in its Settings window (**Settings…** in the
menu bar): a resizable window with a sidebar of sections, where every change
applies immediately. The sections:

- **General** — the drawing frame, which displays to draw on, where the palette opens, the toolbar's orientation and which screen edge it docks to, which tools it shows and in which order, how long the laser lasts, whether marks and board pages survive quitting Stare (until the machine restarts, on by default), launch at login, and update checks.
- **Tools** — the ink drawing starts with, a shortcut for each tool, and the palette's position reset.
- **Shortcuts** — the four global shortcuts (`⌥⇧A`, `⌥⇧M`, `⌥⇧P`, `⌥⇧W`) with a key recorder and conflict checks.
- **Pointer Highlight** — the style of the `⌥⇧M` highlight: five shapes (Ring, Squircle, Rhombus, Dot, Spotlight), size up to 240 pt, band width, border style (Solid or Dashed), opacity, glow, the click animation (Scale or Rotate), colour and idle fade, with a live preview drawn by the same renderer the overlay uses.
- **Capture** — where captures go (the clipboard or a folder), the file format for folder saves, the file-name prefix and a name template for folder saves — leave the template empty for the prefix-based name, or build it from the tokens `{date}` (2026-11-21), `{time}` (14-05-33), `{app}` (the app you captured) and `{display}` (the display you captured); literal text may use letters, numbers, hyphen, underscore and dot, the extension (`.png`/`.jpg`) is added automatically, and an unknown token, an unsafe character, or an app or display name that isn't there falls back to the prefix-based name — no template can move the file out of the destination folder — whether a save is downscaled — off by default: a Retina capture can be written at its logical size (1×) or scaled down to a maximum width, the file only, never an upscale, and the clipboard always carries the full capture — whether a save carries a backdrop — off by default: optional padding (a transparent margin in pixels, 0–128), rounded corners (0–64, never more than half the capture) and a fixed soft shadow around the capture, composed before any downscale so the padding is never resampled on its own, the file only, and the clipboard always carries the capture exactly as it was — and the History pane: every capture the session delivered, newest first, each reopening in the editor by an Open click. The history is kept in memory only — nothing is saved to disk, and quitting Stare forgets it.
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
