// Draws the vector model onto a 2D canvas, following StareCore's MarkRenderer.
import { arrowHeadBarbs, normalizedRect } from './geometry'
import { BADGE_DIAMETER, ERASER_RADIUS, inkHex, isTransient, laserOpacity, lineWidth, type Mark, opacity } from './model'
import type { DrawingSession } from './session'

/** Inks light enough that a white step number would disappear on them. */
const LIGHT_INKS = new Set(['white', 'yellow'])

export interface DrawOptions {
  /** Clock for fading lasers, in milliseconds. */
  now?: number
  /** False leaves transient marks out, as a capture does. */
  transient?: boolean
}

export interface Drawable {
  mark: Mark
  badge: number | null
}

/**
 * The marks to draw, in the app's order: lasers first so they pass under the
 * other marks, then everything else, then the stroke in progress.
 */
export function drawableMarks(session: DrawingSession, options: DrawOptions = {}): Drawable[] {
  const committed = session.marks.map((mark, index) => ({ mark, badge: session.badgeNumber(index) }))
  const current = session.current ? [{ mark: session.current, badge: nextBadgeNumber(session) }] : []
  const all = [...committed, ...current]
  const lasers = options.transient === false ? [] : all.filter((d) => isTransient(d.mark.tool))
  return [...lasers, ...all.filter((d) => !isTransient(d.mark.tool))]
}

export function drawSession(ctx: CanvasRenderingContext2D, session: DrawingSession, options: DrawOptions = {}): void {
  for (const { mark, badge } of drawableMarks(session, options)) drawMark(ctx, mark, badge, options.now)
}

function nextBadgeNumber(session: DrawingSession): number {
  return session.marks.filter((m) => m.tool === 'number').length + 1
}

/** `now` fades a laser; without it a laser draws at full strength (samples). */
export function drawMark(ctx: CanvasRenderingContext2D, mark: Mark, badge: number | null, now?: number): void {
  const weight = mark.weight ?? 1
  const width = lineWidth(mark.tool) * weight
  const color = inkHex(mark.ink)
  const [start] = mark.points
  const end = mark.points[mark.points.length - 1]

  ctx.save()
  ctx.globalAlpha = isTransient(mark.tool) && now !== undefined ? laserOpacity(mark, now) : opacity(mark.tool)
  ctx.strokeStyle = color
  ctx.fillStyle = color
  ctx.lineWidth = width
  ctx.lineCap = 'round'
  ctx.lineJoin = 'round'

  switch (mark.tool) {
    case 'pen':
    case 'highlighter':
    case 'laser':
      if (mark.points.length === 1) {
        ctx.beginPath()
        ctx.arc(start.x, start.y, width / 2, 0, Math.PI * 2)
        ctx.fill()
      } else {
        strokeSmooth(ctx, mark)
      }
      break
    case 'line':
      ctx.beginPath()
      ctx.moveTo(start.x, start.y)
      ctx.lineTo(end.x, end.y)
      ctx.stroke()
      break
    case 'arrow': {
      ctx.beginPath()
      ctx.moveTo(start.x, start.y)
      ctx.lineTo(end.x, end.y)
      for (const barb of arrowHeadBarbs(start, end, weight)) {
        ctx.moveTo(end.x, end.y)
        ctx.lineTo(barb.x, barb.y)
      }
      ctx.stroke()
      break
    }
    case 'rectangle': {
      const r = normalizedRect(start, end)
      ctx.strokeRect(r.x, r.y, r.width, r.height)
      break
    }
    case 'ellipse': {
      const r = normalizedRect(start, end)
      ctx.beginPath()
      ctx.ellipse(r.x + r.width / 2, r.y + r.height / 2, r.width / 2, r.height / 2, 0, 0, Math.PI * 2)
      ctx.stroke()
      break
    }
    case 'number':
      drawBadge(ctx, mark, badge ?? 1, weight)
      break
    case 'eraser':
      // Only the shortcuts panel draws this: the path the eraser swept.
      ctx.globalAlpha = 0.22
      ctx.strokeStyle = '#5b6275'
      ctx.lineWidth = ERASER_RADIUS * 2 * weight
      ctx.beginPath()
      ctx.moveTo(start.x, start.y)
      ctx.lineTo(end.x, end.y)
      ctx.stroke()
      break
  }
  ctx.restore()
}

/** Freehand strokes pass through the midpoints between samples, as the app does. */
function strokeSmooth(ctx: CanvasRenderingContext2D, mark: Mark): void {
  const pts = mark.points
  ctx.beginPath()
  ctx.moveTo(pts[0].x, pts[0].y)
  for (let i = 1; i < pts.length - 1; i++) {
    const mid = { x: (pts[i].x + pts[i + 1].x) / 2, y: (pts[i].y + pts[i + 1].y) / 2 }
    ctx.quadraticCurveTo(pts[i].x, pts[i].y, mid.x, mid.y)
  }
  const last = pts[pts.length - 1]
  ctx.lineTo(last.x, last.y)
  ctx.stroke()
}

function drawBadge(ctx: CanvasRenderingContext2D, mark: Mark, number: number, weight: number): void {
  const { x, y } = mark.points[0]
  const radius = (BADGE_DIAMETER / 2) * weight

  ctx.shadowColor = 'rgba(0, 0, 0, 0.18)'
  ctx.shadowBlur = 4 * weight
  ctx.shadowOffsetY = 1 * weight
  ctx.beginPath()
  ctx.arc(x, y, radius, 0, Math.PI * 2)
  ctx.fill()

  ctx.shadowColor = 'transparent'
  ctx.fillStyle = LIGHT_INKS.has(mark.ink) ? '#1c2030' : '#ffffff'
  ctx.font = `600 ${Math.round(14 * weight)}px -apple-system, BlinkMacSystemFont, system-ui, sans-serif`
  ctx.textAlign = 'center'
  ctx.textBaseline = 'middle'
  ctx.fillText(String(number), x, y + 0.5 * weight)
}
