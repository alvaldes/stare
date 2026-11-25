# Changelog

Each `## <version>` section becomes that version's GitHub release notes
(`Scripts/release.sh --upload`). Keep each bullet one short line about what a
user gets.

## Unreleased

- Bar: the tools that are not the main ones move behind a more button (three dots), so the bar stops growing — most of all when it stands vertical. A fresh install keeps the pointer, pen, highlighter, arrow, rectangle, ellipse, text and eraser on the bar, and line, numbered step, blur, spotlight and laser hide behind it: click it and a small panel opens beside the bar, toward the middle of the screen instead of off the edge it is docked to; pick a tool and the panel closes with that tool's icon left on the button, so the bar always says which tool is armed. Every tool keeps its own key wherever it lives, and Settings decides what sits on the bar and what hides behind the button
- Settings: the pool is the bar's hidden section now, not a shelf of discards — the **More tools** card lists what hides behind the more button, says so, and is never empty on a fresh install, with a roomy "Hide it here" target to drop a bar tool onto; the bar preview draws the same button the real bar draws
- Drawing: the spotlight joins the tools (`D`) — drag a region and everything outside it dims in the capture, fading away from the region's edge in one soft gradient whose width scales with the region, so the light reads as light rather than a pasted shape; while you are still dragging it previews as a plain ellipse outline (the ellipse tool's own look, no dim anywhere) and the dim paints once the mark is committed, so a capture always carries the full dim; it is a mark like any other, so undo, redo, the eraser, moving and the editor all treat it as one, it works on the whiteboard and in the capture editor, and it carries no ink of its own — the ink keys keep working while it is selected
- Drawing: annotation depth — `9` toggles whether the next rectangle or ellipse is drawn filled or outline-only, and `0` cycles the next arrow's head between the plain open barbs and a solid one; the style is a property of the mark itself, so shapes keep whatever they were drawn with through undo, redo and every capture, and a rebound tool shortcut always wins over the plain keys. The next text mark starts with the style the last one was typed at (its size and ink); the memory is session-scoped, nothing persists
- Capture: downscaling on save, off by default — Settings → Capture can write a Retina capture at its logical size (1×) or scaled down to a maximum width instead of its full pixel size; the saved file only, the clipboard always gets the full image, and smaller captures are never upscaled
- Capture: new `⌥⇧O` — drag an area anywhere (no drawing session needed) and the text it holds, plus a QR code if that is what you framed, lands on the clipboard as plain text; recognition runs on-device with Vision and nothing is uploaded, and the same gesture works from the menu bar's "Recognise Text"
- Capture: the OCR gesture answers every dead end plainly instead of clobbering your clipboard: pressing `⌥⇧O` immediately dims the display with "Drag over text to copy it · Esc to cancel", so the gesture is visible before you drag, the pointer becomes the crosshair the capture area drag shows for the whole gesture and puts the normal cursor back however it ends (commit, `Esc`, or a second press), a magnifier follows the drag showing the display as the gesture opened so the exact pixel edge is visible, and a second press cancels it; without Screen Recording it points at System Settings (never a prompt mid-gesture), an empty selection or a failed read shows "No text found" / "Text recognition failed", and `Esc` cancels the drag with everything left as it was
- Capture: pin an image with its own action, distinct from pinning your marks — the capture card's pin button (and the menu's Pin Image for the latest capture) floats the captured picture as a borderless always-on-top window beside the capture card in the same screen corner, never in the middle of the display: drag it anywhere, scroll to resize, ⌥-scroll to change its opacity, and its 📌, ✕ and 🔒 stay visible without hovering — 📌 and ✕ close it, 🔒 makes it click-through so you can work underneath it; several pinned images coexist, and they stay on screen no matter what you open or close in Stare — all in memory, nothing written to disk
- Capture: the pinned image closes the way you press toward it — Pin Image is a toggle (a second press takes the frontmost pin down, the card's pin button keeps its deliberate multi-pin path), the 📌 badge, ✕ and 🔒 stay drawn and clickable in every state (hovering no longer decides whether you can close), and a pin shortcut that cannot act right now (`⌥⇧I` with nothing captured yet) says so on screen — no more silently stacking pins, no more clicks landing in the app underneath when you meant to close one, no more dead keys; the lock has no keyboard shortcut, the 🔒 on the pin is the affordance
- Capture: the session's captures stay reachable in Settings → Capture → History — reopen any of the last captures of this session in the editor with one click, even after its card has faded away; the history lives in memory and clears when Stare quits
- Settings: "Draw on" defaults to the active display instead of every display, so a second monitor is never covered by a sheet nobody asked for
- Capture: the `⇧S` area drag follows the pointer with a magnifier over the frozen frame, so the exact pixel edge you are choosing is visible, and it stays clear of the pixel it magnifies — near a display edge it flips to the other side; without Screen Recording the drag runs live as before and the magnifier stays away
- Capture: the last `⇧S` area is remembered for the session — press `⇧S` again and it is already framed: `Return` captures it with no dragging, dragging replaces it, and leaving the overlay forgets it
- Capture: the `⇧S` area drag runs on a frame taken when drawing mode opened and refreshed after each capture, so the frozen frame already exists before you press `⇧S` — hover states and tooltips cannot vanish while you choose the area, existing blur marks blur the frozen content, and the captured pixels are exactly the frame you framed; the frame is as fresh as your last capture (without Screen Recording the drag runs live as before and the magnifier stays away), and `Esc` or a stray click brings the live screen back
- Capture: `⌥S` captures just the front window, with your marks composited onto it
- Capture: dragging an area is clamped to the display so it can never reach outside it, and holding `⇧` while dragging forces a square
- Capture: name templates for folder saves — write file names from the tokens `{date}`, `{time}`, `{app}` and `{display}` (for example `{app}-{date}_{time}`); an empty template keeps the prefix name as today, and a template with an unknown token, unsafe characters, or an app or display name that isn't there falls back to it, so a template can rename a capture inside the destination folder but never move it out
- Capture: a backdrop on folder saves, off by default — optional padding, rounded corners and a fixed soft shadow around the capture in Settings → Capture; the backdrop is composed before any downscale so the padding is never resampled on its own, sizes are clamped so a silly value can neither blank the capture nor grow the file enormous, and the clipboard always carries the capture exactly as it was
- Settings: regrouped into Capture, Draw, Pointer, Board and System, with the bar, the overlay and the laser on panes of their own instead of inside General
- Settings: the pointer highlight and the bar are previewed in a fixed stage above the controls, so a change is visible while you make it
- Settings: the pointer preview is shorter, and the bar's Placement card fills the pane instead of stopping short of its right edge
- Drawing: `⌘Z` brings back everything `Escape` cleared, and `⇧⌘Z` clears it again
- Drawing: every tool shows its own cursor
- Drawing: a blur mark can pixelate instead — one Redaction choice in Settings → Tools, and everything the mark touches saves exactly what it shows
- Pointer tool: drag a box to select everything under it, `⇧`-click to add or remove a mark, and move the whole selection as one undoable step
- Toolbar: a `⠇⠇` grip moves the bar and right-click puts it back
- Toolbar: a vertical bar sits as far from the side edge as a horizontal one does from the top or bottom
- Pointer Highlight: a fresh install starts on the rhombus with a dashed border, a fixed purple and 100 pt
- Marks and board pages now survive quitting Stare and leaving the modes, until the machine restarts, with a Settings switch for the old ephemeral behaviour
- Capture editor: choosing the crop only stages a rectangle — move or resize it as long as you like, then `↵` cuts it; `Esc` drops it and `⌘Z` returns the previous crop
- Capture editor: zoom and pan to annotate a fine detail — `⌘+`/`⌘−`/`⌘0`, `⌘` + scroll or pinch zoom about the pointer, plain scroll or space-drag pans, and a zoomed or panned stroke still saves exactly the pixels the fit drawing would save; the tool keys never change
- Capture editor: drop an image on the window to stack it over the capture — hold `⌥` to move, resize or select it, `⌫` deletes it and `[`/`]` restack it, saving exactly what the canvas shows
- Capture editor: `⌘V` pastes an image from the clipboard onto the canvas, centred in the view and clamped exactly like a dropped image, and one `⌘Z` takes it back
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
- Whiteboard: with the board open, picking a capture in the history (`⌥⇧I`) pastes it onto the current page instead of copying — one image per page, it pans and zooms with the page, shows in captures and under blur marks, `⌥`-drag moves or resizes it and `⌫` removes it, and it lives for the session without ever being written to disk
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

- Capture card: smaller, with a pin that keeps it exactly where you left it — later captures stack next to it instead of pushing it, and the cap that closes old cards never touches a pinned one — and a close that takes it away
- Capture history: `⌥⇧I` opens a paste-style panel of your newest 50 captures — arrows to move, `↵` to copy one to the clipboard, Clear to empty it — and it stays on disk (Application Support) until you clear it, with the drawing mode yielding to the panel while the whiteboard keeps running under it