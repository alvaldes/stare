# Changelog

Each `## <version>` section becomes that version's GitHub release notes
(`Scripts/release.sh --upload`). Keep each bullet one short line about what a
user gets.

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
