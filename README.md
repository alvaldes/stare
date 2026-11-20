# Stare

Native macOS menu bar app for drawing over the live screen, capturing the screen
with those marks, and pasting the result anywhere. macOS 26, Swift, no Electron,
no account, no subscription.

Press `⌥⇧A` to draw, `S` to capture, `Esc` to clear and leave.

## Build and run

```sh
swift build                 # compile
swift test                  # 58 unit tests, no GUI needed
Scripts/bundle.sh           # release build -> build/Stare.app
Scripts/bundle.sh release install   # also copies to /Applications
```

`Scripts/bundle.sh` signs with the first available "Apple Development" identity,
or with `CODESIGN_IDENTITY` if you set it. Ad-hoc signing (`-`) works, but macOS
forgets the Screen Recording grant on every rebuild, because TCC keys the grant to
the code requirement.

Diagnostics: the app writes nothing by default. Launch with `STARE_DIAG=1` to make
it append to `/tmp/stare.log`. `Stare --selftest` writes
`/tmp/stare-selftest.txt`, offscreen renders of the palette, the editor chrome and
the settings form in both system appearances, and a mark-composition PNG.

## Keyboard

| Where | Keys |
| --- | --- |
| Anywhere | `⌥⇧A` draw over the screen · `⌥⇧M` pointer highlight |
| Drawing | `P` pen · `H` highlighter · `A` arrow · `L` line · `R` rectangle · `O` ellipse · `T` text · `C` numbered step · `F` laser · `E` eraser |
| Drawing | `1`–`8` inks (red, orange, yellow, green, blue, purple, white, black) · `⌘Z` undo (across displays) · `Esc` clear and leave |
| Drawing | hold `⇧` for a straight line with pen/highlighter, or a square/circle with rectangle/ellipse |
| Drawing | `S` capture the display · `⇧S` drag an area (the rest dims) |
| Capture card | hover keeps it alive · click opens the editor · drag it into another app |
| Editor | same tools and inks · `⌘Z` undo · `Esc` cancels a crop, then closes |

## Structure

```
Sources/StareCore/        no AppKit: geometry, session, shortcuts, compositing
  Tool Ink Stroke         the model: instruments, inks, one mark
  PathBuilder             freehand smoothing, arrow heads, shapes, badges
  DrawingSession          begin/extend/commit, undo, erase, transient pruning
  MarkRenderer            draws marks into any CGContext
  MarkCompositor          recomposes marks over a captured frame at pixel scale
  CoordinateMapping       AppKit <-> overlay <-> capture pixels
  ShortcutRouter          one mapping from key press to tool or ink

Sources/Stare/            AppKit and SwiftUI
  OverlayController       one window per display, the two modes, capture, undo order
  OverlayWindow/View      the transparent drawing layer and its input
  ToolbarPanel/View       the floating palette (also the editor's bar)
  CaptureService          ScreenCaptureKit, permission, own windows excluded
  CaptureCard             the corner card with drag-out
  CaptureEditor           editor window, canvas, crop, copy, save
  SettingsView/Controller every preference in one window
  GlobalHotkey            Carbon hotkeys, no Accessibility permission
  EditorState             preferences and current tool/ink
  SelfTest Diag           development verification and optional tracing
```

## Decisions worth not re-learning

- **The overlay never reads pixels**, so drawing needs no TCC permission. Every
  pixel-reading feature (capture) is gated separately.
- **Captures are recomposed, not photographed.** `MarkCompositor` redraws the
  vector marks over the ScreenCaptureKit frame, and the capture filter excludes
  Stare's own windows. That is why the palette, the drawing frame and the pointer
  highlight never appear, with no hiding and no timing race. The laser is
  transient and is never composed.
- **Never use `.canJoinAllSpaces` on the overlay** together with `NSPanel`. The
  window server draws it on every Space but treats it as a non-interactive ghost:
  it stays key (tool keys work) while clicks and cursor updates go nowhere. A
  plain borderless `NSWindow` that overrides `canBecomeKey`, plus re-ordering on
  `NSWorkspace.activeSpaceDidChangeNotification`, is the configuration that works.
- **The pointer highlight is its own mode**, not a drawing tool: `⌥⇧M` shows a
  click-through layer that follows `NSEvent.mouseLocation` at 60Hz. It needs no
  permission, unlike a global event tap, and it never activates Stare.
- **Retina captures need `CGDisplayCopyDisplayMode(...).pixelWidth`.** On a
  3840-wide screen `CGDisplayPixelsWide` reports 1920, so trusting it halves the
  capture resolution.
- **`NSHostingView.fittingSize` is zero before layout.** A window sized from it is
  created and never seen. Use a fixed content size.
- **Return in an `NSTextField` must read the field editor** (`textView.string`),
  not the cell: the cell may not hold the latest keystrokes.
- **Leaving drawing mode must not always restore focus.** When one of our windows
  takes over (the editor), handing focus back to the previous app races with our
  own window and buries it.
- Palette colours are semantic (`primary`/`secondary`), because white glyphs wash
  out in light mode. Verified by rendering in `aqua` and `darkAqua`.

## What is deliberately out of v0.1

Share links, whiteboard pages, voice briefs, the local MCP server, blur (B), pin,
redo, and any telemetry or updater. See `odd/tasks/core-overlay-capture.md` for the
full spec list (S1–S35) and the log of every correction.

## Roadmap when work resumes

1. **Distribution** — Developer ID Application certificate, hardened runtime,
   `notarytool` submit and staple, DMG, and a download page. The app currently
   runs from `/Applications` signed with an Apple Development identity.
2. **v0.2 features** — blur (needs screen pixels, so it joins the capture
   permission), pages with an endless whiteboard and blackboard, redo, and pin so
   marks stay while clicks pass through.
3. **Polish already identified** — click animation for the pointer highlight
   (scale pulse), and a real "front window's display" check beyond the current
   window-list heuristic.
