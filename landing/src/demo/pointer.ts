// The pointer highlight, mirrored from the app: StareCore's PointerStyle (what
// Settings chooses), PointerAppearance (what a renderer needs) and the idle
// fade in OverlayView.
import type { InkId } from './model'

export type PointerPreset = 'ring' | 'squircle' | 'rhombus' | 'dot' | 'spotlight'

/** The shapes Settings offers, in its order. */
export const POINTER_PRESETS: readonly { id: PointerPreset; title: string }[] = [
  { id: 'ring', title: 'Ring' },
  { id: 'squircle', title: 'Squircle' },
  { id: 'rhombus', title: 'Rhombus' },
  { id: 'dot', title: 'Dot' },
  { id: 'spotlight', title: 'Spotlight' },
]

/** A few stops along the app's 32–240 pt slider, its default included. */
export const POINTER_SIZES = [44, 72, 100, 140, 180] as const

export interface PointerLook {
  preset: PointerPreset
  /** Diameter in points. */
  size: number
  ink: InkId
  /** Band thickness as a ratio of the radius. */
  bandWidth: number
  glow: boolean
  border: 'solid' | 'dashed'
  fadeWhenIdle: boolean
  /** Colour from the active ink instead of `ink` (the app's "Follows ink"). */
  followInk: boolean
  /** What a click does: grow with the pulse, or turn with it. */
  clickAnimation: 'scale' | 'rotate'
}

/** PointerStyle.standard: the look a fresh install of Stare gets. */
export const DEFAULT_POINTER: PointerLook = {
  preset: 'rhombus',
  size: 100,
  ink: 'purple',
  bandWidth: 0.1,
  glow: true,
  border: 'dashed',
  fadeWhenIdle: true,
  followInk: false,
  clickAnimation: 'scale',
}

const GLOW_EXTENT = 1.9
const EDGE_WIDTH = 2
const SQUIRCLE_CORNER = 0.62
const IDLE_DELAY_S = 1.2
const IDLE_FADE_S = 0.8
const IDLE_FLOOR = 0.25

export interface PointerAppearance {
  radius: number
  /** The band's inner edge; equals the radius for the filled dot. */
  holeRadius: number
  /** Corner radius of the outer shape; equals the radius for a round ring. */
  corner: number
  /** Degrees the shape turns: the rhombus is the squircle at 45°. */
  rotation: number
  /** Whether a shape is drawn at all; the spotlight is glow alone. */
  shape: boolean
  /** Width of the one bright line on the outer boundary; 0 for dot and spotlight. */
  edgeWidth: number
  /** Dash and gap lengths of a dashed outer line, or null for a solid one. */
  dash: [number, number] | null
  bandFillAlpha: number
  edgeAlpha: number
  /** Where the glow starts and ends, in points from the centre. */
  glowStart: number
  glowRadius: number
  glowStops: { offset: number; alpha: number }[]
}

export function pointerAppearance(look: PointerLook): PointerAppearance {
  const radius = look.size / 2
  const banded = look.preset === 'ring' || look.preset === 'squircle' || look.preset === 'rhombus'
  const band = banded ? radius * look.bandWidth : 0
  const rounded = look.preset === 'squircle' || look.preset === 'rhombus'
  const edgeWidth = banded ? EDGE_WIDTH : 0
  return {
    radius,
    holeRadius: radius - band,
    corner: rounded ? radius * SQUIRCLE_CORNER : radius,
    rotation: look.preset === 'rhombus' ? 45 : 0,
    shape: look.preset !== 'spotlight',
    edgeWidth,
    // PointerHighlightRenderer.dashPattern: three line widths on, two off.
    dash: banded && look.border === 'dashed' ? [edgeWidth * 3, edgeWidth * 2] : null,
    bandFillAlpha: 0.55,
    edgeAlpha: 0.95,
    glowStart: look.preset === 'spotlight' ? 0 : look.preset === 'dot' ? radius : radius - band,
    glowRadius: radius * GLOW_EXTENT,
    glowStops: look.glow
      ? [
          { offset: 0, alpha: 0.26 },
          { offset: 0.55, alpha: 0.1 },
          { offset: 1, alpha: 0 },
        ]
      : [],
  }
}

/** Opacity after the pointer has been still for `idleSeconds`. */
export function idleOpacity(idleSeconds: number): number {
  if (idleSeconds <= IDLE_DELAY_S) return 1
  const progress = Math.min(1, (idleSeconds - IDLE_DELAY_S) / IDLE_FADE_S)
  return 1 - (1 - IDLE_FLOOR) * progress
}

/** The ink the highlight draws in: its own, or the active one when it follows the ink. */
export function pointerInk(look: PointerLook, activeInk: InkId): InkId {
  return look.followInk ? activeInk : look.ink
}

// StareCore's PointerPulse: a quick rise, a small dip, then a settle back to 1.
const PULSE_RISE_S = 0.09
const PULSE_DIP_S = 0.08
const PULSE_SETTLE_S = 0.28
const PULSE_PEAK = 1.35
const PULSE_DIP = 0.94
export const PULSE_DURATION_S = PULSE_RISE_S + PULSE_DIP_S + PULSE_SETTLE_S

/** OverlayView.clickRotateRadiansPerScale: the peak turns the shape about 12°. */
const ROTATE_RADIANS_PER_SCALE = 0.6

const easeOutCubic = (t: number) => 1 - (1 - Math.min(1, Math.max(0, t))) ** 3
const easeInOutSine = (t: number) => (1 - Math.cos(Math.PI * Math.min(1, Math.max(0, t)))) / 2

/** The click pulse's scale, `elapsed` seconds after the click. */
export function pulseScale(elapsed: number): number {
  if (elapsed < 0) return 1
  if (elapsed <= PULSE_RISE_S) return 1 + (PULSE_PEAK - 1) * easeOutCubic(elapsed / PULSE_RISE_S)
  const dipEnd = PULSE_RISE_S + PULSE_DIP_S
  if (elapsed <= dipEnd) return PULSE_PEAK + (PULSE_DIP - PULSE_PEAK) * easeInOutSine((elapsed - PULSE_RISE_S) / PULSE_DIP_S)
  if (elapsed >= dipEnd + PULSE_SETTLE_S) return 1
  return PULSE_DIP + (1 - PULSE_DIP) * easeInOutSine((elapsed - dipEnd) / PULSE_SETTLE_S)
}

/** Scale grows with the pulse; Rotate rides the same envelope as a turn, in degrees, at its own size. */
export function clickTransform(animation: PointerLook['clickAnimation'], elapsed: number): { scale: number; rotation: number } {
  const pulse = pulseScale(elapsed)
  if (animation === 'scale') return { scale: pulse, rotation: 0 }
  return { scale: 1, rotation: ((pulse - 1) * ROTATE_RADIANS_PER_SCALE * 180) / Math.PI }
}
