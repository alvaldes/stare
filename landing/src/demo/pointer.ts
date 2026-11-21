// The pointer highlight's geometry, mirrored from the app (OverlayView's
// drawCursorFrame and SettingsView's "Pointer highlight" section).

export const POINTER_SIZES = [32, 44, 60, 72, 80] as const
export type PointerShape = 'circle' | 'squircle'

const BAND_RATIO = 0.26
const GLOW_MULTIPLIER = 1.9
const SQUIRCLE_CORNER = 0.62
const IDLE_DELAY_S = 1.2
const IDLE_FADE_S = 0.8
const IDLE_FLOOR = 0.25

export interface PointerRing {
  radius: number
  /** Width of the translucent band between the two bright edges. */
  band: number
  glowRadius: number
  /** Corner radius of the outer shape; equals the radius for a circle. */
  corner: number
}

/** Size is the ring's diameter in points, as in the app's settings. */
export function pointerRing(size: number, shape: PointerShape): PointerRing {
  const radius = size / 2
  return {
    radius,
    band: radius * BAND_RATIO,
    glowRadius: radius * GLOW_MULTIPLIER,
    corner: shape === 'squircle' ? radius * SQUIRCLE_CORNER : radius,
  }
}

/** Opacity after the pointer has been still for `idleSeconds`. */
export function idleOpacity(idleSeconds: number): number {
  if (idleSeconds <= IDLE_DELAY_S) return 1
  const progress = Math.min(1, (idleSeconds - IDLE_DELAY_S) / IDLE_FADE_S)
  return 1 - (1 - IDLE_FLOOR) * progress
}
