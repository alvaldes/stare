# Changelog

Each `## <version>` section becomes that version's GitHub release notes
(`Scripts/release.sh --upload`). Keep each bullet one short line about what a
user gets.

## Unreleased

- First run: a setup guide opens System Settings at the Screen Recording pane, notices the grant when you come back, and continues into Settings
- Rebuilt Settings window: a resizable sidebar of sections — General, Tools, Shortcuts, Pointer Highlight, Capture, Whiteboard, Permissions, About — with every change applied live
- Pointer highlight styles: six shapes (Ring, Squircle, Dot, Marker tip, Spotlight, Rhombus) with size, colour, band, glow, plus a live preview drawn by the overlay's own renderer
- Pointer highlight extras: a Solid or Dashed border, an adjustable opacity, and a Rotate click animation next to the existing Scale pulse
- Every global shortcut and tool key is rebindable from Settings, with conflict checks and a visible refusal
- Captures can go to a folder instead of the clipboard, saved as PNG or JPEG with a name prefix you choose
- The whiteboard can open with black pages and a chosen page count
- Whiteboard: a System default that opens pages white in light mode and black in dark mode, resolved when the board opens
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
