import { ARROW_HEAD_HALF_ANGLE, ARROW_HEAD_LENGTH, type Point } from './model'

/** The two barbs of the arrow head, ported from StareCore's PathBuilder. */
export function arrowHeadBarbs(start: Point, end: Point, weight = 1): Point[] {
  const dx = end.x - start.x
  const dy = end.y - start.y
  const length = Math.hypot(dx, dy)
  if (length <= 0.001) return []

  const shaft = Math.atan2(dy, dx)
  // A short stroke must not grow barbs longer than itself.
  const barbLength = Math.min(ARROW_HEAD_LENGTH * weight, length * 0.6)

  return [ARROW_HEAD_HALF_ANGLE, -ARROW_HEAD_HALF_ANGLE].map((offset) => {
    const angle = shaft + offset
    return { x: end.x - Math.cos(angle) * barbLength, y: end.y - Math.sin(angle) * barbLength }
  })
}

export function normalizedRect(a: Point, b: Point) {
  return {
    x: Math.min(a.x, b.x),
    y: Math.min(a.y, b.y),
    width: Math.abs(b.x - a.x),
    height: Math.abs(b.y - a.y),
  }
}

export function distance(a: Point, b: Point): number {
  return Math.hypot(b.x - a.x, b.y - a.y)
}
