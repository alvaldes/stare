/** @jsxImportSource hono/jsx/dom */
// The interactive layer of the demo: toolbar, drawing on the canvas, keyboard
// shortcuts and capture cards. The screen itself is prerendered on the server.
import { useCallback, useEffect, useRef, useState } from 'hono/jsx'
import { createPortal, render } from 'hono/jsx/dom'
import { copyImage, renderCapture } from '../demo/capture'
import { autoDismissDelay, CONTROL_SIDE, cardSize, evictOverflow, PLATE_INSET, STACK_MARGIN, stackBottoms } from '../demo/card'
import { ACTION_SYMBOLS, CARD_SYMBOLS, symbolStyle, TOOL_SYMBOLS } from '../demo/icons'
import { type DemoAction, resolveKey } from '../demo/keymap'
import { normalizedRect } from '../demo/geometry'
import {
  BLUR_RADIUS,
  ERASER_RADIUS,
  INKS,
  type InkId,
  inkHex,
  type MarkStyle,
  type Point,
  SCREEN_HEIGHT,
  SCREEN_WIDTH,
  TEXT_SIZE,
  TOOLS,
  type ToolId,
} from '../demo/model'
import { drawableMarks, drawSession, TEXT_FONT_FAMILY, textFont } from '../demo/render'
import { DrawingSession } from '../demo/session'
import { BAR_LAYOUT, HIDDEN_TOOLS, moreButton } from '../demo/toolbar'
import { INK_EVENT } from './events'

interface Capture {
  id: number
  url: string
  pinned: boolean
}

/** The demo screen's capture, sized like the app's card for a 1200×720 display. */
const CARD = cardSize(SCREEN_WIDTH, SCREEN_HEIGHT)

/** Screen points as CSS: the cards layer is a container 1200 points wide. */
const pt = (points: number) => `calc(${points} * var(--pt))`

interface DemoElements {
  wrapper: HTMLElement
  screen: SVGSVGElement
  canvas: HTMLCanvasElement
  flash: HTMLElement
  blurs: HTMLElement
  cards: HTMLElement
}

export function mountDemo(wrapper: HTMLElement): void {
  const screen = wrapper.querySelector<SVGSVGElement>('#demo-screen')
  const canvas = wrapper.querySelector<HTMLCanvasElement>('#demo-ink')
  const flash = wrapper.querySelector<HTMLElement>('#demo-flash')
  const blurs = wrapper.querySelector<HTMLElement>('#demo-blurs')
  const cards = wrapper.querySelector<HTMLElement>('#demo-cards')
  const ui = wrapper.querySelector<HTMLElement>('#demo-ui')
  if (!screen || !canvas || !flash || !blurs || !cards || !ui) return
  render(<Demo elements={{ wrapper, screen, canvas, flash, blurs, cards }} />, ui)
}

/**
 * Lays one backdrop-blurred box over each blur mark, so the live page under
 * it really diffuses; the capture blurs the same rectangles on its canvas.
 */
function syncBlurs(layer: HTMLElement, session: DrawingSession, scale: number): void {
  const boxes = drawableMarks(session)
    .filter((d) => d.mark.tool === 'blur')
    .map(({ mark }) => normalizedRect(mark.points[0], mark.points[mark.points.length - 1]))
  while (layer.children.length > boxes.length) layer.lastElementChild!.remove()
  while (layer.children.length < boxes.length) layer.append(document.createElement('div'))
  const filter = `blur(${BLUR_RADIUS * scale}px)`
  boxes.forEach((r, i) => {
    const box = layer.children[i] as HTMLElement
    Object.assign(box.style, {
      position: 'absolute',
      left: `${(r.x / SCREEN_WIDTH) * 100}%`,
      top: `${(r.y / SCREEN_HEIGHT) * 100}%`,
      width: `${(r.width / SCREEN_WIDTH) * 100}%`,
      height: `${(r.height / SCREEN_HEIGHT) * 100}%`,
      backdropFilter: filter,
      webkitBackdropFilter: filter,
    })
  })
}

function Demo({ elements }: { elements: DemoElements }) {
  const { wrapper, screen, canvas, flash, blurs, cards } = elements
  const session = useRef(new DrawingSession()).current!
  const [tool, setTool] = useState<ToolId>('pen')
  const [ink, setInk] = useState<InkId>('red')
  const [captures, setCaptures] = useState<Capture[]>([])
  const [captureError, setCaptureError] = useState(false)
  const [copied, setCopied] = useState(0)
  // Drawing mode: Done (✕) leaves it, keeping the marks; ⌥⇧A comes back.
  const [drawing, setDrawing] = useState(true)
  const drawingRef = useRef(true)
  drawingRef.current = drawing
  // Where the gripper moved the bar, from its resting place.
  const [offset, setOffset] = useState({ x: 0, y: 0 })
  const barRef = useRef<HTMLDivElement>(null)
  // The ⁞ panel of hidden tools, open or not.
  const [moreOpen, setMoreOpen] = useState(false)
  const moreRef = useRef<HTMLDivElement>(null)
  // The app's 9 and 0: how the next shape and arrow are drawn.
  const [style, setStyle] = useState<MarkStyle>({ filled: false, arrowHead: 'open' })
  const toolRef = useRef<ToolId>('pen')
  const inkRef = useRef<InkId>('red')
  const styleRef = useRef<MarkStyle>(style)
  toolRef.current = tool
  inkRef.current = ink
  styleRef.current = style

  const redraw = useCallback(() => {
    const ratio = window.devicePixelRatio || 1
    const width = Math.round(canvas.clientWidth * ratio)
    const height = Math.round(canvas.clientHeight * ratio)
    if (canvas.width !== width || canvas.height !== height) {
      canvas.width = width
      canvas.height = height
    }
    const ctx = canvas.getContext('2d')
    if (!ctx) return
    ctx.setTransform(1, 0, 0, 1, 0, 0)
    ctx.clearRect(0, 0, width, height)
    const scale = width / SCREEN_WIDTH
    ctx.setTransform(scale, 0, 0, scale, 0, 0)
    drawSession(ctx, session, { now: performance.now() })
    syncBlurs(blurs, session, canvas.clientWidth / SCREEN_WIDTH)
    wrapper.toggleAttribute('data-drawn', !session.isEmpty)
  }, [])

  const capture = useCallback(async () => {
    // Flash first, like a shutter: encoding the PNG can take a moment and the
    // visitor should see that S did something right away.
    if (!window.matchMedia('(prefers-reduced-motion: reduce)').matches) {
      flash.animate([{ opacity: 0.8 }, { opacity: 0 }], { duration: 420, easing: 'ease-out' })
    }
    const scale = Math.min(2, Math.max(1, window.devicePixelRatio || 1))
    const pending = renderCapture(screen, session, { width: SCREEN_WIDTH, height: SCREEN_HEIGHT }, scale)
    // Like the app, the capture goes straight to the clipboard. Started here,
    // inside the key press or click, so the browser still counts the gesture.
    copyImage(pending).then(
      () => setCopied((n) => n + 1),
      () => {},
    )
    try {
      const blob = await pending
      setCaptureError(false)
      const added: Capture = { id: Date.now(), url: URL.createObjectURL(blob), pinned: false }
      setCaptures((list) => {
        const kept = evictOverflow([...list, added])
        for (const gone of list) if (!kept.includes(gone)) URL.revokeObjectURL(gone.url)
        return kept
      })
    } catch {
      setCaptureError(true)
    }
  }, [])

  const perform = useCallback((action: DemoAction) => {
    // Outside drawing mode only ⌥⇧A does anything, as in the app.
    if (!drawingRef.current) {
      if (action.type === 'start') setDrawing(true)
      return
    }
    switch (action.type) {
      case 'start':
        return
      case 'tool':
        return setTool(action.tool)
      case 'ink':
        return setInk(action.ink)
      case 'undo':
        session.undo()
        return redraw()
      case 'redo':
        session.redo()
        return redraw()
      case 'fill':
        return setStyle((s) => ({ ...s, filled: !s.filled }))
      case 'arrowHead':
        return setStyle((s) => ({ ...s, arrowHead: s.arrowHead === 'open' ? 'filled' : 'open' }))
      case 'clear':
        session.clear()
        return redraw()
      case 'capture':
        return void capture()
    }
  }, [])

  // Pointer drawing on the canvas, in the screen's 1200-point space.
  useEffect(() => {
    // 'erase' drags never create a mark; they wipe what they touch.
    let mode: 'draw' | 'erase' | null = null
    let frame = 0
    // Lasers fade without any input, so keep drawing frames until the last
    // one has gone; otherwise redraw only when the visitor draws.
    const scheduleRedraw = () => {
      if (frame) return
      frame = requestAnimationFrame((now) => {
        frame = 0
        const fading = session.prune(now)
        redraw()
        if (fading) scheduleRedraw()
      })
    }
    const toScreen = (event: PointerEvent): Point => {
      const rect = canvas.getBoundingClientRect()
      return {
        x: ((event.clientX - rect.left) / rect.width) * SCREEN_WIDTH,
        y: ((event.clientY - rect.top) / rect.height) * SCREEN_HEIGHT,
      }
    }
    const strokeWeight = () => {
      const shown = canvas.getBoundingClientRect().width
      return Math.min(3, Math.max(1, (SCREEN_WIDTH / shown) * 0.6))
    }

    const erase = (event: PointerEvent) => {
      if (session.erase(toScreen(event), ERASER_RADIUS * strokeWeight()) > 0) scheduleRedraw()
    }

    // The text tool types into a real field over the canvas, like the app's
    // NSTextField: Return or clicking away keeps it, Esc drops it, and empty
    // text never becomes a mark.
    let field: { input: HTMLInputElement; origin: Point; weight: number } | null = null
    const measure = document.createElement('canvas').getContext('2d')

    const finishText = (keep: boolean) => {
      if (!field) return
      const { input, origin, weight } = field
      field = null
      input.remove()
      if (keep && measure) {
        measure.font = textFont(weight)
        session.addText(origin, input.value, inkRef.current!, measure.measureText(input.value).width, weight)
      }
      scheduleRedraw()
    }

    const startText = (origin: Point) => {
      const weight = strokeWeight()
      const scale = canvas.getBoundingClientRect().width / SCREEN_WIDTH
      const input = document.createElement('input')
      input.type = 'text'
      input.setAttribute('aria-label', 'Text to place on the screen')
      input.autocomplete = 'off'
      input.spellcheck = false
      Object.assign(input.style, {
        position: 'absolute',
        left: `${canvas.offsetLeft + origin.x * scale}px`,
        top: `${canvas.offsetTop + origin.y * scale}px`,
        width: `${320 * scale}px`,
        font: `400 ${TEXT_SIZE * weight * scale}px ${TEXT_FONT_FAMILY}`,
        lineHeight: '1',
        color: inkHex(inkRef.current!),
        caretColor: inkHex(inkRef.current!),
        background: 'transparent',
        border: '0',
        outline: 'none',
        padding: '0',
        margin: '0',
      })
      input.addEventListener('keydown', (event) => {
        // Typed letters must not reach the demo's shortcuts.
        event.stopPropagation()
        if (event.key === 'Enter') finishText(true)
        if (event.key === 'Escape') finishText(false)
      })
      input.addEventListener('blur', () => finishText(true))
      canvas.parentElement!.append(input)
      field = { input, origin, weight }
      input.focus()
    }

    const down = (event: PointerEvent) => {
      if (event.button !== 0) return
      // Any click first commits the text being typed, as in the app.
      finishText(true)
      if (toolRef.current === 'text') {
        // Keep the click from moving focus off the new field.
        event.preventDefault()
        startText(toScreen(event))
        return
      }
      canvas.setPointerCapture(event.pointerId)
      if (toolRef.current === 'eraser') {
        mode = 'erase'
        erase(event)
        return
      }
      mode = 'draw'
      session.begin(toScreen(event), toolRef.current!, inkRef.current!, strokeWeight(), performance.now(), styleRef.current!)
      scheduleRedraw()
    }
    const move = (event: PointerEvent) => {
      if (!mode) return
      // Some browsers hand back an empty list (untrusted events); fall back to
      // the event itself so no sample is lost.
      const coalesced = event.getCoalescedEvents?.() ?? []
      for (const sample of coalesced.length > 0 ? coalesced : [event]) {
        if (mode === 'erase') erase(sample)
        else session.extend(toScreen(sample))
      }
      scheduleRedraw()
    }
    const up = () => {
      if (!mode) return
      const wasDrawing = mode === 'draw'
      mode = null
      if (!wasDrawing) return
      session.end()
      scheduleRedraw()
    }

    canvas.addEventListener('pointerdown', down)
    canvas.addEventListener('pointermove', move)
    canvas.addEventListener('pointerup', up)
    canvas.addEventListener('pointercancel', up)
    const resize = new ResizeObserver(() => redraw())
    resize.observe(canvas)
    redraw()
    return () => {
      canvas.removeEventListener('pointerdown', down)
      canvas.removeEventListener('pointermove', move)
      canvas.removeEventListener('pointerup', up)
      canvas.removeEventListener('pointercancel', up)
      resize.disconnect()
      field?.input.remove()
    }
  }, [])

  // Like the app, the panel closes on any interaction that is not its own: a
  // click elsewhere or a key press (which still does its job).
  useEffect(() => {
    if (!moreOpen) return
    const away = (event: Event) => {
      if (!moreRef.current?.contains(event.target as Node)) setMoreOpen(false)
    }
    const key = () => setMoreOpen(false)
    window.addEventListener('pointerdown', away, true)
    window.addEventListener('keydown', key, true)
    return () => {
      window.removeEventListener('pointerdown', away, true)
      window.removeEventListener('keydown', key, true)
    }
  }, [moreOpen])

  // Tell the page which ink is active, for a pointer highlight that follows it.
  useEffect(() => {
    window.dispatchEvent(new CustomEvent(INK_EVENT, { detail: ink }))
  }, [ink])

  // The app shows an I-beam over the screen while the text tool is active.
  useEffect(() => {
    canvas.style.cursor = tool === 'text' ? 'text' : ''
  }, [tool])

  // Shortcuts apply while the pointer is over the demo or focus is inside it,
  // so typing elsewhere on the page is never hijacked.
  useEffect(() => {
    const keydown = (event: KeyboardEvent) => {
      if (event.target instanceof HTMLInputElement || event.target instanceof HTMLTextAreaElement) return
      const armed = wrapper.matches(':hover') || wrapper.contains(document.activeElement)
      if (!armed || event.repeat) return
      const action = resolveKey(event)
      if (!action) return
      event.preventDefault()
      perform(action)
    }
    window.addEventListener('keydown', keydown)
    return () => window.removeEventListener('keydown', keydown)
  }, [])

  const dismiss = useCallback((id: number) => {
    setCaptures((list) => {
      const gone = list.find((c) => c.id === id)
      if (gone) URL.revokeObjectURL(gone.url)
      return list.filter((c) => c.id !== id)
    })
  }, [])

  const togglePin = useCallback((id: number) => {
    setCaptures((list) => list.map((c) => (c.id === id ? { ...c, pinned: !c.pinned } : c)))
  }, [])

  // Leaving drawing mode hides the marks and stops the canvas taking input;
  // they come back untouched with ⌥⇧A.
  useEffect(() => {
    for (const layer of [canvas, blurs]) {
      layer.style.visibility = drawing ? '' : 'hidden'
    }
    if (!drawing) setMoreOpen(false)
  }, [drawing])

  // The ⠇⠇ gripper moves the bar; a right click puts it back, as in the app.
  const grab = (event: PointerEvent) => {
    if (event.button !== 0) return
    const handle = event.currentTarget as HTMLElement
    handle.setPointerCapture(event.pointerId)
    const start = { x: event.clientX - offset.x, y: event.clientY - offset.y }
    const bounds = wrapper.getBoundingClientRect()
    const bar = barRef.current!.getBoundingClientRect()
    // The bar may go anywhere over the screen, never off it.
    const limit = {
      left: bounds.left - (bar.left - offset.x),
      right: bounds.right - (bar.right - offset.x),
      top: bounds.top - (bar.top - offset.y),
      bottom: bounds.bottom - (bar.bottom - offset.y),
    }
    const move = (e: PointerEvent) =>
      setOffset({
        x: Math.min(limit.right, Math.max(limit.left, e.clientX - start.x)),
        y: Math.min(limit.bottom, Math.max(limit.top, e.clientY - start.y)),
      })
    const stop = () => {
      handle.removeEventListener('pointermove', move)
      handle.removeEventListener('pointerup', stop)
      handle.removeEventListener('pointercancel', stop)
    }
    handle.addEventListener('pointermove', move)
    handle.addEventListener('pointerup', stop)
    handle.addEventListener('pointercancel', stop)
  }

  return (
    <>
      <div
        ref={barRef}
        role="toolbar"
        aria-label="Stare drawing tools"
        hidden={!drawing}
        style={{ marginLeft: `${offset.x}px`, marginTop: `${offset.y}px` }}
        class="pointer-events-auto mx-auto mt-4 flex max-w-full flex-wrap items-center justify-center gap-0.5 rounded-[14px] border border-white/12 bg-chrome/82 px-3 py-2 font-mac shadow-toolbar backdrop-blur-xl md:absolute md:top-[16%] md:left-1/2 md:mt-0 md:w-max md:-translate-x-1/2 md:flex-nowrap"
      >
        {BAR_LAYOUT.map((item) => {
          if (item === '|') return <Divider />
          const t = TOOLS.find((info) => info.id === item)!
          return <ToolbarButton label={`${t.name} (${t.key})`} pressed={tool === t.id} symbol={TOOL_SYMBOLS[t.id]} onClick={() => setTool(t.id)} />
        })}
        <div ref={moreRef} class="relative">
          <ToolbarButton
            label={moreButton(tool).label}
            pressed={HIDDEN_TOOLS.includes(tool)}
            expanded={moreOpen}
            symbol={moreButton(tool).icon === 'more' ? ACTION_SYMBOLS.more : TOOL_SYMBOLS[tool]}
            onClick={() => setMoreOpen((open) => !open)}
          />
          {moreOpen && (
            // Opens toward the middle of the screen, centred on its button, as the app's panel does.
            <div
              role="group"
              aria-label="More tools"
              class="absolute top-full left-1/2 z-10 mt-2.5 flex -translate-x-1/2 gap-1 rounded-[12px] border border-white/12 bg-chrome/90 p-1.5 shadow-toolbar backdrop-blur-xl motion-safe:animate-card-in"
            >
              {HIDDEN_TOOLS.map((id) => {
                const t = TOOLS.find((info) => info.id === id)!
                return (
                  <ToolbarButton
                    label={`${t.name} (${t.key})`}
                    pressed={tool === id}
                    symbol={TOOL_SYMBOLS[id]}
                    onClick={() => {
                      setTool(id)
                      setMoreOpen(false)
                    }}
                  />
                )
              })}
            </div>
          )}
        </div>
        <Divider />
        {INKS.map((i) => (
          <button
            type="button"
            aria-label={`${i.name} ink (${i.key})`}
            aria-pressed={String(ink === i.id)}
            title={`${i.name} (${i.key})`}
            onClick={() => setInk(i.id)}
            class="grid size-6 shrink-0 place-items-center rounded-full"
          >
            <span
              class={`block size-[15px] rounded-full ${ink === i.id ? 'ring-2 ring-white' : 'ring-1 ring-white/25'}`}
              style={{ backgroundColor: i.hex }}
            />
          </button>
        ))}
        <Divider />
        <ToolbarButton label="Undo (⌘Z)" symbol={ACTION_SYMBOLS.undo} action onClick={() => perform({ type: 'undo' })} />
        <ToolbarButton label="Redo (⇧⌘Z)" symbol={ACTION_SYMBOLS.redo} action onClick={() => perform({ type: 'redo' })} />
        <ToolbarButton label="Clear all (Esc)" symbol={ACTION_SYMBOLS.clear} action onClick={() => perform({ type: 'clear' })} />
        <ToolbarButton label="Done" symbol={ACTION_SYMBOLS.close} action onClick={() => setDrawing(false)} />
        {/* The bar only moves where it floats over the screen, so phones skip the handle. */}
        <button
          type="button"
          aria-label="Move the bar (right-click puts it back)"
          title="Drag to move · right-click to reset"
          onPointerDown={grab}
          onContextMenu={(event: MouseEvent) => {
            event.preventDefault()
            setOffset({ x: 0, y: 0 })
          }}
          class="hidden h-[26px] w-4 shrink-0 cursor-grab touch-none text-white/60 active:cursor-grabbing md:block"
        >
          <svg aria-hidden="true" viewBox="0 0 16 26" width="16" height="26" fill="currentColor">
            {[5, 11].map((x) => [8, 13, 18].map((y) => <circle cx={x} cy={y} r="1.5" />))}
          </svg>
        </button>
      </div>

      {/* Phones have no S key, so they get a capture control below the screen (not on the bar, which has none). */}
      <div class="mt-3 flex justify-center [@media(hover:hover)]:hidden">
        <button
          type="button"
          onClick={() => perform({ type: 'capture' })}
          class="pointer-events-auto rounded-full bg-graphite px-5 py-2.5 text-[15px] font-semibold text-paper"
        >
          Capture the screen
        </button>
      </div>

      <div aria-live="polite" class="pointer-events-none mt-3 flex justify-center md:absolute md:bottom-[4%] md:left-[2.5%] md:mt-0">
        {captureError && (
          <p class="pointer-events-auto rounded-xl bg-chrome/90 px-4 py-3 font-mac text-[13px] text-white">
            This browser blocked the capture. Try the latest Chrome, Safari or Firefox.
          </p>
        )}
        {copied > 0 && <span class="sr-only">Capture {copied} copied to the clipboard.</span>}
      </div>

      {createPortal(
        <div class="absolute inset-0 [--pt:max(calc(100cqw/1200),0.6px)]">
          {stackBottoms(captures.map(() => CARD.height)).map((bottom, i) => {
            const c = captures[i]
            return <CaptureCard key={c.id} capture={c} bottom={bottom} onDismiss={() => dismiss(c.id)} onPin={() => togglePin(c.id)} />
          })}
          {!drawing && (
            <button
              type="button"
              onClick={() => setDrawing(true)}
              class="pointer-events-auto absolute top-[16%] left-1/2 -translate-x-1/2 rounded-full bg-chrome/85 px-4 py-2 font-mac text-[13px] text-white shadow-toolbar backdrop-blur-xl hover:bg-chrome"
            >
              Start drawing <kbd class="ml-1 opacity-70">⌥⇧A</kbd>
            </button>
          )}
        </div>,
        cards,
      )}
    </>
  )
}

function Divider() {
  return <span aria-hidden="true" class="mx-1 h-5 w-px shrink-0 bg-white/18" />
}

/** An app bar button: 28×26 for a tool, 26×26 for an action, as ToolbarView sizes them. */
function ToolbarButton(props: {
  label: string
  symbol: string
  pressed?: boolean
  expanded?: boolean
  action?: boolean
  onClick: () => void
}) {
  const active = props.pressed === true
  return (
    <button
      type="button"
      aria-label={props.label}
      aria-pressed={props.pressed === undefined ? undefined : String(props.pressed)}
      aria-expanded={props.expanded === undefined ? undefined : String(props.expanded)}
      title={props.label}
      onClick={props.onClick}
      class={`grid h-[26px] ${props.action ? 'w-[26px]' : 'w-7'} shrink-0 place-items-center rounded-[7px] transition-colors ${
        active ? 'bg-ink-blue/55 text-white' : 'text-white/60 hover:text-white'
      }`}
    >
      <SfSymbol name={props.symbol} />
    </button>
  )
}

/** An SF Symbol of the app, filled with the current text colour. */
function SfSymbol({ name, size = 26 }: { name: string; size?: number }) {
  return <span aria-hidden="true" class="sf-symbol" style={symbolStyle(name, size)} />
}

/**
 * CaptureCardView: the capture on a dark rounded plate, with the round pin and
 * close buttons in its top-right corner. Clicking opens it (the app opens its
 * editor; here, the full image), dragging takes the image anywhere. It leaves
 * after 5 s, 3 s once hovered, and stays while hovered or pinned.
 */
function CaptureCard(props: { capture: Capture; bottom: number; onDismiss: () => void; onPin: () => void }) {
  const { capture } = props
  const [hovered, setHovered] = useState(false)
  const [hasBeenHovered, setHasBeenHovered] = useState(false)

  useEffect(() => {
    const delay = autoDismissDelay({ pinned: capture.pinned, hovered, hasBeenHovered })
    if (delay === null) return
    const timer = setTimeout(props.onDismiss, delay)
    return () => clearTimeout(timer)
  }, [hovered, hasBeenHovered, capture.pinned])

  const enter = () => {
    setHovered(true)
    setHasBeenHovered(true)
  }
  const control = (symbol: string, label: string, onClick: () => void, right: number) => (
    <button
      type="button"
      aria-label={label}
      title={label}
      onClick={onClick}
      class="absolute grid place-items-center rounded-full bg-black/55 text-white"
      style={{ top: pt(PLATE_INSET), right: pt(right), width: pt(CONTROL_SIDE), height: pt(CONTROL_SIDE) }}
    >
      <span aria-hidden="true" class="sf-symbol" style={symbolStyle(symbol, pt(CONTROL_SIDE))} />
    </button>
  )

  return (
    <div
      onMouseEnter={enter}
      onMouseLeave={() => setHovered(false)}
      onFocusIn={enter}
      onFocusOut={() => setHovered(false)}
      class="pointer-events-auto absolute cursor-default shadow-card"
      style={{
        right: pt(STACK_MARGIN),
        bottom: pt(props.bottom),
        width: pt(CARD.width),
        height: pt(CARD.height),
        borderRadius: pt(10),
        backgroundColor: 'rgb(20 20 20 / 0.92)',
        // A pinned card says so on the plate itself: a 2 pt blue line just inside its edge.
        outline: capture.pinned ? '2px solid rgb(92 168 255 / 0.95)' : 'none',
        outlineOffset: '-3px',
      }}
    >
      <a
        href={capture.url}
        target="_blank"
        rel="noopener"
        aria-label="Open the capture"
        title="Click to open · drag it anywhere"
        class="absolute block overflow-hidden"
        style={{ inset: pt(PLATE_INSET), borderRadius: pt(5) }}
      >
        <img src={capture.url} alt="Your capture with marks" class="block size-full" draggable />
      </a>
      {control(capture.pinned ? CARD_SYMBOLS.pinned : CARD_SYMBOLS.pin, capture.pinned ? 'Unpin the card' : 'Pin the card open', props.onPin, PLATE_INSET + CONTROL_SIDE + 4)}
      {control(CARD_SYMBOLS.close, 'Close the card', props.onDismiss, PLATE_INSET)}
    </div>
  )
}
