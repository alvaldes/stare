// Small page effects: scroll reveals, pointer spotlights and shortcut rows that
// light up when their key is pressed. All of it is decoration; the page reads
// the same without it.
import { resolveKey } from '../demo/keymap'

/** Marks [data-reveal] elements as shown once they scroll into view. */
export function revealOnScroll(): void {
  const targets = document.querySelectorAll<HTMLElement>('[data-reveal]')
  if (!('IntersectionObserver' in window)) {
    for (const el of targets) el.dataset.shown = ''
    return
  }
  const observer = new IntersectionObserver(
    (entries) => {
      for (const entry of entries) {
        if (!entry.isIntersecting) continue
        ;(entry.target as HTMLElement).dataset.shown = ''
        observer.unobserve(entry.target)
      }
    },
    { rootMargin: '0px 0px -12% 0px', threshold: 0.15 },
  )
  for (const el of targets) observer.observe(el)
}

/** Feeds the pointer position to .spotlight elements as --mx / --my. */
export function trackSpotlights(): void {
  for (const el of document.querySelectorAll<HTMLElement>('[data-spotlight]')) {
    el.addEventListener('pointermove', (event) => {
      const rect = el.getBoundingClientRect()
      el.style.setProperty('--mx', `${event.clientX - rect.left}px`)
      el.style.setProperty('--my', `${event.clientY - rect.top}px`)
    })
    el.addEventListener('pointerleave', () => {
      el.style.removeProperty('--mx')
      el.style.removeProperty('--my')
    })
  }
}

/**
 * Pressing a Stare shortcut anywhere on the page flashes its row in the
 * shortcuts table, so visitors learn the keys by trying them.
 */
export function lightUpShortcuts(): void {
  const timers = new Map<HTMLElement, number>()
  window.addEventListener('keydown', (event) => {
    const target = event.target
    if (target instanceof Element && target.closest('input, textarea, [contenteditable]')) return

    const action = resolveKey(event)
    const key =
      action?.type === 'undo' || action?.type === 'redo' ? '⌘Z' : action?.type === 'clear' ? 'Esc' : action ? event.key.toUpperCase() : null
    if (!key) return

    for (const row of document.querySelectorAll<HTMLElement>(`[data-key="${CSS.escape(key)}"]`)) {
      row.dataset.pressed = ''
      clearTimeout(timers.get(row))
      timers.set(
        row,
        window.setTimeout(() => delete row.dataset.pressed, 450),
      )
    }
  })
}
