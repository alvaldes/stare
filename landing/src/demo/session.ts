import { arrowHeadBarbs, distance, distanceToPolyline, ellipseOutline, normalizedRect } from './geometry'
import {
  BADGE_DIAMETER,
  type InkId,
  isArea,
  isTransient,
  LASER_LIFETIME_MS,
  lineWidth,
  type Mark,
  type MarkStyle,
  MINIMUM_SAMPLE_DISTANCE,
  type Point,
  TEXT_PADDING,
  TEXT_SIZE,
  type ToolId,
} from './model'

const FREEHAND: ReadonlySet<ToolId> = new Set(['pen', 'highlighter', 'laser'])

/** A shape shorter than this is a stray click, not a mark. */
const MINIMUM_SHAPE_LENGTH = 2

/** What undo can reverse: a mark put on screen, or the batch Esc cleared. */
type HistoryStep = { added: Mark } | { cleared: Mark[] }

/**
 * The vector model of one drawing session: committed marks plus the stroke in
 * progress. Mirrors StareCore's DrawingSession, without any rendering.
 */
export class DrawingSession {
  marks: Mark[] = []
  current: Mark | null = null
  private undoSteps: HistoryStep[] = []
  private redoSteps: HistoryStep[] = []

  get isEmpty(): boolean {
    return this.marks.length === 0 && this.current === null
  }

  /** `now` stamps transient marks so they can fade; other marks ignore it. */
  /** `style` is the app's `9` and `0`: only rectangles, ellipses and arrows keep it. */
  begin(point: Point, tool: ToolId, ink: InkId, weight = 1, now = 0, style?: MarkStyle): void {
    const mark: Mark = { tool, ink, points: [point] }
    if (weight !== 1) mark.weight = weight
    if (isTransient(tool)) mark.createdAt = now
    if (style?.filled && (tool === 'rectangle' || tool === 'ellipse')) mark.filled = true
    if (style?.arrowHead === 'filled' && tool === 'arrow') mark.arrowHead = 'filled'
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
    this.add(mark)
  }

  /** Every new mark is one undo step and forks the redo history, as in the app. */
  private add(mark: Mark): void {
    this.marks.push(mark)
    this.undoSteps.push({ added: mark })
    this.redoSteps = []
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
    this.add(mark)
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
    const erased = before - this.marks.length
    // Erasing is an edit: the history forks and nothing comes back.
    if (erased > 0) this.redoSteps = []
    return erased
  }

  /**
   * Takes back the newest step still on screen: a mark the eraser or a fading
   * laser already removed is skipped, as the app skips stale entries.
   */
  undo(): void {
    for (let step = this.undoSteps.pop(); step; step = this.undoSteps.pop()) {
      if ('cleared' in step) {
        this.marks = [...step.cleared, ...this.marks]
        this.redoSteps.push(step)
        return
      }
      const index = this.marks.indexOf(step.added)
      if (index === -1) continue
      this.marks.splice(index, 1)
      this.redoSteps.push(step)
      return
    }
  }

  redo(): void {
    const step = this.redoSteps.pop()
    if (!step) return
    if ('cleared' in step) {
      const gone = new Set(step.cleared)
      this.marks = this.marks.filter((mark) => !gone.has(mark))
    } else {
      this.marks.push(step.added)
    }
    this.undoSteps.push(step)
  }

  /** The Esc clear: every mark goes as one undoable step; an empty screen adds none. */
  clear(): void {
    this.current = null
    if (this.marks.length === 0) return
    this.undoSteps.push({ cleared: this.marks })
    this.marks = []
    this.redoSteps = []
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
    case 'blur':
    case 'spotlight': {
      // Areas, not outlines: any point inside the dragged rectangle touches them.
      const r = normalizedRect(start, end)
      return point.x >= r.x && point.x <= r.x + r.width && point.y >= r.y && point.y <= r.y + r.height
    }
    default:
      return distanceToPolyline(point, mark.points) <= reach
  }
}
