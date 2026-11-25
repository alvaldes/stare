/** @jsxImportSource hono/jsx/dom */
// The shortcuts panel: shows what the last pressed Stare key does and draws a
// live sample of it with the demo's renderer. Keys can be pressed on the
// visitor's keyboard or clicked on the keyboard drawn by components/Keyboard.
import { useEffect, useRef, useState } from 'hono/jsx'
import { render } from 'hono/jsx/dom'
import { type DemoAction, resolveKey } from '../demo/keymap'
import { INKS, type InkId, type MarkStyle, TOOLS, type ToolId } from '../demo/model'
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
  text: 'Click to type a note right on the screen. Return keeps it, Esc drops it.',
  number: 'Numbered steps. Undo one and the rest renumber.',
  eraser: 'Wipes whole marks as you drag over them. There is no undo for it, like the app.',
  laser: 'Point while you talk. It fades on its own and never shows up in a capture.',
  blur: 'Drag over anything private. It stays unreadable in the capture.',
  spotlight: 'Drag around what matters and everything else dims.',
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
      return { key: '⌘Z', title: 'Undo', note: 'Takes back the last mark, one at a time, or everything Esc cleared.' }
    case 'redo':
      return { key: '⇧⌘Z', title: 'Redo', note: 'Puts back what undo took.' }
    case 'fill':
      return { key: '9', title: 'Fill', note: 'The next rectangle or ellipse gets a wash of its ink. Press again for an outline.' }
    case 'arrowHead':
      return { key: '0', title: 'Arrow head', note: 'Switches the next arrow between an open head and a solid one.' }
    case 'clear':
      return { key: 'Esc', title: 'Clear all', note: 'Wipes every mark in one step. ⌘Z brings them back.' }
    case 'capture':
      return { key: 'S', title: 'Capture', note: 'Copies the screen with your marks and shows it on a card in the corner.' }
    case 'start':
      return { key: '⌥⇧A', title: 'Start drawing', note: 'Lays the sheet over any app. Your marks come back with it.' }
  }
}

/** A few lines of pretend text to mark up. */
function drawPretendText(ctx: CanvasRenderingContext2D): void {
  ctx.fillStyle = '#dfe4ec'
  for (const [x, y, w] of [[46, 52, 190], [46, 76, 228], [46, 100, 160], [46, 124, 204]]) {
    ctx.beginPath()
    ctx.roundRect(x, y, w, 9, 4.5)
    ctx.fill()
  }
}

/** The sample's white page with its text, for the blur to diffuse. */
function pretendPage(): HTMLCanvasElement {
  const page = document.createElement('canvas')
  page.width = SAMPLE_WIDTH * 2
  page.height = SAMPLE_HEIGHT * 2
  const ctx = page.getContext('2d')
  if (ctx) {
    ctx.scale(2, 2)
    ctx.fillStyle = '#ffffff'
    ctx.fillRect(0, 0, SAMPLE_WIDTH, SAMPLE_HEIGHT)
    drawPretendText(ctx)
  }
  return page
}

export function mountKeyboardPanel(root: HTMLElement, keyboard: HTMLElement): void {
  render(<Panel keyboard={keyboard} />, root)
}

function Panel({ keyboard }: { keyboard: HTMLElement }) {
  const canvasRef = useRef<HTMLCanvasElement>(null)
  const flashRef = useRef<HTMLDivElement>(null)
  const state = useRef({
    tool: 'pen' as ToolId,
    ink: 'red' as InkId,
    style: { filled: false, arrowHead: 'open' } as MarkStyle,
    t: 1,
    frame: 0,
    page: null as HTMLCanvasElement | null,
  }).current!
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
    drawPretendText(ctx)
    state.page ??= pretendPage()
    const surface = { backdrop: state.page, bounds: { width: SAMPLE_WIDTH, height: SAMPLE_HEIGHT } }
    sampleMarks(state.tool, state.ink, t).forEach((mark, i) => {
      const styled = { ...mark }
      if (state.style.filled && (mark.tool === 'rectangle' || mark.tool === 'ellipse')) styled.filled = true
      if (state.style.arrowHead === 'filled' && mark.tool === 'arrow') styled.arrowHead = 'filled'
      drawMark(ctx, styled, mark.tool === 'number' ? i + 1 : null, undefined, surface)
    })
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
    // The style keys show their effect on the shape they change.
    if (action.type === 'fill') {
      state.style.filled = !state.style.filled
      if (state.tool !== 'ellipse') state.tool = 'rectangle'
    }
    if (action.type === 'arrowHead') {
      state.style.arrowHead = state.style.arrowHead === 'open' ? 'filled' : 'open'
      state.tool = 'arrow'
    }
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
