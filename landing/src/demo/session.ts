import { arrowHeadBarbs, distance, distanceToPolyline, ellipseOutline, normalizedRect } from './geometry'
import {
  BADGE_DIAMETER,
  type InkId,
  isTransient,
  LASER_LIFETIME_MS,
  lineWidth,
  type Mark,
  MINIMUM_SAMPLE_DISTANCE,
  type Point,
  TEXT_PADDING,
  TEXT_SIZE,
  type ToolId,
} from './model'

const FREEHAND: ReadonlySet<ToolId> = new Set(['pen', 'highlighter', 'laser'])

/** A shape shorter than this is a stray click, not a mark. */
const MINIMUM_SHAPE_LENGTH = 2

/**
 * The vector model of one drawing session: committed marks plus the stroke in
 * progress. Mirrors StareCore's DrawingSession, without any rendering.
 */
export class DrawingSession {
  marks: Mark[] = []
  current: Mark | null = null

  get isEmpty(): boolean {
    return this.marks.length === 0 && this.current === null
  }

  /** `now` stamps transient marks so they can fade; other marks ignore it. */
  begin(point: Point, tool: ToolId, ink: InkId, weight = 1, now = 0): void {
    const mark: Mark = { tool, ink, points: [point] }
    if (weight !== 1) mark.weight = weight
    if (isTransient(tool)) mark.createdAt = now
    this.current = mark
  }

  extend(point: Point): void {
    const mark = this.current
    if (!mark || mark.tool === 'number') return

    if (FREEHAND.has(mark.tool)) {
      const last = mark.points[mark.points.length - 1]
      if (distance(last, point) >= MINIMUM_SAMPLE_DISTANCE) mark.points.push(point)
      return
    }
    mark.points = [mark.points[0], point]
  }

  end(): void {
    const mark = this.current
    this.current = null
    if (!mark) return

    const isShape = !FREEHAND.has(mark.tool) && mark.tool !== 'number'
    if (isShape) {
      const [start, end] = mark.points
      if (!end || distance(start, end) < MINIMUM_SHAPE_LENGTH) return
    }
    this.marks.push(mark)
  }

  /**
   * Drops lasers that have faded out. Returns whether any are still fading,
   * so the caller knows to keep redrawing.
   */
  prune(now: number): boolean {
    const alive = (m: Mark) => !isTransient(m.tool) || now - (m.createdAt ?? now) < LASER_LIFETIME_MS
    this.marks = this.marks.filter(alive)
    const fading = (m: Mark | null) => m !== null && isTransient(m.tool)
    return this.marks.some(fading) || fading(this.current)
  }

  /**
   * Commits typed text at its top-left origin. Empty text never becomes a
   * mark, as in the app. `width` is the measured width of the text in screen
   * points. Returns whether a mark was added.
   */
  addText(origin: Point, text: string, ink: InkId, width: number, weight = 1): boolean {
    if (text === '') return false
    const mark: Mark = { tool: 'text', ink, points: [origin], text, size: { width, height: TEXT_SIZE * weight } }
    if (weight !== 1) mark.weight = weight
    this.marks.push(mark)
    return true
  }

  /**
   * Removes every whole mark within `radius` of the point, as the app's eraser
   * does on each drag sample. Returns how many went. Not undoable, like the
   * app: undo afterwards takes back the last mark still on screen.
   */
  erase(point: Point, radius: number): number {
    const before = this.marks.length
    this.marks = this.marks.filter((mark) => !hitTest(mark, point, radius))
    return before - this.marks.length
  }

  undo(): void {
    this.marks.pop()
  }

  clear(): void {
    this.marks = []
    this.current = null
  }

  /**
   * The step number shown on a numbered badge, or null for other marks.
   * Computed from order, so undoing a step never leaves a gap.
   */
  badgeNumber(index: number): number | null {
    if (this.marks[index]?.tool !== 'number') return null
    let count = 0
    for (let i = 0; i <= index; i++) {
      if (this.marks[i].tool === 'number') count++
    }
    return count
  }
}

/**
 * StareCore's Stroke.hitTest: the stroked outline widened by the eraser
 * radius on each side, the badge's disc, or (for later tools) their bounds.
 */
function hitTest(mark: Mark, point: Point, radius: number): boolean {
  const weight = mark.weight ?? 1
  const reach = Math.max(lineWidth(mark.tool) * weight, 2) / 2 + radius
  const [start] = mark.points
  const end = mark.points[mark.points.length - 1]

  switch (mark.tool) {
    case 'number':
      return distance(point, start) <= (BADGE_DIAMETER / 2) * weight + radius
    case 'rectangle': {
      const r = normalizedRect(start, end)
      const corners = [
        { x: r.x, y: r.y },
        { x: r.x + r.width, y: r.y },
        { x: r.x + r.width, y: r.y + r.height },
        { x: r.x, y: r.y + r.height },
        { x: r.x, y: r.y },
      ]
      return distanceToPolyline(point, corners) <= reach
    }
    case 'ellipse':
      return distanceToPolyline(point, ellipseOutline(normalizedRect(start, end))) <= reach
    case 'arrow': {
      const head = arrowHeadBarbs(start, end, weight).map((barb) => [end, barb])
      return [[start, end], ...head].some((segment) => distanceToPolyline(point, segment) <= reach)
    }
    case 'text': {
      const pad = TEXT_PADDING * weight + radius
      const { width, height } = mark.size ?? { width: 0, height: TEXT_SIZE * weight }
      return (
        point.x >= start.x - pad && point.x <= start.x + width + pad && point.y >= start.y - pad && point.y <= start.y + height + pad
      )
    }
    case 'eraser':
      return false
    default:
      return distanceToPolyline(point, mark.points) <= reach
  }
}
