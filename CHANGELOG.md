# Changelog

Each `## <version>` section becomes that version's GitHub release notes
(`Scripts/release.sh --upload`). Keep each bullet one short line about what a
user gets.

## Unreleased

- Drawing: `⌘Z` brings back everything `Escape` cleared, and `⇧⌘Z` clears it again
- Drawing: every tool shows its own cursor
- Pointer tool: drag a box to select everything under it, `⇧`-click to add or remove a mark, and move the whole selection as one undoable step
- Toolbar: a `⠇⠇` grip moves the bar and right-click puts it back
- Pointer Highlight: a fresh install starts on the rhombus with a dashed border, a fixed purple and 100 pt
- Marks and board pages now survive quitting Stare and leaving the modes, until the machine restarts, with a Settings switch for the old ephemeral behaviour
- Capture editor: choosing the crop only stages a rectangle — move or resize it as long as you like, then `↵` cuts it; `Esc` drops it and `⌘Z` returns the previous crop
- Bar: Settings now organises the toolbar the way Bartender does — a live preview of the bar next to a pool of tools and separators, arranged by dragging, with the bar following every drop
- Settings now chooses the bar's orientation and the edge it docks to (top or bottom when horizontal, left or right when vertical), which tools it shows, and in which order
- Board: `⌘` + scroll zooms in one smooth gesture — no contrary kicks, no momentum overshoot — and the pointer turns into a hand while you pan and a magnifier while you zoom
- Editor: the copy you save puts your marks exactly where you drew them, letterboxed windows included

## 0.3.0

- First run: the Setup Guide is redesigned — one card per state with a single primary action, the app's real logo, Return to continue and Escape to leave
- Screen Recording: the permission probe targets the display of the frontmost window, never asks for a degenerate capture size, bounds its wait, and the pending-restart message names re-authorizing in System Settings
- Screen Recording: a probe that stalls recovers on its own within seconds instead of reporting "cannot capture" until Stare restarts
- First run: a setup guide opens System Settings at the Screen Recording pane, notices the grant when you come back, and continues into Settings
- Rebuilt Settings window: a resizable sidebar of sections — General, Tools, Shortcuts, Pointer Highlight, Capture, Whiteboard, Permissions, About — with every change applied live
- Pointer highlight styles: five shapes (Ring, Squircle, Rhombus, Dot, Spotlight) with size, colour, band, glow, plus a live preview drawn by the overlay's own renderer
- Pointer highlight extras: a Solid or Dashed border, an adjustable opacity, and a Rotate click animation next to the existing Scale pulse
- Every global shortcut and tool key is rebindable from Settings, with conflict checks and a visible refusal
- Captures can go to a folder instead of the clipboard, saved as PNG or JPEG with a name prefix you choose
- The whiteboard can open with black pages and a chosen page count
- The board's blur diffuses the board's own content, not the screen behind it — the board never asks for Screen Recording
- The board opens on System (white in light mode, black in dark mode, resolved when the board opens), White or Black pages, and you choose its display scope (every display or only the active one) and its own border toggle in Settings
- The board zooms with the pan (pinch, `⌘+`/`⌘−`, `⌘0` resets both) under a Freeform-style dot grid
- Launch at login, with the login item's real status shown
- Update check that names the latest release and links to it — Stare is not notarized, so it never installs anything itself

## 0.2.0

- New logo: the open nib in the menu bar and as the app icon
- Whiteboard: endless white and black pages, `⌥⇧W` to open, `⌘←`/`⌘→` to flip, pan with space or middle-drag
- Pin: `⌥⇧P` keeps the marks on screen while clicks pass through to the apps underneath
- Redo: `⇧⌘Z` across displays, next to undo in the palette
- Blur tool: `B` blurs the captured pixels of the area under the marks (needs Screen Recording; on the whiteboard it shows a neutral fallback)
- The pointer highlight pulses when you click, so a click reads as a click on a shared screen
- Captures name the display of the real front window, found in the window list, not the frontmost app's first window
- The palette groups the tools by family and finally shows redo

## 0.1.0

- First working version: draw over the screen with pen, highlighter, shapes, text, numbered steps and a laser
- Eight inks, undo, and per-tool shortcuts
- Capture the screen or an area with the marks composed in, and paste it anywhere from the capture card
- Edit a capture in the built-in editor, with the same tools, inks and crop
