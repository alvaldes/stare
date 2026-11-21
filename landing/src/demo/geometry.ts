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

export function distanceToSegment(p: Point, a: Point, b: Point): number {
  const dx = b.x - a.x
  const dy = b.y - a.y
  const lengthSquared = dx * dx + dy * dy
  if (lengthSquared === 0) return distance(p, a)
  const t = Math.max(0, Math.min(1, ((p.x - a.x) * dx + (p.y - a.y) * dy) / lengthSquared))
  return distance(p, { x: a.x + t * dx, y: a.y + t * dy })
}

/** Distance to an open chain of points; a single point is its own chain. */
export function distanceToPolyline(p: Point, points: readonly Point[]): number {
  if (points.length === 1) return distance(p, points[0])
  let best = Infinity
  for (let i = 1; i < points.length; i++) best = Math.min(best, distanceToSegment(p, points[i - 1], points[i]))
  return best
}

/** The outline of the ellipse inscribed in a rectangle, as a closed polygon. */
export function ellipseOutline(rect: { x: number; y: number; width: number; height: number }, steps = 72): Point[] {
  const cx = rect.x + rect.width / 2
  const cy = rect.y + rect.height / 2
  return Array.from({ length: steps + 1 }, (_, i) => {
    const a = (i / steps) * Math.PI * 2
    return { x: cx + Math.cos(a) * (rect.width / 2), y: cy + Math.sin(a) * (rect.height / 2) }
  })
}
