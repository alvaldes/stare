# Developing Stare

How to build, sign, release and debug Stare, and the decisions that are worth
not re-learning. For what Stare does, see the [README](../README.md).

## Build and run

```sh
swift build                 # compile
swift test                  # unit tests, no GUI needed
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
`/tmp/stare-selftest.txt`, offscreen renders of the palette, the editor chrome
and every Settings pane in both system appearances, a mark-composition PNG, a
blur-composition check with its measured pixels, pointer-pulse renders with
their measured extents, and the front-window display mapping with the window
frame and display frames it used.

Its checked sections each end in one `result=` line, expected `PASS`:
`select`, `board`, `blur` and `pointer pulse` for the drawing and capture
core; `settings panes … areas=8` and `settings window` for the settings shell
(every pane rendered in light and dark; the window visible, resizable and
wider than the old fixed 420-pt form); `tools pane` (a tool-shortcut rebind
as the overlay's router sees it, with conflict and unsupported-key refusals
leaving the map unchanged); `hotkeys pane` (the four default global hotkeys
registered through the real Carbon path, a rebound key re-registered, a
modifier-less key refused while the previous binding stays); `general pane`
(the update due-check runs without contacting the release feed when not due);
`capture pane` (a folder-destination capture lands as a correctly named,
decodable file through the real delivery tail, and the clipboard path writes
nothing); `whiteboard pane` (a fresh board opens with the persisted
background and page count); `marker styles … presets=5` (all five pointer
presets drawn through the Settings preview, with painted-pixel checks); and
`onboarding` (the guide's window can become key from the accessory app, and
any close marks the guide as seen). The scratch directories the capture and
whiteboard sections create are removed before the report returns.

## Signing and the Screen Recording grant

Every release is signed with the same Apple Development identity, and macOS
keys the Screen Recording grant to that signature, so updates keep the grant.
The certificate itself expires (the current one on 2027-10-24), and renewing it
resets the grant once for every user.

## Architecture

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
  OnboardingWindow/View   the first-run guide and its handoff to Settings
  SettingsView/Controller the settings window: a sidebar of areas, panes of cards
  PreferencesModel        the one persisted preferences blob, saved whole on every change
  GlobalHotkey            Carbon hotkeys, no Accessibility permission
  EditorState             current tool/ink and mirrors, written through PreferencesModel
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


## History

Every spec, task and user correction is logged in [`odd/tasks/`](../odd/tasks/):
`core-overlay-capture.md` (v0.1), `v0.2.md`, `landing.md` and
`onboarding-settings.md`. Release notes are in
[CHANGELOG.md](../CHANGELOG.md).
