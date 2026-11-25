// "Every tool is one key away" as a Mac keyboard you can press. Stare's keys
// are buttons marked with their tool icon or ink; pressing them (on your own
// keyboard or here) draws a live sample in the panel that client/keyboard.tsx
// mounts into #key-preview. The rest of the keyboard is quiet decoration.
import { ACTION_SYMBOLS, symbolStyle, TOOL_SYMBOLS } from '../demo/icons'
import { INKS, TOOLS } from '../demo/model'
import { container, sectionTitle } from './sections'
import { Kbd } from './ui'

interface KeySpec {
  label: string
  /** Width in standard key units. */
  w?: number
  /** Value fed to the keymap when the key is clicked (KeyboardEvent.key). */
  press?: string
  meta?: boolean
  /** Name used by the page-wide shortcut highlighter (client/effects.ts). */
  flash?: string
  kind?: 'tool' | 'ink' | 'action' | 'modifier'
  /** SF Symbol name of a Stare key. */
  icon?: string
  color?: string
  hint?: string
}

const tool = (key: string): KeySpec => {
  const info = TOOLS.find((t) => t.key === key)!
  return { label: key, press: key.toLowerCase(), flash: key, kind: 'tool', icon: TOOL_SYMBOLS[info.id], hint: info.name }
}
const ink = (key: string): KeySpec => {
  const info = INKS.find((i) => i.key === key)!
  return { label: key, press: key, flash: key, kind: 'ink', color: info.hex, hint: info.name }
}
const plain = (label: string, w = 1): KeySpec => ({ label, w })

const rows: KeySpec[][] = [
  [
    { label: 'esc', w: 1.5, press: 'Escape', flash: 'Esc', kind: 'action', hint: 'Clear' },
    ...['1', '2', '3', '4', '5', '6', '7', '8'].map(ink),
    { label: '9', press: '9', flash: '9', kind: 'action', icon: ACTION_SYMBOLS.fill, hint: 'Fill' },
    { label: '0', press: '0', flash: '0', kind: 'action', icon: ACTION_SYMBOLS.arrowHead, hint: 'Arrow head' },
    plain('-'),
    plain('='),
    plain('delete', 1.5),
  ],
  [
    plain('tab', 1.5),
    plain('Q'),
    plain('W'),
    tool('E'),
    tool('R'),
    tool('T'),
    plain('Y'),
    plain('U'),
    plain('I'),
    tool('O'),
    tool('P'),
    plain('['),
    plain(']'),
    plain('\\', 1.5),
  ],
  [
    plain('caps lock', 1.8),
    tool('A'),
    { label: 'S', press: 's', flash: 'S', kind: 'action', icon: ACTION_SYMBOLS.capture, hint: 'Capture' },
    tool('D'),
    tool('F'),
    plain('G'),
    tool('H'),
    plain('J'),
    plain('K'),
    tool('L'),
    plain(';'),
    plain("'"),
    plain('return', 2.2),
  ],
  [
    { label: '⇧ shift', w: 2.3, kind: 'modifier', hint: 'Start' },
    { label: 'Z', press: 'z', meta: true, flash: '⌘Z', kind: 'action', icon: ACTION_SYMBOLS.undo, hint: '⌘ Undo' },
    plain('X'),
    tool('C'),
    plain('V'),
    tool('B'),
    plain('N'),
    plain('M'),
    plain(','),
    plain('.'),
    plain('/'),
    plain('⇧ shift', 2.7),
  ],
  [
    plain('fn'),
    plain('control'),
    { label: '⌥ option', kind: 'modifier', hint: 'Start' },
    { label: '⌘', w: 1.3, kind: 'modifier' },
    plain('', 5.4),
    plain('⌘', 1.3),
    plain('⌥'),
    plain('←'),
    plain('↑↓'),
    plain('→'),
  ],
]

function Key({ spec }: { spec: KeySpec }) {
  // Space-grey MacBook keys: quiet for most of the board, lit for Stare's.
  const base =
    'relative flex h-[4.6cqw] min-w-0 flex-col justify-between rounded-[0.7cqw] px-[0.7cqw] py-[0.55cqw] text-left font-mac text-[1.25cqw] leading-none transition-[transform,box-shadow,background-color] duration-150'
  const style = { flex: `${spec.w ?? 1} 1 0` }

  if (!spec.kind) {
    return (
      <span aria-hidden="true" class={`${base} bg-key text-white/30 shadow-key`} style={style}>
        {spec.label}
      </span>
    )
  }

  if (spec.kind === 'modifier') {
    return (
      <span aria-hidden="true" class={`${base} bg-key text-white/75 shadow-key`} style={style}>
        <span>{spec.label}</span>
        {spec.hint && <span class="text-[0.95cqw] font-semibold text-ink-sky">{spec.hint}</span>}
      </span>
    )
  }

  return (
    <button
      type="button"
      data-keycap
      data-key={spec.flash}
      data-press={spec.press}
      data-meta={spec.meta ? '' : undefined}
      aria-label={`${spec.label}: ${spec.hint}${spec.kind === 'ink' ? ' ink' : ''}`}
      class={`${base} cursor-pointer bg-key-lit text-white shadow-key ring-1 ring-ink-sky/25 hover:bg-key-hover hover:ring-ink-sky/60`}
      style={style}
    >
      <span class="flex items-center justify-between gap-1">
        <span class="font-semibold">{spec.label}</span>
        {spec.color && (
          <span
            class="size-[1.3cqw] rounded-full ring-1 ring-white/25"
            style={{ backgroundColor: spec.color, boxShadow: `0 0 0.9cqw ${spec.color}` }}
          />
        )}
      </span>
      {spec.icon ? (
        // The symbol sits on a 26 pt canvas with room around it; the negative
        // margin lets the glyph, not the canvas, line up with the key's edge.
        <span
          aria-hidden="true"
          class="sf-symbol -m-[0.55cqw] self-end text-ink-sky drop-shadow-[0_0_0.5cqw_rgb(108_180_255/0.6)]"
          style={symbolStyle(spec.icon, '3cqw')}
        />
      ) : (
        <span class="truncate text-[0.95cqw] text-white/55">{spec.hint}</span>
      )}
    </button>
  )
}

/** Global shortcuts and drawing-mode combinations, as the app ships them. */
const combos: [string[], string][] = [
  [['⌥', '⇧', 'A'], 'start drawing over any app'],
  [['⌥', '⇧', 'W'], 'open the whiteboard'],
  [['⇧', 'S'], 'capture an area you drag'],
  [['⌥', 'S'], 'capture the front window'],
  [['⌥', '⇧', 'O'], 'copy the text or QR code in an area'],
  [['⌥', '⇧', 'I'], 'open your recent captures'],
  [['⌘', 'Z'], 'undo the last mark'],
  [['⇧', '⌘', 'Z'], 'redo it'],
]

export function Shortcuts() {
  return (
    <section id="shortcuts" aria-labelledby="shortcuts-title" class="relative scroll-mt-20 overflow-hidden bg-paper">
      <div aria-hidden="true" class="bg-dots pointer-events-none absolute inset-0 opacity-70" />
      <div class={`${container} relative py-20 md:py-28`}>
        <div data-reveal class="max-w-[38rem]">
          <h2 id="shortcuts-title" class={sectionTitle}>
            Every tool is one key away
          </h2>
          <p class="mt-3 text-[17px] leading-relaxed text-muted">
            Go ahead: press <Kbd>H</Kbd>, then <Kbd>3</Kbd>, then <Kbd>A</Kbd> on your keyboard, or tap the keys below.
            The panel draws what each one does.
          </p>
        </div>

        <div data-reveal style={{ '--delay': '120ms' }} class="mt-12 grid items-start gap-6 lg:grid-cols-[minmax(0,1fr)_340px]">
          {/* min-w-0: as a grid item this would otherwise grow to the keyboard's
              720px minimum and drag the panel off-screen on phones. */}
          <div class="min-w-0">
            {/* Key sizes are in container units, so the keyboard scales as one
                piece. Below 720px it keeps that width and scrolls sideways;
                the vertical padding leaves room for the shadow overflow clips. */}
            <div class="-mx-4 overflow-x-auto px-4 pt-1 pb-8 md:mx-0 md:overflow-visible md:px-0 md:pb-0">
              <div class="@container min-w-[720px]">
                <div class="flex flex-col gap-[0.6cqw] rounded-[1.8cqw] bg-gradient-to-b from-board to-key p-[1.3cqw] shadow-window ring-1 ring-black/40">
                  {rows.map((row) => (
                    <div class="flex gap-[0.55cqw]">
                      {row.map((spec) => (
                        <Key spec={spec} />
                      ))}
                    </div>
                  ))}
                </div>
              </div>
            </div>
            {/* The app's key combinations, which a keyboard of single keys
                can't show on its own. */}
            <ul class="grid gap-x-8 gap-y-3 text-[15px] text-muted sm:grid-cols-2 md:mt-6" aria-label="Key combinations">
              {combos.map(([keys, what]) => (
                <li class="flex items-center gap-2">
                  <span class="flex shrink-0 items-center gap-1">
                    {keys.map((k, i) => (
                      <>
                        {i > 0 && '+'}
                        <Kbd>{k}</Kbd>
                      </>
                    ))}
                  </span>
                  {what}
                </li>
              ))}
            </ul>
          </div>
          {/* Filled in by client/keyboard.tsx; without JavaScript the keys still list every shortcut. */}
          <div id="key-preview" class="min-h-[320px]" />
        </div>
      </div>
    </section>
  )
}
