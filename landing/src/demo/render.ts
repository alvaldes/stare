// Draws the vector model onto a 2D canvas, following StareCore's MarkRenderer.
import { arrowHeadBarbs, normalizedRect, spotlightGradient } from './geometry'
import {
  BADGE_DIAMETER,
  BLUR_RADIUS,
  ERASER_RADIUS,
  inkHex,
  isTransient,
  laserOpacity,
  lineWidth,
  type Mark,
  opacity,
  SCREEN_HEIGHT,
  SCREEN_WIDTH,
  SHAPE_FILL_OPACITY,
  TEXT_SIZE,
} from './model'
import type { DrawingSession } from './session'

/** The system font stack, standing in for the app's NSFont.systemFont. */
export const TEXT_FONT_FAMILY = '-apple-system, BlinkMacSystemFont, "Helvetica Neue", system-ui, sans-serif'

export function textFont(weight = 1): string {
  return `400 ${TEXT_SIZE * weight}px ${TEXT_FONT_FAMILY}`
}

/** Inks light enough that a white step number would disappear on them. */
const LIGHT_INKS = new Set(['white', 'yellow'])

export interface DrawOptions {
  /** Clock for fading lasers, in milliseconds. */
  now?: number
  /** False leaves transient marks out, as a capture does. */
  transient?: boolean
  /**
   * What a blur mark diffuses, laid over the whole surface. Without one the
   * canvas leaves blur marks to the caller (the live demo blurs them with CSS,
   * because the page shown on its screen can't be read).
   */
  backdrop?: CanvasImageSource
  /** The surface a spotlight dims, in the marks' points. Defaults to the demo screen. */
  bounds?: { width: number; height: number }
}

export interface Drawable {
  mark: Mark
  badge: number | null
  /** The mark still being dragged: a spotlight previews as a plain outline. */
  inProgress: boolean
}

/**
 * The marks to draw, in the app's order: lasers first so they pass under the
 * other marks, then everything else, then the stroke in progress.
 */
export function drawableMarks(session: DrawingSession, options: DrawOptions = {}): Drawable[] {
  const committed = session.marks.map((mark, index) => ({ mark, badge: session.badgeNumber(index), inProgress: false }))
  const current = session.current ? [{ mark: session.current, badge: nextBadgeNumber(session), inProgress: true }] : []
  const all = [...committed, ...current]
  const lasers = options.transient === false ? [] : all.filter((d) => isTransient(d.mark.tool))
  return [...lasers, ...all.filter((d) => !isTransient(d.mark.tool))]
}

export function drawSession(ctx: CanvasRenderingContext2D, session: DrawingSession, options: DrawOptions = {}): void {
  for (const { mark, badge, inProgress } of drawableMarks(session, options)) {
    drawMark(ctx, mark, badge, options.now, { ...options, inProgress })
  }
}

function nextBadgeNumber(session: DrawingSession): number {
  return session.marks.filter((m) => m.tool === 'number').length + 1
}

/** `now` fades a laser; without it a laser draws at full strength (samples). */
export function drawMark(
  ctx: CanvasRenderingContext2D,
  mark: Mark,
  badge: number | null,
  now?: number,
  surface: DrawOptions & { inProgress?: boolean } = {},
): void {
  if (mark.tool === 'blur') {
    if (surface.backdrop) drawBlur(ctx, mark, surface.backdrop, surface.bounds)
    return
  }
  if (mark.tool === 'spotlight' && !surface.inProgress) {
    drawSpotlight(ctx, mark, surface.bounds)
    return
  }
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
      // A solid head inks the triangle the two barbs span, over the shaft.
      const barbs = arrowHeadBarbs(start, end, weight)
      if (mark.arrowHead === 'filled' && barbs.length === 2) {
        ctx.beginPath()
        ctx.moveTo(end.x, end.y)
        ctx.lineTo(barbs[0].x, barbs[0].y)
        ctx.lineTo(barbs[1].x, barbs[1].y)
        ctx.closePath()
        ctx.fill()
      }
      break
    }
    case 'rectangle': {
      const r = normalizedRect(start, end)
      ctx.beginPath()
      ctx.rect(r.x, r.y, r.width, r.height)
      fillWash(ctx, mark)
      ctx.stroke()
      break
    }
    case 'ellipse':
    case 'spotlight': {
      // A spotlight being dragged previews as the ellipse tool draws it.
      const r = normalizedRect(start, end)
      ctx.beginPath()
      ctx.ellipse(r.x + r.width / 2, r.y + r.height / 2, r.width / 2, r.height / 2, 0, 0, Math.PI * 2)
      if (mark.tool === 'ellipse') fillWash(ctx, mark)
      ctx.stroke()
      break
    }
    case 'number':
      drawBadge(ctx, mark, badge ?? 1, weight)
      break
    case 'text':
      ctx.font = textFont(weight)
      ctx.textBaseline = 'top'
      ctx.fillText(mark.text ?? '', start.x, start.y)
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

/** A filled shape paints its ink wash first; the outline then covers its edge. */
function fillWash(ctx: CanvasRenderingContext2D, mark: Mark): void {
  if (!mark.filled) return
  ctx.save()
  ctx.globalAlpha = SHAPE_FILL_OPACITY
  ctx.fill()
  ctx.restore()
}

const SCREEN_BOUNDS = { width: SCREEN_WIDTH, height: SCREEN_HEIGHT }

/**
 * The spotlight: no ink, one radial gradient over the whole surface, its rings
 * elliptical about the region's centre, as MarkRenderer.drawSpotlight paints.
 */
function drawSpotlight(ctx: CanvasRenderingContext2D, mark: Mark, bounds = SCREEN_BOUNDS): void {
  const rect = normalizedRect(mark.points[0], mark.points[mark.points.length - 1])
  const gradient = spotlightGradient(rect, bounds)
  if (!gradient) return
  const semiWidth = rect.width / 2
  const semiHeight = rect.height / 2

  ctx.save()
  ctx.translate(rect.x + semiWidth, rect.y + semiHeight)
  ctx.scale(semiWidth, semiHeight)
  const fill = ctx.createRadialGradient(0, 0, 0, 0, 0, gradient.reach)
  for (const stop of gradient.stops) fill.addColorStop(stop.offset, `rgba(0, 0, 0, ${stop.alpha})`)
  ctx.fillStyle = fill
  // The surface, mapped into the gradient's scaled space.
  const left = -(rect.x + semiWidth) / semiWidth
  const top = -(rect.y + semiHeight) / semiHeight
  ctx.fillRect(left, top, bounds.width / semiWidth, bounds.height / semiHeight)
  ctx.restore()
}

/**
 * The blur: the backdrop under the mark's rectangle, diffused with the app's
 * 15 pt radius. Where canvas filters are missing (older Safari), a down- and
 * up-scale gives the same soft, unreadable patch.
 */
function drawBlur(ctx: CanvasRenderingContext2D, mark: Mark, backdrop: CanvasImageSource, bounds = SCREEN_BOUNDS): void {
  const r = normalizedRect(mark.points[0], mark.points[mark.points.length - 1])
  if (r.width <= 0 || r.height <= 0) return
  const scale = ctx.getTransform().a || 1

  ctx.save()
  ctx.beginPath()
  ctx.rect(r.x, r.y, r.width, r.height)
  ctx.clip()
  if (typeof ctx.filter === 'string') {
    ctx.filter = `blur(${BLUR_RADIUS * scale}px)`
    ctx.drawImage(backdrop, 0, 0, bounds.width, bounds.height)
  } else {
    const shrink = 1 / BLUR_RADIUS
    const small = document.createElement('canvas')
    small.width = Math.max(1, Math.round(bounds.width * shrink))
    small.height = Math.max(1, Math.round(bounds.height * shrink))
    small.getContext('2d')?.drawImage(backdrop, 0, 0, small.width, small.height)
    ctx.imageSmoothingQuality = 'high'
    ctx.drawImage(small, 0, 0, bounds.width, bounds.height)
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
