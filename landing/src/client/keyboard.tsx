/** @jsxImportSource hono/jsx/dom */
// The shortcuts panel: shows what the last pressed Stare key does and draws a
// live sample of it with the demo's renderer. Keys can be pressed on the
// visitor's keyboard or clicked on the keyboard drawn by components/Keyboard.
import { useEffect, useRef, useState } from 'hono/jsx'
import { render } from 'hono/jsx/dom'
import { type DemoAction, resolveKey } from '../demo/keymap'
import { INKS, type InkId, TOOLS, type ToolId } from '../demo/model'
import { drawMark } from '../demo/render'
import { SAMPLE_HEIGHT, SAMPLE_WIDTH, sampleMarks } from '../demo/samples'

const DRAW_MS = 520
const FLASH_MS = 160

const TOOL_NOTES: Record<ToolId, string> = {
  pen: 'Freehand ink, smoothed as you draw. Circle anything.',
  highlighter: 'A translucent stroke. The text underneath stays readable.',
  arrow: 'Point at the thing. The head scales with the arrow.',
  line: 'Straight underlines and connectors.',
  rectangle: 'Frame a region of the screen.',
  ellipse: 'Ring the detail that matters.',
  number: 'Numbered steps. Undo one and the rest renumber.',
}

interface Shown {
  key: string
  title: string
  note: string
}

function describe(action: DemoAction): Shown {
  switch (action.type) {
    case 'tool': {
      const info = TOOLS.find((t) => t.id === action.tool)!
      return { key: info.key, title: info.name, note: TOOL_NOTES[action.tool] }
    }
    case 'ink': {
      const info = INKS.find((i) => i.id === action.ink)!
      return { key: info.key, title: `${info.name} ink`, note: 'Every tool picks it up until you change it.' }
    }
    case 'undo':
      return { key: '⌘Z', title: 'Undo', note: 'Takes back the last mark, one at a time.' }
    case 'clear':
      return { key: 'Esc', title: 'Clear all', note: 'Wipes every mark and leaves drawing mode.' }
    case 'capture':
      return { key: 'S', title: 'Capture', note: 'Saves the screen with your marks to a card you can paste.' }
  }
}

export function mountKeyboardPanel(root: HTMLElement, keyboard: HTMLElement): void {
  render(<Panel keyboard={keyboard} />, root)
}

function Panel({ keyboard }: { keyboard: HTMLElement }) {
  const canvasRef = useRef<HTMLCanvasElement>(null)
  const flashRef = useRef<HTMLDivElement>(null)
  const state = useRef({ tool: 'pen' as ToolId, ink: 'red' as InkId, t: 1, frame: 0 }).current!
  const [shown, setShown] = useState<Shown>({
    key: 'P',
    title: 'Pen',
    note: 'Press a highlighted key, or tap one, to see what it does.',
  })
  const [ink, setInk] = useState<InkId>('red')

  const paint = (t: number) => {
    const canvas = canvasRef.current
    if (!canvas) return
    const ratio = window.devicePixelRatio || 1
    const width = Math.round(canvas.clientWidth * ratio)
    const height = Math.round(canvas.clientHeight * ratio)
    if (canvas.width !== width || canvas.height !== height) {
      canvas.width = width
      canvas.height = height
    }
    const ctx = canvas.getContext('2d')
    if (!ctx) return
    ctx.setTransform(width / SAMPLE_WIDTH, 0, 0, height / SAMPLE_HEIGHT, 0, 0)
    ctx.clearRect(0, 0, SAMPLE_WIDTH, SAMPLE_HEIGHT)
    // A few lines of pretend text to mark up.
    ctx.fillStyle = '#dfe4ec'
    for (const [x, y, w] of [[46, 52, 190], [46, 76, 228], [46, 100, 160], [46, 124, 204]]) {
      ctx.beginPath()
      ctx.roundRect(x, y, w, 9, 4.5)
      ctx.fill()
    }
    sampleMarks(state.tool, state.ink, t).forEach((mark, i) => drawMark(ctx, mark, mark.tool === 'number' ? i + 1 : null))
  }

  const animate = (from: number, to: number) => {
    cancelAnimationFrame(state.frame)
    if (window.matchMedia('(prefers-reduced-motion: reduce)').matches) {
      state.t = to
      paint(to)
      return
    }
    const start = performance.now()
    const step = (now: number) => {
      const k = Math.min(1, (now - start) / DRAW_MS)
      const eased = 1 - (1 - k) ** 3
      state.t = from + (to - from) * eased
      paint(state.t)
      if (k < 1) state.frame = requestAnimationFrame(step)
    }
    state.frame = requestAnimationFrame(step)
  }

  const perform = (action: DemoAction) => {
    if (action.type === 'tool') state.tool = action.tool
    if (action.type === 'ink') {
      state.ink = action.ink
      setInk(action.ink)
    }
    setShown(describe(action))

    if (action.type === 'undo' || action.type === 'clear') {
      animate(state.t, 0)
    } else if (action.type === 'capture') {
      paint(state.t)
      flashRef.current?.animate([{ opacity: 0.9 }, { opacity: 0 }], { duration: 420, easing: 'ease-out' })
    } else {
      animate(0, 1)
    }
  }

  useEffect(() => {
    paint(1)
    const resize = new ResizeObserver(() => paint(state.t))
    if (canvasRef.current) resize.observe(canvasRef.current)

    const onKey = (event: KeyboardEvent) => {
      const target = event.target
      if (target instanceof Element && target.closest('input, textarea, [contenteditable]')) return
      if (event.repeat) return
      const action = resolveKey(event)
      if (action) perform(action)
    }

    const onClick = (event: MouseEvent) => {
      const key = (event.target as Element).closest<HTMLElement>('[data-keycap]')
      if (!key?.dataset.press) return
      const action = resolveKey({
        key: key.dataset.press,
        metaKey: key.hasAttribute('data-meta'),
        ctrlKey: false,
        shiftKey: false,
        altKey: false,
      })
      if (!action) return
      key.dataset.pressed = ''
      setTimeout(() => delete key.dataset.pressed, FLASH_MS)
      perform(action)
    }

    window.addEventListener('keydown', onKey)
    keyboard.addEventListener('click', onClick)
    return () => {
      window.removeEventListener('keydown', onKey)
      keyboard.removeEventListener('click', onClick)
      resize.disconnect()
    }
  }, [])

  return (
    <div class="overflow-hidden rounded-3xl bg-chrome font-mac text-white shadow-card">
      <div aria-live="polite" class="flex items-start gap-4 p-5">
        <kbd class="grid h-12 min-w-12 shrink-0 place-items-center rounded-xl border border-b-[3px] border-white/15 bg-white/10 px-3 text-[18px] font-semibold">
          {shown.key}
        </kbd>
        <div>
          <p class="text-[17px] font-semibold">{shown.title}</p>
          <p class="mt-1 text-[14px] leading-snug text-white/65">{shown.note}</p>
        </div>
      </div>
      <div class="relative mx-5 overflow-hidden rounded-2xl bg-white">
        <canvas ref={canvasRef} class="block aspect-[2/1] w-full" aria-hidden="true" />
        <div ref={flashRef} class="pointer-events-none absolute inset-0 bg-white opacity-0" />
      </div>
      <div class="flex items-center gap-2 px-5 py-4" aria-label="Current ink">
        {INKS.map((i) => (
          <span
            class={`size-3.5 rounded-full transition-transform ${ink === i.id ? 'scale-125 ring-2 ring-white' : 'ring-1 ring-white/25'}`}
            style={{ backgroundColor: i.hex }}
          />
        ))}
        <span class="ml-auto text-[12px] text-white/50">1–8 change ink</span>
      </div>
    </div>
  )
}
