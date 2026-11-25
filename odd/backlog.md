# Backlog

Known work that is not being done right now. One entry per item: what the user
sees, why it happens, and where it lives. Add at the top; newest first.

## The inks still make the vertical bar long

- **What the user sees**: a vertical bar is still a tall column even after the
  extras moved behind the more button. The owner has named it twice as the real
  size problem for the vertical case.
- **Why**: the shorter default only bought ~68 pt (742 against 810), because five
  tools leave the column while four separators and the more button join it. The
  two structures that dominate a vertical bar are now the **eight ink swatches**
  (224 pt, 30 % of the column) and the **five-item tail** (undo, redo, clear,
  close, gripper — 150 pt).
- **Where**: `Sources/Stare/ToolbarView.swift` (`barItems`: `ForEach(Ink.allCases)`
  draws one row per ink unconditionally, whichever way the bar stacks).
- **Direction of the fix**: lay the inks out as a **two-column grid when the bar
  is vertical** (four rows instead of eight, ~112 pt saved) and leave the tail
  alone. It is a visible layout change nobody has asked for yet, so it is the
  owner's call, not an agent's — pin it with the vertical bar's fitting height
  before and after, and keep the horizontal bar's single row untouched.
- **Reported**: 2026-11-25, as the open product decision when the bar-overflow
  batch closed.

## The extras panel ignores where the bar actually is

- **What the user sees** (owner, verbatim): "el bar esta vertical left pero lo
  muevo a la derecha completamente y presiono '...' y se abre a la derecha de la
  bar cuando en realidad deberia abrirse a la izquierda porque a la derecha no
  hay espacio."
- **Why**: `ToolbarOverflowPlacement.panelFrame` decides the side from the
  `ToolbarBorder` the bar is *docked* to — the setting — not from where the bar
  actually sits. Dragging the bar by its gripper moves the window without
  changing the border, so a bar docked `left` and parked against the right edge
  still opens its panel to the right, off the screen. The clamp then slides it
  back, which is why it reads as "opens on the wrong side" rather than "opens
  off screen".
- **Where**: `Sources/StareCore/ToolbarOverflowPlacement.swift` (the side rule),
  `Sources/Stare/OverlayController.swift` (`toggleOverflowPanel` passes
  `state.toolbarBorder.docked(for:)`).
- **Direction of the fix**: choose the side from the room available, not from the
  setting — open toward the middle of the screen when the bar is where the setting
  says, and otherwise toward whichever side has room for the panel; fall back to
  the setting only when both sides fit. Pin it with the four docked borders plus
  the "docked left, parked right" case, which is the one that is broken today.
- **Reported**: 2026-11-25, after the bar-overflow batch was accepted.
