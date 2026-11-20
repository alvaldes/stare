// Plays the creator's note once the demo comes into view: a red ring drawn
// around the URL in the pretend Safari bar, a stroke out to the bubble, then
// the message typed letter by letter. Geometry is measured from the layout,
// so the ink follows the URL at any width.
import { SCREEN_HEIGHT, SCREEN_WIDTH } from '../demo/model'

/** Where the domain sits in the demo screen's 1200×720 space (see DemoScreen). */
const URL_CENTER = { x: 599.4, y: 60 }
const RING_RADIUS = { x: 44, y: 11 }
const TYPE_MS = 32

export function playCreatorNote(): void {
  const section = document.getElementById('try')
  const screen = document.getElementById('demo-screen')
  const svg = document.getElementById('creator-ink')
  const ring = document.getElementById('creator-ring')
  const line = document.getElementById('creator-line')
  const note = document.getElementById('creator-note')
  const text = document.getElementById('creator-text')
  if (!section || !screen || !svg || !ring || !line || !note || !text) return

  const reduced = window.matchMedia('(prefers-reduced-motion: reduce)').matches
  const message = text.textContent?.trim() ?? ''

  const layout = () => {
    const origin = section.getBoundingClientRect()
    const s = screen.getBoundingClientRect()
    const scaleX = s.width / SCREEN_WIDTH
    const scaleY = s.height / SCREEN_HEIGHT
    const cx = s.left - origin.left + URL_CENTER.x * scaleX
    const cy = s.top - origin.top + URL_CENTER.y * scaleY
    const rx = RING_RADIUS.x * scaleX
    const ry = RING_RADIUS.y * scaleY * 1.6

    // A hand-drawn ring: slightly more than a full turn, starting top-right.
    const start = -Math.PI / 4
    const turn = Math.PI * 2.18
    const points = Array.from({ length: 41 }, (_, i) => {
      const a = start - (i / 40) * turn
      const wobble = 1 + Math.sin(a * 3) * 0.04
      return `${(cx + Math.cos(a) * rx * wobble).toFixed(1)} ${(cy + Math.sin(a) * ry * wobble).toFixed(1)}`
    })
    ring.setAttribute('d', `M${points.join('L')}`)

    // From the ring's top-right to the bubble's lower-left corner.
    const b = note.getBoundingClientRect()
    const from = { x: cx + Math.cos(start) * rx, y: cy + Math.sin(start) * ry }
    const to = { x: b.left - origin.left + 4, y: b.bottom - origin.top - 10 }
    line.setAttribute(
      'd',
      `M${from.x.toFixed(1)} ${from.y.toFixed(1)}C${(from.x + 30).toFixed(1)} ${(from.y - 70).toFixed(1)} ${(to.x - 120).toFixed(1)} ${(to.y + 30).toFixed(1)} ${to.x.toFixed(1)} ${to.y.toFixed(1)}`,
    )
  }

  const visible = () => getComputedStyle(svg).display !== 'none'

  const typeMessage = () => {
    if (reduced) return
    const caret = document.createElement('span')
    caret.className = 'creator-caret'
    text.append(caret)
    let i = 0
    const tick = () => {
      caret.before(message[i])
      i += 1
      if (i < message.length) setTimeout(tick, TYPE_MS + (message[i - 1] === ',' ? 180 : 0))
      else setTimeout(() => caret.remove(), 1600)
    }
    setTimeout(tick, 250)
  }

  const play = () => {
    // The note waits hidden (see .js #creator-note in style.css) until now.
    note.dataset.played = ''
    if (reduced) {
      ring.setAttribute('stroke-dashoffset', '0')
      line.setAttribute('stroke-dashoffset', '0')
      return
    }
    // Keep the finished height while typing, so the bubble (and the stroke
    // anchored to its corner) doesn't move as lines fill in. Then empty it
    // before it shows, so it never appears full and retypes.
    text.style.minHeight = `${text.getBoundingClientRect().height}px`
    text.textContent = ''
    note.animate([{ opacity: 0, transform: 'translateY(10px) scale(0.96)' }, { opacity: 1, transform: 'none' }], {
      duration: 420,
      delay: visible() ? 1250 : 0,
      easing: 'cubic-bezier(0.22, 1, 0.36, 1)',
      fill: 'backwards',
    })
    if (visible()) {
      const draw = (el: Element, delay: number, duration: number) =>
        el.animate([{ strokeDashoffset: 1 }, { strokeDashoffset: 0 }], {
          duration,
          delay,
          easing: 'cubic-bezier(0.65, 0, 0.35, 1)',
          fill: 'forwards',
        })
      draw(ring, 0, 650)
      draw(line, 600, 700)
    }
    setTimeout(typeMessage, visible() ? 1500 : 250)
  }

  layout()
  new ResizeObserver(layout).observe(section)

  const observer = new IntersectionObserver(
    (entries) => {
      if (!entries.some((e) => e.isIntersecting)) return
      observer.disconnect()
      layout()
      play()
    },
    { threshold: 0.45 },
  )
  observer.observe(screen)
}
