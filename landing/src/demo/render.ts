// Draws the vector model onto a 2D canvas, following StareCore's MarkRenderer.
import { arrowHeadBarbs, normalizedRect } from './geometry'
import { BADGE_DIAMETER, inkHex, lineWidth, type Mark, opacity } from './model'
import type { DrawingSession } from './session'

/** Inks light enough that a white step number would disappear on them. */
const LIGHT_INKS = new Set(['white', 'yellow'])

export function drawSession(ctx: CanvasRenderingContext2D, session: DrawingSession): void {
  session.marks.forEach((mark, index) => drawMark(ctx, mark, session.badgeNumber(index)))
  if (session.current) drawMark(ctx, session.current, nextBadgeNumber(session))
}

function nextBadgeNumber(session: DrawingSession): number {
  return session.marks.filter((m) => m.tool === 'number').length + 1
}

export function drawMark(ctx: CanvasRenderingContext2D, mark: Mark, badge: number | null): void {
  const weight = mark.weight ?? 1
  const width = lineWidth(mark.tool) * weight
  const color = inkHex(mark.ink)
  const [start] = mark.points
  const end = mark.points[mark.points.length - 1]

  ctx.save()
  ctx.globalAlpha = opacity(mark.tool)
  ctx.strokeStyle = color
  ctx.fillStyle = color
  ctx.lineWidth = width
  ctx.lineCap = 'round'
  ctx.lineJoin = 'round'

  switch (mark.tool) {
    case 'pen':
    case 'highlighter':
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
