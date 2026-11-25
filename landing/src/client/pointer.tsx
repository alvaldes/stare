/** @jsxImportSource hono/jsx/dom */
// Pointer highlight on the landing itself. ⌥⇧M or the button turns it on and a
// highlight follows the visitor's real cursor across the whole page, drawn like
// the app's (PointerHighlightRenderer) and starting on the look a fresh install
// gets. It never takes clicks, but pulses on them like the app.
import { useEffect, useRef, useState } from 'hono/jsx'
import { render } from 'hono/jsx/dom'
import { INKS, type InkId } from '../demo/model'
import {
  clickTransform,
  DEFAULT_POINTER,
  idleOpacity,
  POINTER_PRESETS,
  POINTER_SIZES,
  type PointerLook,
  pointerInk,
  PULSE_DURATION_S,
} from '../demo/pointer'
import { highlightMarkup } from '../demo/pointerMarkup'
import { INK_EVENT } from './events'

let gradientId = 0

export function mountPointer(controls: HTMLElement): void {
  const overlay = document.createElement('div')
  overlay.setAttribute('aria-hidden', 'true')
  overlay.className = 'pointer-events-none fixed top-0 left-0 z-[60] hidden'
  document.body.append(overlay)
  render(<Pointer overlay={overlay} />, controls)
}

function Pointer({ overlay }: { overlay: HTMLElement }) {
  const touchOnly = window.matchMedia('(hover: none)').matches
  const [on, setOn] = useState(false)
  // Starts on the app's factory look, so the page shows what Stare ships.
  const [look, setLook] = useState<PointerLook>(DEFAULT_POINTER)
  // The demo starts on red; it says so again whenever the visitor changes ink.
  const [activeInk, setActiveInk] = useState<InkId>('red')
  const previewRef = useRef<HTMLDivElement>(null)
  const onRef = useRef(false)
  const lookRef = useRef(DEFAULT_POINTER)
  onRef.current = on
  lookRef.current = look
  const shown: PointerLook = { ...look, ink: pointerInk(look, activeInk) }
  const markup = highlightMarkup(shown, `pointer-glow-${++gradientId}`)

  // Redraw the highlight whenever the look or the ink it follows changes.
  useEffect(() => {
    overlay.innerHTML = highlightMarkup(shown, `pointer-glow-${++gradientId}`)
  }, [look, activeInk])

  useEffect(() => {
    const take = (event: Event) => setActiveInk((event as CustomEvent<InkId>).detail)
    window.addEventListener(INK_EVENT, take)
    return () => window.removeEventListener(INK_EVENT, take)
  }, [])

  // Follow the real cursor; fade when it rests and pulse on a click, like the app.
  useEffect(() => {
    let x = -9999
    let y = -9999
    let lastMove = performance.now()
    let clickedAt = -Infinity
    let frame = 0
    const tick = () => {
      frame = 0
      const now = performance.now()
      const idle = (now - lastMove) / 1000
      const sinceClick = (now - clickedAt) / 1000
      const fade = lookRef.current!.fadeWhenIdle
      const { scale, rotation } = clickTransform(lookRef.current!.clickAnimation, sinceClick)
      const pulse = `scale(${scale}) rotate(${rotation}deg)`
      overlay.style.transform = `translate(${x}px, ${y}px) translate(-50%, -50%)`
      overlay.style.opacity = String(fade ? idleOpacity(idle) : 1)
      for (const svg of [overlay.firstElementChild, previewRef.current?.firstElementChild]) {
        if (svg instanceof SVGElement) svg.style.transform = pulse
      }
      const pulsing = sinceClick < PULSE_DURATION_S
      if (pulsing || (onRef.current && fade && idle < 2.2)) frame = requestAnimationFrame(tick)
    }
    // The click does not reset the idle fade: only movement does.
    const click = (event: PointerEvent) => {
      if (event.pointerType === 'touch') return
      clickedAt = performance.now()
      if (!frame) frame = requestAnimationFrame(tick)
    }
    window.addEventListener('pointerdown', click, { passive: true })
    const move = (event: PointerEvent) => {
      if (event.pointerType === 'touch') return
      x = event.clientX
      y = event.clientY
      lastMove = performance.now()
      if (!frame) frame = requestAnimationFrame(tick)
    }
    const leave = () => {
      x = -9999
      if (!frame) frame = requestAnimationFrame(tick)
    }
    window.addEventListener('pointermove', move, { passive: true })
    document.documentElement.addEventListener('pointerleave', leave)
    return () => {
      window.removeEventListener('pointermove', move)
      window.removeEventListener('pointerdown', click)
      document.documentElement.removeEventListener('pointerleave', leave)
      cancelAnimationFrame(frame)
    }
  }, [])

  useEffect(() => {
    overlay.classList.toggle('hidden', !on)
  }, [on])

  // ⌥⇧M, the app's shortcut. On a Mac that chord types "Â", so match the key
  // position (code), not the character.
  useEffect(() => {
    const key = (event: KeyboardEvent) => {
      if (touchOnly || !event.altKey || !event.shiftKey || event.metaKey || event.ctrlKey) return
      if (event.code !== 'KeyM') return
      event.preventDefault()
      setOn((value) => !value)
    }
    window.addEventListener('keydown', key)
    return () => window.removeEventListener('keydown', key)
  }, [])

  const set = (patch: Partial<PointerLook>) => setLook((current) => ({ ...current, ...patch }))
  const chip = (active: boolean) =>
    `rounded-full px-3 py-1.5 text-[13px] font-semibold transition-colors ${
      active ? 'bg-graphite text-paper' : 'bg-paper text-graphite ring-1 ring-rule hover:ring-graphite/40'
    }`

  return (
    <div class="grid items-stretch gap-6 lg:grid-cols-2">
      <div class="flex flex-col gap-6">
        {touchOnly ? (
          <p class="rounded-2xl bg-paper/70 p-4 text-[15px] text-muted">
            The pointer highlight follows a mouse or trackpad. Open this page on your Mac to try it.
          </p>
        ) : (
          <div class="flex flex-wrap items-center gap-4">
            <button
              type="button"
              aria-pressed={String(on)}
              onClick={() => setOn((value) => !value)}
              class={`inline-flex h-12 items-center gap-3 rounded-full px-6 text-[15px] font-semibold shadow-toolbar transition-colors ${
                on ? 'bg-ink-red text-white' : 'bg-graphite text-paper hover:bg-graphite/90'
              }`}
            >
              {on ? 'Turn it off' : 'Turn it on for this page'}
              <kbd class="rounded-md bg-white/15 px-1.5 py-0.5 font-mac text-[12px]">⌥⇧M</kbd>
            </button>
            <span aria-live="polite" class="text-[14px] text-muted">
              {on ? 'Move your pointer anywhere on the page.' : ''}
            </span>
          </div>
        )}

        <fieldset class="flex flex-col gap-4 rounded-3xl border border-white/80 bg-paper/60 p-5 shadow-glass backdrop-blur-sm">
          <legend class="sr-only">Pointer highlight settings</legend>
          <div class="flex flex-wrap items-center gap-2">
            <span class="w-16 text-[14px] text-muted">Size</span>
            {POINTER_SIZES.map((size) => (
              <button type="button" aria-pressed={String(look.size === size)} onClick={() => set({ size })} class={chip(look.size === size)}>
                {size} pt
              </button>
            ))}
          </div>
          <div class="flex flex-wrap items-center gap-2">
            <span class="w-16 text-[14px] text-muted">Shape</span>
            {POINTER_PRESETS.map((preset) => (
              <button
                type="button"
                aria-pressed={String(look.preset === preset.id)}
                onClick={() => set({ preset: preset.id })}
                class={chip(look.preset === preset.id)}
              >
                {preset.title}
              </button>
            ))}
          </div>
          <div class="flex flex-wrap items-center gap-2">
            <span class="w-16 text-[14px] text-muted">Border</span>
            {(['solid', 'dashed'] as const).map((border) => (
              <button type="button" aria-pressed={String(look.border === border)} onClick={() => set({ border })} class={chip(look.border === border)}>
                {border === 'solid' ? 'Solid' : 'Dashed'}
              </button>
            ))}
          </div>
          <div class="flex flex-wrap items-center gap-2">
            <span class="w-16 text-[14px] text-muted">Colour</span>
            {INKS.filter((i) => i.id !== 'white' && i.id !== 'black').map((ink) => {
              const picked = !look.followInk && look.ink === ink.id
              return (
                <button
                  type="button"
                  aria-label={`${ink.name}`}
                  aria-pressed={String(picked)}
                  onClick={() => set({ ink: ink.id, followInk: false })}
                  class={`size-7 rounded-full transition-transform ${picked ? 'scale-110 ring-2 ring-graphite ring-offset-2' : 'ring-1 ring-graphite/15 hover:scale-105'}`}
                  style={{ backgroundColor: ink.hex }}
                />
              )
            })}
            <button
              type="button"
              aria-pressed={String(look.followInk)}
              title="Takes the ink picked in the demo above"
              onClick={() => set({ followInk: !look.followInk })}
              class={chip(look.followInk)}
            >
              Follows ink
            </button>
          </div>
          <div class="flex flex-wrap items-center gap-2">
            <span class="w-16 text-[14px] text-muted">Click</span>
            {(['scale', 'rotate'] as const).map((clickAnimation) => (
              <button
                type="button"
                aria-pressed={String(look.clickAnimation === clickAnimation)}
                onClick={() => set({ clickAnimation })}
                class={chip(look.clickAnimation === clickAnimation)}
              >
                {clickAnimation === 'scale' ? 'Scale' : 'Rotate'}
              </button>
            ))}
            <span class="text-[13px] text-muted">Click anywhere to see it.</span>
          </div>
          <div class="flex flex-wrap items-center gap-2">
            <span class="w-16 text-[14px] text-muted">Effects</span>
            <button type="button" aria-pressed={String(look.glow)} onClick={() => set({ glow: !look.glow })} class={chip(look.glow)}>
              Glow
            </button>
            <button
              type="button"
              aria-pressed={String(look.fadeWhenIdle)}
              onClick={() => set({ fadeWhenIdle: !look.fadeWhenIdle })}
              class={chip(look.fadeWhenIdle)}
            >
              Fade when idle
            </button>
          </div>
        </fieldset>
      </div>

      {/* Live preview of the current look, over a pretend slide. */}
      {/* Tall enough for the largest size and its glow, so switching never shifts the page. */}
      <div class="relative grid min-h-[360px] place-items-center overflow-hidden rounded-3xl bg-chrome shadow-card">
        <div aria-hidden="true" class="absolute inset-8 flex flex-col gap-3 opacity-30">
          <span class="h-4 w-1/2 rounded-full bg-white" />
          <span class="h-3 w-3/4 rounded-full bg-white/70" />
          <span class="h-3 w-2/3 rounded-full bg-white/70" />
          <span class="mt-4 h-24 w-2/5 rounded-2xl bg-white/50" />
        </div>
        <div ref={previewRef} class="relative" dangerouslySetInnerHTML={{ __html: markup }} />
        <svg aria-hidden="true" viewBox="0 0 18 24" width="18" height="24" class="absolute top-1/2 left-1/2 -mt-0.5 -ml-0.5">
          <path d="M2 2l13 12.5-6.2.6 3.6 7.2-2.8 1.3-3.5-7.2L2 21z" fill="#fff" stroke="#1c2030" stroke-width="1.4" stroke-linejoin="round" />
        </svg>
      </div>
    </div>
  )
}
