# Stare

Native macOS menu bar app for drawing over the live screen, capturing the screen
with those marks, and pasting the result anywhere. macOS 26, Swift, no Electron,
no account, no subscription.

Press `⌥⇧A` to draw over the screen, `⌥⇧W` for the whiteboard, `S` to capture,
`Esc` to clear and leave.

## Install

Stare needs macOS 26 or later.

1. Download [Stare.dmg](https://github.com/alvaldes/stare/releases/latest/download/Stare.dmg), open it and drag Stare to Applications. Or install it with [Homebrew](https://brew.sh):

   ```sh
   brew install --cask alvaldes/tap/stare
   ```

2. Open Stare from Applications. Stare is not notarized (no Apple Developer account behind it), but only a browser download gets the Gatekeeper stop: Homebrew does not quarantine its downloads, so `brew install --cask` opens Stare without a prompt, while a browser-downloaded Stare.dmg is stopped the first time — choose **Done**, then open System Settings → Privacy & Security and click **Open Anyway** next to “Stare.app” was blocked. Removing the quarantine flag also works: `xattr -d com.apple.quarantine /Applications/Stare.app`.
3. Allow Stare in **Screen Recording** when it asks (System Settings → Privacy & Security → Screen Recording). Only capturing needs it; drawing does not. Grant it once and updates keep it, because every release is signed with the same Apple Development identity and macOS keys the grant to that signature — but the certificate itself expires (2026-04-15), and renewing it resets the grant.
4. Press `⌥⇧A` to draw over the screen.

## Build and run

```sh
swift build                 # compile
swift test                  # 95 unit tests, no GUI needed
Scripts/bundle.sh           # release build -> build/Stare.app
Scripts/bundle.sh release install   # also copies to /Applications
```

`Scripts/bundle.sh` signs with the first available "Apple Development" identity,
or with `CODESIGN_IDENTITY` if you set it. Ad-hoc signing (`-`) works, but macOS
forgets the Screen Recording grant on every rebuild, because TCC keys the grant to
the code requirement.

`Scripts/release.sh` packs the signed release build into `dist/Stare.dmg` (the
name never changes, so the landing can link to
`releases/latest/download/Stare.dmg`; the volume name carries the version).
Without `--upload` it works in a dirty tree and on an untagged HEAD — the
clean-tree and tag checks belong to `--upload` only, which also publishes the
GitHub release with the version's `CHANGELOG.md` section as notes and rewrites
the Homebrew cask's `version` and `sha256` in
[alvaldes/homebrew-tap](https://github.com/alvaldes/homebrew-tap). Like
`bundle.sh`, the release refuses ad-hoc signatures.

Diagnostics: the app writes nothing by default. Launch with `STARE_DIAG=1` to make
it append to `/tmp/stare.log`. `Stare --selftest` writes
`/tmp/stare-selftest.txt`, offscreen renders of the palette, the editor chrome and
the settings form in both system appearances, a mark-composition PNG, a
blur-composition check with its measured pixels, pointer-pulse renders with
their measured extents, and the front-window display mapping with the window
frame and display frames it used.

## Keyboard

| Where | Keys |
| --- | --- |
| Anywhere | `⌥⇧A` draw over the screen · `⌥⇧W` whiteboard · `⌥⇧M` pointer highlight · `⌥⇧P` pin or unpin the drawing so clicks pass through |
| Pointer highlight | clicks pulse the highlight (grow and settle), so a click reads as a click on a shared screen · works over any app, no permission |
| Drawing | `P` pen · `H` highlighter · `A` arrow · `L` line · `R` rectangle · `O` ellipse · `T` text · `C` numbered step · `F` laser · `B` blur · `E` eraser |
| Drawing | `1`–`8` inks (red, orange, yellow, green, blue, purple, white, black) · `⌘Z` undo · `⇧⌘Z` redo (across displays) · `Esc` clear and leave |
| Drawing | hold `⇧` for a straight line with pen/highlighter, or a square/circle with rectangle/ellipse |
| Drawing | `S` capture the display · `⇧S` drag an area (the rest dims) |
| Whiteboard | `‹` `›` buttons in the palette, or `⌘←` `⌘→` — going past the last page creates one inheriting its background, `‹` at page 1 stays put |
| Whiteboard | `⌘B` flips the current page between white and black; inks are never remapped, so a mark colour that vanishes against the background is your call |
| Whiteboard | hold space and drag, or middle-drag, to pan the endless canvas; marks keep their position when the display changes |
| Whiteboard | `S` capture composes the marks over the page's own background colour, no Screen Recording permission needed · `Esc` closes the board and keeps the pages for the session |
| Capture card | hover keeps it alive · click opens the editor · drag it into another app |
| Editor | same tools and inks · `⌘Z` undo · `⇧⌘Z` redo · `Esc` cancels a crop, then closes |

## Structure

```
Sources/StareCore/        no AppKit: geometry, session, shortcuts, compositing
  Tool Ink Stroke         the model: instruments, inks, one mark
  PathBuilder             freehand smoothing, arrow heads, shapes, badges
  DrawingSession          begin/extend/commit, undo, erase, transient pruning
  WhiteboardPages         per-display pages: marks, background, pan offset
  MarkRenderer            draws marks into any CGContext
  MarkCompositor          recomposes marks over a captured frame at pixel scale
  CoordinateMapping       AppKit <-> overlay <-> capture pixels
  ShortcutRouter          one mapping from key press to tool or ink

Sources/Stare/            AppKit and SwiftUI
  OverlayController       one window per display, the two modes, capture, undo order
  OverlayWindow/View      the transparent drawing layer and its input
  WhiteboardView          the opaque board: pages, background colour, pan
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
  permission, unlike a global event tap, and it never activates Stare. A click
  makes it pulse — grow and settle over 0.45s — and the pulse reads the mouse
  button by polling `CGEventSource.buttonState` from the same 60Hz timer, which
  also needs no permission, so pointer mode stays permission-free.
- **The "front window's display" answer comes from the real window list**:
  `FrontWindowLocator` takes the front-most layer-0 on-screen window that is
  not Stare's own from `CGWindowListCopyWindowInfo` and maps its bounds to a
  display through the pure `FrontWindowDisplay` mapping (StareCore). The old
  frontmost-application heuristic stays as the fallback when the list has no
  such window. Reading the list needs no Accessibility permission.
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

1. **Distribution** — a GitHub release with a fixed-name `Stare.dmg` built and
   packed by `Scripts/release.sh` (`--upload` attaches it to the version tag,
   sets the release notes from `CHANGELOG.md` and rewrites the Homebrew cask),
   installed with `brew install --cask alvaldes/tap/stare`. There is no Apple
   Developer account, so no notarization and no Developer ID: a browser-downloaded DMG needs the Privacy & Security confirmation on first launch (a Homebrew
   install does not), and updates keep the Screen Recording grant only as long
   as the signing identity stays the same — a renewed certificate resets it. See
   [Install](#install). *(Done in T10; see `odd/tasks/v0.2.md`.)*
2. **v0.2 features** — blur (needs screen pixels, so it joins the capture
   permission), pages with an endless whiteboard and blackboard, redo, and pin so
   marks stay while clicks pass through.
3. **Polish already identified** — click animation for the pointer highlight
   (scale pulse), and a real "front window's display" check beyond the current
   window-list heuristic. *(Done in T7: the click pulse and the z-order window
   lookup landed; see `odd/tasks/v0.2.md`.)*
