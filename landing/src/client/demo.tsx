/** @jsxImportSource hono/jsx/dom */
// The interactive layer of the demo: toolbar, drawing on the canvas, keyboard
// shortcuts and capture cards. The screen itself is prerendered on the server.
import { useCallback, useEffect, useRef, useState } from 'hono/jsx'
import { render } from 'hono/jsx/dom'
import { copyImage, renderCapture } from '../demo/capture'
import { ACTION_ICONS, TOOL_ICONS } from '../demo/icons'
import { type DemoAction, resolveKey } from '../demo/keymap'
import { INKS, type InkId, type Point, SCREEN_HEIGHT, SCREEN_WIDTH, TOOLS, type ToolId } from '../demo/model'
import { drawSession } from '../demo/render'
import { DrawingSession } from '../demo/session'

/** Capture cards leave on their own after this long, unless hovered. */
const CARD_LIFETIME_MS = 5000

interface Capture {
  id: number
  blob: Blob
  url: string
}

interface DemoElements {
  wrapper: HTMLElement
  screen: SVGSVGElement
  canvas: HTMLCanvasElement
  flash: HTMLElement
}

export function mountDemo(wrapper: HTMLElement): void {
  const screen = wrapper.querySelector<SVGSVGElement>('#demo-screen')
  const canvas = wrapper.querySelector<HTMLCanvasElement>('#demo-ink')
  const flash = wrapper.querySelector<HTMLElement>('#demo-flash')
  const ui = wrapper.querySelector<HTMLElement>('#demo-ui')
  if (!screen || !canvas || !flash || !ui) return
  render(<Demo elements={{ wrapper, screen, canvas, flash }} />, ui)
}

function Demo({ elements }: { elements: DemoElements }) {
  const { wrapper, screen, canvas, flash } = elements
  const session = useRef(new DrawingSession()).current!
  const [tool, setTool] = useState<ToolId>('pen')
  const [ink, setInk] = useState<InkId>('red')
  const [captures, setCaptures] = useState<Capture[]>([])
  const [captureError, setCaptureError] = useState(false)
  const toolRef = useRef<ToolId>('pen')
  const inkRef = useRef<InkId>('red')
  toolRef.current = tool
  inkRef.current = ink

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
    drawSession(ctx, session)
    wrapper.toggleAttribute('data-drawn', !session.isEmpty)
  }, [])

  const capture = useCallback(async () => {
    // Flash first, like a shutter: encoding the PNG can take a moment and the
    // visitor should see that S did something right away.
    if (!window.matchMedia('(prefers-reduced-motion: reduce)').matches) {
      flash.animate([{ opacity: 0.8 }, { opacity: 0 }], { duration: 420, easing: 'ease-out' })
    }
    try {
      const scale = Math.min(2, Math.max(1, window.devicePixelRatio || 1))
      const blob = await renderCapture(screen, session, { width: SCREEN_WIDTH, height: SCREEN_HEIGHT }, scale)
      setCaptureError(false)
      setCaptures((list) => [...list, { id: Date.now(), blob, url: URL.createObjectURL(blob) }])
    } catch {
      setCaptureError(true)
    }
  }, [])

  const perform = useCallback((action: DemoAction) => {
    switch (action.type) {
      case 'tool':
        return setTool(action.tool)
      case 'ink':
        return setInk(action.ink)
      case 'undo':
        session.undo()
        return redraw()
      case 'clear':
        session.clear()
        return redraw()
      case 'capture':
        return void capture()
    }
  }, [])

  // Pointer drawing on the canvas, in the screen's 1200-point space.
  useEffect(() => {
    let drawing = false
    let frame = 0
    const scheduleRedraw = () => {
      if (frame) return
      frame = requestAnimationFrame(() => {
        frame = 0
        redraw()
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

    const down = (event: PointerEvent) => {
      if (event.button !== 0) return
      drawing = true
      canvas.setPointerCapture(event.pointerId)
      session.begin(toScreen(event), toolRef.current!, inkRef.current!, strokeWeight())
      scheduleRedraw()
    }
    const move = (event: PointerEvent) => {
      if (!drawing) return
      for (const sample of event.getCoalescedEvents?.() ?? [event]) session.extend(toScreen(sample))
      scheduleRedraw()
    }
    const up = () => {
      if (!drawing) return
      drawing = false
      session.end()
      redraw()
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
    }
  }, [])

  // Shortcuts apply while the pointer is over the demo or focus is inside it,
  // so typing elsewhere on the page is never hijacked.
  useEffect(() => {
    const keydown = (event: KeyboardEvent) => {
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

  return (
    <>
      <div
        role="toolbar"
        aria-label="Stare drawing tools"
        class="pointer-events-auto mx-auto mt-4 flex max-w-full flex-wrap items-center justify-center gap-0.5 rounded-[14px] border border-white/12 bg-chrome/82 px-3 py-2 font-mac shadow-toolbar backdrop-blur-xl md:absolute md:top-[7%] md:left-1/2 md:mt-0 md:w-max md:-translate-x-1/2 md:flex-nowrap"
      >
        {TOOLS.map((t) => (
          <ToolbarButton
            label={`${t.name} (${t.key})`}
            pressed={tool === t.id}
            path={TOOL_ICONS[t.id]}
            onClick={() => setTool(t.id)}
          />
        ))}
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
        <ToolbarButton label="Undo (⌘Z)" path={ACTION_ICONS.undo} onClick={() => perform({ type: 'undo' })} />
        <ToolbarButton label="Clear all (Esc)" path={ACTION_ICONS.clear} onClick={() => perform({ type: 'clear' })} />
        <Divider />
        <ToolbarButton label="Capture screen (S)" path={ACTION_ICONS.capture} onClick={() => perform({ type: 'capture' })} />
      </div>

      <div
        aria-live="polite"
        class="pointer-events-none mt-3 flex flex-col items-end gap-3 md:absolute md:right-[2.5%] md:bottom-[4%] md:mt-0"
      >
        {captureError && (
          <p class="pointer-events-auto rounded-xl bg-chrome/90 px-4 py-3 font-mac text-[13px] text-white">
            This browser blocked the capture. Try the latest Chrome, Safari or Firefox.
          </p>
        )}
        {captures.map((c) => (
          <CaptureCard capture={c} onDismiss={() => dismiss(c.id)} />
        ))}
      </div>
    </>
  )
}

function Divider() {
  return <span aria-hidden="true" class="mx-1 h-5 w-px shrink-0 bg-white/18" />
}

function ToolbarButton(props: { label: string; path: string; pressed?: boolean; onClick: () => void }) {
  const active = props.pressed === true
  return (
    <button
      type="button"
      aria-label={props.label}
      aria-pressed={props.pressed === undefined ? undefined : String(props.pressed)}
      title={props.label}
      onClick={props.onClick}
      class={`grid h-[26px] w-7 shrink-0 place-items-center rounded-[7px] transition-colors ${
        active ? 'bg-ink-blue/55 text-white' : 'text-white/60 hover:text-white'
      }`}
    >
      <Icon path={props.path} />
    </button>
  )
}

function Icon({ path, size = 16 }: { path: string; size?: number }) {
  return (
    <svg
      aria-hidden="true"
      viewBox="0 0 24 24"
      width={size}
      height={size}
      fill="none"
      stroke="currentColor"
      stroke-width="1.8"
      stroke-linecap="round"
      stroke-linejoin="round"
    >
      <path d={path} />
    </svg>
  )
}

function CaptureCard({ capture, onDismiss }: { capture: Capture; onDismiss: () => void }) {
  const [copy, setCopy] = useState<'idle' | 'copied' | 'failed'>('idle')
  const [hovered, setHovered] = useState(false)

  // Five seconds on screen; hovering keeps the card until the pointer leaves.
  useEffect(() => {
    if (hovered) return
    const timer = setTimeout(onDismiss, CARD_LIFETIME_MS)
    return () => clearTimeout(timer)
  }, [hovered])

  const onCopy = async () => {
    try {
      await copyImage(capture.blob)
      setCopy('copied')
    } catch {
      setCopy('failed')
    }
  }

  return (
    <div
      onMouseEnter={() => setHovered(true)}
      onMouseLeave={() => setHovered(false)}
      onFocusIn={() => setHovered(true)}
      onFocusOut={() => setHovered(false)}
      class="pointer-events-auto w-56 overflow-hidden rounded-xl border border-white/12 bg-chrome/88 font-mac text-white shadow-card backdrop-blur-xl motion-safe:animate-card-in"
    >
      <img src={capture.url} alt="Your capture with marks" class="block aspect-[5/3] w-full object-cover" draggable />
      <div class="flex items-center gap-1 p-1.5 text-[12.5px]">
        <button
          type="button"
          onClick={onCopy}
          class="flex flex-1 items-center justify-center gap-1.5 rounded-lg px-2 py-1.5 hover:bg-white/10"
        >
          <Icon path={ACTION_ICONS.copy} size={14} />
          {copy === 'copied' ? 'Copied' : copy === 'failed' ? 'Copy blocked' : 'Copy'}
        </button>
        <a
          href={capture.url}
          download="Stare capture.png"
          class="flex flex-1 items-center justify-center gap-1.5 rounded-lg px-2 py-1.5 hover:bg-white/10"
        >
          <Icon path={ACTION_ICONS.save} size={14} />
          Save
        </a>
      </div>
    </div>
  )
}
