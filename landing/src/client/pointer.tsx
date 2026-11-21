/** @jsxImportSource hono/jsx/dom */
// Pointer highlight on the landing itself. ⌥⇧M or the button turns it on and a
// ring follows the visitor's real cursor across the whole page, drawn like the
// app's presentation mode (OverlayView.drawCursorFrame): a soft glow, a
// translucent band and two bright edges. It never takes clicks.
import { useEffect, useRef, useState } from 'hono/jsx'
import { render } from 'hono/jsx/dom'
import { INKS, type InkId, inkHex } from '../demo/model'
import { idleOpacity, POINTER_SIZES, type PointerShape, pointerRing } from '../demo/pointer'

interface Look {
  size: number
  shape: PointerShape
  glow: boolean
  ink: InkId
}

let gradientId = 0

/** SVG markup for the ring, centred in a box sized to fit its glow. */
function ringMarkup(look: Look): string {
  const { radius, band, glowRadius, corner } = pointerRing(look.size, look.shape)
  const ratio = corner / radius
  const half = Math.ceil(glowRadius) + 2
  const color = inkHex(look.ink)
  const id = `ring-glow-${++gradientId}`
  const rect = (r: number) => {
    const c = r * ratio
    // Rounded rect as a path so outer and inner shapes can share one even-odd fill.
    return `M${-r + c} ${-r}H${r - c}A${c} ${c} 0 0 1 ${r} ${-r + c}V${r - c}A${c} ${c} 0 0 1 ${r - c} ${r}H${-r + c}A${c} ${c} 0 0 1 ${-r} ${r - c}V${-r + c}A${c} ${c} 0 0 1 ${-r + c} ${-r}Z`
  }
  const inner = radius - band
  const disc = `M${-glowRadius} 0A${glowRadius} ${glowRadius} 0 1 0 ${glowRadius} 0A${glowRadius} ${glowRadius} 0 1 0 ${-glowRadius} 0Z`
  // The app's gradient starts at the inner edge and draws nothing inside it,
  // so the glow is a disc with the inner shape cut out: the centre stays clear
  // over whatever is being pointed at.
  const glow = look.glow
    ? `<defs><radialGradient id="${id}" gradientUnits="userSpaceOnUse" cx="0" cy="0" r="${glowRadius}" fr="${inner}">
         <stop offset="0" stop-color="${color}" stop-opacity=".26"/>
         <stop offset=".55" stop-color="${color}" stop-opacity=".10"/>
         <stop offset="1" stop-color="${color}" stop-opacity="0"/>
       </radialGradient></defs>
       <path d="${disc}${rect(inner)}" fill="url(#${id})" fill-rule="evenodd"/>`
    : ''
  return `<svg width="${half * 2}" height="${half * 2}" viewBox="${-half} ${-half} ${half * 2} ${half * 2}" aria-hidden="true">
    ${glow}
    <path d="${rect(radius)}${rect(inner)}" fill="${color}" fill-opacity=".55" fill-rule="evenodd"/>
    <path d="${rect(radius)}${rect(inner)}" fill="none" stroke="${color}" stroke-opacity=".95" stroke-width="2"/>
  </svg>`
}

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
  const [fadeIdle, setFadeIdle] = useState(true)
  const [look, setLook] = useState<Look>({ size: 60, shape: 'circle', glow: true, ink: 'red' })
  const onRef = useRef(false)
  const fadeRef = useRef(true)
  onRef.current = on
  fadeRef.current = fadeIdle

  // Redraw the ring whenever the look changes.
  useEffect(() => {
    overlay.innerHTML = ringMarkup(look)
  }, [look])

  // Follow the real cursor; fade when it rests, like the app.
  useEffect(() => {
    let x = -9999
    let y = -9999
    let lastMove = performance.now()
    let frame = 0
    const tick = () => {
      frame = 0
      const idle = (performance.now() - lastMove) / 1000
      overlay.style.transform = `translate(${x}px, ${y}px) translate(-50%, -50%)`
      overlay.style.opacity = String(fadeRef.current ? idleOpacity(idle) : 1)
      if (onRef.current && fadeRef.current && idle < 2.2) frame = requestAnimationFrame(tick)
    }
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

  const set = (patch: Partial<Look>) => setLook((current) => ({ ...current, ...patch }))
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
            {(['circle', 'squircle'] as const).map((shape) => (
              <button type="button" aria-pressed={String(look.shape === shape)} onClick={() => set({ shape })} class={chip(look.shape === shape)}>
                {shape === 'circle' ? 'Circle' : 'Squircle'}
              </button>
            ))}
          </div>
          <div class="flex flex-wrap items-center gap-2">
            <span class="w-16 text-[14px] text-muted">Ink</span>
            {INKS.filter((i) => i.id !== 'white' && i.id !== 'black').map((ink) => (
              <button
                type="button"
                aria-label={`${ink.name} ink`}
                aria-pressed={String(look.ink === ink.id)}
                onClick={() => set({ ink: ink.id })}
                class={`size-7 rounded-full transition-transform ${look.ink === ink.id ? 'scale-110 ring-2 ring-graphite ring-offset-2' : 'ring-1 ring-graphite/15 hover:scale-105'}`}
                style={{ backgroundColor: ink.hex }}
              />
            ))}
          </div>
          <div class="flex flex-wrap items-center gap-2">
            <span class="w-16 text-[14px] text-muted">Effects</span>
            <button type="button" aria-pressed={String(look.glow)} onClick={() => set({ glow: !look.glow })} class={chip(look.glow)}>
              Glow
            </button>
            <button type="button" aria-pressed={String(fadeIdle)} onClick={() => setFadeIdle((value) => !value)} class={chip(fadeIdle)}>
              Fade when idle
            </button>
          </div>
        </fieldset>
      </div>

      {/* Live preview of the current look, over a pretend slide. */}
      <div class="relative grid min-h-[300px] place-items-center overflow-hidden rounded-3xl bg-chrome shadow-card">
        <div aria-hidden="true" class="absolute inset-8 flex flex-col gap-3 opacity-30">
          <span class="h-4 w-1/2 rounded-full bg-white" />
          <span class="h-3 w-3/4 rounded-full bg-white/70" />
          <span class="h-3 w-2/3 rounded-full bg-white/70" />
          <span class="mt-4 h-24 w-2/5 rounded-2xl bg-white/50" />
        </div>
        <div class="relative" dangerouslySetInnerHTML={{ __html: ringMarkup(look) }} />
        <svg aria-hidden="true" viewBox="0 0 18 24" width="18" height="24" class="absolute top-1/2 left-1/2 -mt-0.5 -ml-0.5">
          <path d="M2 2l13 12.5-6.2.6 3.6 7.2-2.8 1.3-3.5-7.2L2 21z" fill="#fff" stroke="#1c2030" stroke-width="1.4" stroke-linejoin="round" />
        </svg>
      </div>
    </div>
  )
}
