// "More than a screenshot": what Stare does with a capture once it has one, as
// six cards, each with a small SVG scene looping in CSS (.c1-* to .c6-* in
// style.css). Like the "How it works" scenes, they rest on a complete state and
// only play once revealed; reduced motion leaves them still.
import type { Child } from 'hono/jsx'
import { container, sectionTitle } from './sections'
import { MAC, MiniWindow } from './Steps'
import { Kbd } from './ui'

const RED = '#ff3b30'
const BLUE = '#007aff'
const PURPLE = '#b052de'

function TextLines({ x, y, widths, gap = 12, color = '#c9d0dc' }: { x: number; y: number; widths: number[]; gap?: number; color?: string }) {
  return (
    <g>
      {widths.map((w, i) => (
        <rect x={x} y={y + i * gap} width={w} height="5" rx="2.5" fill={color} />
      ))}
    </g>
  )
}

/** ⇧S: an area drag with the magnifier riding its corner. */
function SceneArea() {
  return (
    <svg viewBox="0 0 320 180" class="step-anim block w-full" aria-hidden="true">
      <MiniWindow x={30} y={14} width={260} height={156} />
      <rect class="c1-dim" x="30" y="14" width="260" height="156" rx="10" fill="#1c2030" fill-opacity=".18" />
      <rect class="c1-sel" x="60" y="58" width="150" height="80" fill="#fff" fill-opacity=".25" stroke={BLUE} stroke-width="1.5" stroke-dasharray="5 3" />
      <g class="c1-loupe">
        <circle cx="210" cy="138" r="22" fill="#fff" stroke="#1c2030" stroke-opacity=".35" stroke-width="1.5" />
        <path d="M200 138h20M210 128v20" stroke={BLUE} stroke-width="1.5" />
        <rect x="186" y="160" width="48" height="13" rx="6.5" fill="#1c2030" />
        <text x="210" y="169.5" font-size="8.5" fill="#fff" text-anchor="middle" font-family={MAC}>150 × 80</text>
      </g>
    </svg>
  )
}

/** A pinned capture floating over the windows, with its pin, close and lock. */
function ScenePin() {
  return (
    <svg viewBox="0 0 320 180" class="step-anim block w-full" aria-hidden="true">
      <MiniWindow x={18} y={20} width={200} height={140} />
      <g class="c2-pin">
        <rect x="150" y="34" width="150" height="98" rx="8" fill="#23262f" />
        <rect x="157" y="41" width="136" height="84" rx="5" fill="#fff" />
        <TextLines x={167} y={54} widths={[70, 100, 84]} />
        <ellipse cx="200" cy="105" rx="26" ry="11" fill="none" stroke={RED} stroke-width="2" />
        {[
          [158, '📌'],
          [176, '✕'],
          [194, '🔒'],
        ].map(([cx, label]) => (
          <g>
            <circle cx={cx} cy="31" r="8" fill="#23262f" stroke="#fff" stroke-opacity=".25" />
            <text x={cx} y="34.5" font-size="8.5" fill="#fff" text-anchor="middle" font-family={MAC}>
              {label}
            </text>
          </g>
        ))}
      </g>
    </svg>
  )
}

/** ⌥⇧I: the recent captures, the selection moving, one copied again. */
function SceneHistory() {
  const tiles = [0, 1, 2, 3, 4, 5].map((i) => ({ x: 44 + (i % 3) * 80, y: 22 + Math.floor(i / 3) * 60 }))
  return (
    <svg viewBox="0 0 320 180" class="step-anim block w-full" aria-hidden="true">
      <rect x="30" y="10" width="260" height="168" rx="14" fill="#23262f" />
      {tiles.map(({ x, y }, i) => (
        <g>
          <rect x={x} y={y} width="72" height="52" rx="6" fill={['#b3aee8', '#dbe4f3', '#ffd9a8', '#c8ecd2', '#f6c6c3', '#dbe4f3'][i]} />
          <rect x={x + 8} y={y + 10} width="40" height="5" rx="2.5" fill="#1c2030" opacity=".35" />
          <rect x={x + 8} y={y + 21} width="52" height="4" rx="2" fill="#fff" opacity=".8" />
        </g>
      ))}
      <rect class="c3-sel" x="42" y="20" width="76" height="56" rx="8" fill="none" stroke={BLUE} stroke-width="2.5" />
      <g class="c3-copied">
        <rect x="118" y="144" width="84" height="22" rx="11" fill="#fff" />
        <path d="M131 155l3 3 6-6" fill="none" stroke="#34c759" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" />
        <text x="146" y="159" font-size="10" fill="#1c2030" font-family={MAC}>Copied</text>
      </g>
    </svg>
  )
}

/** ⌥⇧O: a drag over text, a scan line, and plain text on the clipboard. */
function SceneText() {
  return (
    <svg viewBox="0 0 320 180" class="step-anim block w-full" aria-hidden="true">
      {/* A plain page of text, so the selected lines read as the only text. */}
      <rect x="16" y="14" width="190" height="150" rx="10" fill="#fff" stroke="#d3d9e3" />
      <TextLines x={32} y={30} widths={[90, 140]} />
      <TextLines x={32} y={118} widths={[150, 120, 80]} />
      <rect x="28" y="54" width="148" height="48" fill={BLUE} fill-opacity=".08" stroke={BLUE} stroke-width="1.5" stroke-dasharray="5 3" />
      <TextLines x={36} y={62} widths={[116, 92, 128]} color="#1c2030" />
      <rect class="c4-scan" x="28" y="54" width="148" height="2" fill={BLUE} />
      <g class="c4-clip">
        <rect x="196" y="54" width="112" height="78" rx="10" fill="#fff" stroke="#d3d9e3" />
        <text x="206" y="72" font-size="9" font-weight="600" fill="#5b6275" font-family={MAC}>Clipboard</text>
        <text x="206" y="90" font-size="10" fill="#1c2030" font-family="ui-monospace, Menlo, monospace">Order #4821</text>
        <text x="206" y="104" font-size="10" fill="#1c2030" font-family="ui-monospace, Menlo, monospace">ships Friday,</text>
        <text x="206" y="118" font-size="10" fill="#1c2030" font-family="ui-monospace, Menlo, monospace">tracking 7Q…</text>
      </g>
    </svg>
  )
}

/** The editor: a staged crop tightening, then an image dropped on top. */
function SceneEditor() {
  return (
    <svg viewBox="0 0 320 180" class="step-anim block w-full" aria-hidden="true">
      <rect x="20" y="10" width="280" height="162" rx="12" fill="#23262f" />
      <rect x="40" y="26" width="240" height="132" rx="4" fill="#fff" />
      <TextLines x={56} y={44} widths={[110, 170, 140, 160, 90]} gap={16} />
      <ellipse cx="120" cy="92" rx="40" ry="16" fill="none" stroke={RED} stroke-width="2.5" />
      <g class="c5-crop" fill="none" stroke="#fff" stroke-width="3.5" stroke-linecap="round">
        <path d="M58 52v-12h12M262 52v-12h-12M58 140v12h12M262 140v12h-12" stroke="#1c2030" stroke-width="6" stroke-opacity=".25" />
        <path d="M58 52v-12h12M262 52v-12h-12M58 140v12h12M262 140v12h-12" stroke={BLUE} />
      </g>
      <g class="c5-img">
        <rect x="190" y="96" width="70" height="46" rx="4" fill="#b3aee8" stroke="#fff" stroke-width="2" />
        <circle cx="206" cy="110" r="5" fill="#fff" opacity=".8" />
        <path d="M194 138l18-16 12 10 10-8 22 14z" fill="#fff" opacity=".7" />
      </g>
    </svg>
  )
}

/** ⌥⇧W: a blank page with a dot grid, a sketch drawing itself, a capture pasted. */
function SceneBoard() {
  const dots = []
  for (let x = 32; x <= 288; x += 16) for (let y = 22; y <= 166; y += 16) dots.push(<circle cx={x} cy={y} r="1" fill="#c9d0dc" />)
  return (
    <svg viewBox="0 0 320 180" class="step-anim block w-full" aria-hidden="true">
      <rect x="20" y="10" width="280" height="166" rx="12" fill="#fff" stroke="#d3d9e3" />
      {dots}
      <g class="c6-paste">
        <rect x="44" y="34" width="110" height="72" rx="5" fill="#23262f" />
        <rect x="50" y="40" width="98" height="60" rx="3" fill="#dbe4f3" />
        <TextLines x={58} y={50} widths={[52, 74, 60]} color="#fff" />
      </g>
      <path
        class="c6-sketch"
        pathLength="1"
        stroke-dasharray="1"
        d="M170 70c18-22 52-24 70-6 16 16 10 42-10 52-22 11-50 4-60-14M154 70h-12m4-6l-6 6 6 6"
        fill="none"
        stroke={PURPLE}
        stroke-width="3"
        stroke-linecap="round"
        stroke-linejoin="round"
      />
      <text class="c6-note" x="190" y="150" font-size="13" fill={PURPLE} font-family={MAC}>
        ship this
      </text>
    </svg>
  )
}

const cards: { scene: () => Child; keys?: string; title: string; body: Child }[] = [
  {
    scene: SceneArea,
    keys: '⇧S',
    title: 'Just the part that matters',
    body: (
      <>
        Drag an area and a magnifier shows the exact pixel edge; hold <Kbd>⇧</Kbd> for a square. <Kbd>⌥S</Kbd> takes
        only the front window.
      </>
    ),
  },
  {
    scene: ScenePin,
    title: 'Pin it above everything',
    body: 'Float a capture over your windows while you work. Scroll to resize it, ⌥-scroll to fade it, and lock it so clicks pass through.',
  },
  {
    scene: SceneHistory,
    keys: '⌥⇧I',
    title: 'Your last 50 captures',
    body: 'Arrow to an older capture and press Return to copy it again. They stay on your Mac until you clear them.',
  },
  {
    scene: SceneText,
    keys: '⌥⇧O',
    title: 'Copy the text, not a picture',
    body: 'Drag over any text or QR code and it lands on your clipboard as plain text. Recognition runs on your Mac.',
  },
  {
    scene: SceneEditor,
    title: 'Finish it in the editor',
    body: 'Open any capture to crop it, zoom in on a detail or drop another image on top. What you save is what you see.',
  },
  {
    scene: SceneBoard,
    keys: '⌥⇧W',
    title: 'A whiteboard when the screen is not enough',
    body: 'Blank pages over every app, with a dot grid to sketch on. Paste a capture onto a page and draw around it.',
  },
]

export function Captures() {
  return (
    <section id="captures" aria-labelledby="captures-title" class={`${container} scroll-mt-20 py-20 md:py-28`}>
      <div data-reveal class="max-w-[38rem]">
        <h2 id="captures-title" class={sectionTitle}>
          More than a screenshot
        </h2>
        <p class="mt-3 text-[17px] leading-relaxed text-muted">
          What happens after you press <Kbd>S</Kbd> is still a key or two away.
        </p>
      </div>
      <ul class="mt-12 grid gap-5 md:grid-cols-2 lg:grid-cols-3">
        {cards.map((card, i) => (
          <li
            data-reveal
            data-spotlight
            style={{ '--delay': `${(i % 3) * 120}ms` }}
            class="spotlight relative overflow-hidden rounded-3xl border border-white/80 bg-paper/60 shadow-glass backdrop-blur-sm"
          >
            <div class="bg-gradient-to-b from-aurora-blue/25 via-aurora-lilac/20 to-transparent px-5 pt-6">{card.scene()}</div>
            <div class="px-7 pt-2 pb-7">
              <div class="flex items-start justify-between gap-3">
                <h3 class="text-[19px] leading-snug font-bold tracking-tight">{card.title}</h3>
                {card.keys && <Kbd>{card.keys}</Kbd>}
              </div>
              <p class="mt-3 leading-relaxed text-muted">{card.body}</p>
            </div>
          </li>
        ))}
      </ul>
    </section>
  )
}
