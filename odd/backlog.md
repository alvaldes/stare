# Backlog

Known work that is not being done right now. One entry per item: what the user
sees, why it happens, and where it lives. Add at the top; newest first.

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
