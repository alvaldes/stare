// "How it works" as three animated cards, one per key press. Each card holds a
// small SVG scene looping in CSS (.s1-*, .s2-*, .s3-* in style.css). Scenes
// rest on their complete, visible state and only play once revealed.
import type { Child } from 'hono/jsx'
import { container, sectionTitle } from './sections'

export const MAC = "-apple-system, BlinkMacSystemFont, 'Helvetica Neue', Arial, sans-serif"

export function MiniWindow({ x, y, width, height }: { x: number; y: number; width: number; height: number }) {
  return (
    <g>
      <rect x={x} y={y} width={width} height={height} rx="10" fill="#fff" stroke="#d3d9e3" />
      <circle cx={x + 12} cy={y + 11} r="3" fill="#ff5f57" />
      <circle cx={x + 22} cy={y + 11} r="3" fill="#febc2e" />
      <circle cx={x + 32} cy={y + 11} r="3" fill="#28c840" />
      <rect x={x + 16} y={y + 30} width={width * 0.45} height="7" rx="3.5" fill="#1c2030" opacity=".8" />
      <rect x={x + 16} y={y + 46} width={width * 0.7} height="5" rx="2.5" fill="#c9d0dc" />
      <rect x={x + 16} y={y + 58} width={width * 0.6} height="5" rx="2.5" fill="#c9d0dc" />
      <rect x={x + 16} y={y + 76} width={width * 0.34} height={height - 92} rx="6" fill="#dbe4f3" />
      <rect x={x + width * 0.5} y={y + 80} width={width * 0.38} height="5" rx="2.5" fill="#c9d0dc" />
      <rect x={x + width * 0.5} y={y + 92} width={width * 0.3} height="5" rx="2.5" fill="#c9d0dc" />
    </g>
  )
}

function Keycap({ x, y, label, size = 38, class: className }: { x: number; y: number; label: string; size?: number; class: string }) {
  return (
    <g class={className}>
      <rect x={x} y={y + 3} width={size} height={size} rx="9" fill="#c9d0dc" />
      <rect x={x} y={y} width={size} height={size} rx="9" fill="#fff" stroke="#d3d9e3" />
      <text x={x + size / 2} y={y + size / 2 + 6} font-size="17" font-weight="600" fill="#1c2030" text-anchor="middle" font-family={MAC}>
        {label}
      </text>
    </g>
  )
}

function SceneStart() {
  return (
    <svg viewBox="0 0 320 210" class="step-anim block w-full" aria-hidden="true">
      <MiniWindow x={40} y={14} width={240} height={140} />
      {/* The drawing sheet that ⌥⇧A lays over the screen */}
      <rect class="s1-sheet" x="30" y="6" width="260" height="156" rx="14" fill="#007aff" fill-opacity=".07" stroke="#007aff" stroke-opacity=".55" stroke-dasharray="5 4" />
      <g class="s1-bar">
        <rect x="104" y="22" width="112" height="18" rx="9" fill="#23262f" />
        {['#ff3b30', '#ff9500', '#ffcc00', '#34c759', '#007aff', '#b052de'].map((color, i) => (
          <circle cx={120 + i * 16} cy="31" r="4" fill={color} />
        ))}
      </g>
      <Keycap x={95} y={160} label="⌥" class="s1-key s1-k1" />
      <Keycap x={141} y={160} label="⇧" class="s1-key s1-k2" />
      <Keycap x={187} y={160} label="A" class="s1-key s1-k3" />
    </svg>
  )
}

function SceneMarkUp() {
  return (
    <svg viewBox="0 0 320 210" class="step-anim block w-full" aria-hidden="true">
      <MiniWindow x={30} y={20} width={260} height={170} />
      <rect class="s2-hl" x="44" y="45" width="122" height="11" rx="2" fill="#ffcc00" fill-opacity=".45" />
      <path class="s2-arrow" pathLength="1" stroke-dasharray="1" d="M262 176L196 120M196 120l4 14M196 120l14 3" fill="none" stroke="#ff3b30" stroke-width="3" stroke-linecap="round" stroke-linejoin="round" />
      <ellipse class="s2-ring" pathLength="1" stroke-dasharray="1" cx="73" cy="139" rx="40" ry="44" fill="none" stroke="#ff3b30" stroke-width="3" />
      <g class="s2-b1">
        <circle cx="178" cy="98" r="10" fill="#007aff" />
        <text x="178" y="102" font-size="11" font-weight="700" fill="#fff" text-anchor="middle" font-family={MAC}>1</text>
      </g>
      <g class="s2-b2">
        <circle cx="120" cy="128" r="10" fill="#007aff" />
        <text x="120" y="132" font-size="11" font-weight="700" fill="#fff" text-anchor="middle" font-family={MAC}>2</text>
      </g>
    </svg>
  )
}

function SceneCapture() {
  return (
    <svg viewBox="0 0 320 210" class="step-anim block w-full" aria-hidden="true">
      <g>
        <MiniWindow x={16} y={12} width={190} height={120} />
        <ellipse cx="74" cy="110" rx="34" ry="16" fill="none" stroke="#ff3b30" stroke-width="2.5" />
        <rect class="s3-flash" x="16" y="12" width="190" height="120" rx="10" fill="#fff" />
      </g>
      <Keycap x={22} y={150} label="S" class="s3-key" />
      {/* Capture card */}
      <g class="s3-card">
        <rect x="88" y="104" width="118" height="92" rx="10" fill="#23262f" />
        <rect x="96" y="112" width="102" height="56" rx="5" fill="#b3aee8" />
        <rect x="102" y="117" width="90" height="46" rx="4" fill="#fff" />
        <ellipse cx="128" cy="150" rx="15" ry="7" fill="none" stroke="#ff3b30" stroke-width="1.6" />
        <g class="s3-copied">
          <path d="M126 182l3 3 6-6" fill="none" stroke="#34c759" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" />
          <text x="140" y="186" font-size="10" fill="#fff" font-family={MAC}>Copied</text>
        </g>
      </g>
      {/* Chat bubble receiving the paste */}
      <g class="s3-chat">
        <rect x="186" y="20" width="122" height="104" rx="12" fill="#fff" stroke="#d3d9e3" />
        <circle cx="200" cy="36" r="7" fill="#b052de" />
        <rect x="212" y="32" width="40" height="7" rx="3.5" fill="#1c2030" opacity=".8" />
        <rect x="196" y="50" width="92" height="5" rx="2.5" fill="#c9d0dc" />
        <g class="s3-img">
          <rect x="196" y="62" width="102" height="52" rx="6" fill="#b3aee8" />
          <rect x="201" y="66" width="92" height="44" rx="4" fill="#fff" />
          <ellipse cx="228" cy="97" rx="15" ry="7" fill="none" stroke="#ff3b30" stroke-width="1.6" />
        </g>
      </g>
    </svg>
  )
}

const steps: { scene: () => Child; title: string; body: string }[] = [
  {
    scene: SceneStart,
    title: 'Press ⌥⇧A',
    body: 'A clear sheet covers your screen, even full-screen apps. The app underneath keeps focus.',
  },
  {
    scene: SceneMarkUp,
    title: 'Mark it up',
    body: 'Arrows, highlights, boxes, numbered steps, a blur and a spotlight, in eight inks. Every tool is one key.',
  },
  {
    scene: SceneCapture,
    title: 'Press S, then paste',
    body: 'Your screen and your marks land on a card in the corner. Copy it, save it or drag it out. ⇧S takes just an area, ⌥S one window.',
  },
]

export function Steps() {
  return (
    <section aria-labelledby="how-title" class={`${container} py-20 md:py-28`}>
      <div data-reveal class="max-w-[36rem]">
        <h2 id="how-title" class={sectionTitle}>
          Three keys, start to finish
        </h2>
        <p class="mt-3 text-[17px] leading-relaxed text-muted">From "look at this" to an image in someone's chat, without leaving your keyboard.</p>
      </div>
      <ol class="mt-12 grid gap-5 md:grid-cols-3">
        {steps.map((step, i) => (
          <li
            data-reveal
            data-spotlight
            style={{ '--delay': `${i * 140}ms` }}
            class="spotlight relative overflow-hidden rounded-3xl border border-white/80 bg-paper/60 shadow-glass backdrop-blur-sm"
          >
            <div class="bg-gradient-to-b from-aurora-blue/25 via-aurora-lilac/20 to-transparent px-5 pt-6">{step.scene()}</div>
            <div class="px-7 pt-2 pb-7">
              <div class="flex items-center gap-3">
                <span
                  aria-hidden="true"
                  class="grid size-[26px] place-items-center rounded-full bg-ink-red font-mac text-[14px] font-semibold text-white shadow-[0_1px_4px_rgb(0_0_0/0.18)]"
                >
                  {i + 1}
                </span>
                <h3 class="text-[20px] font-bold tracking-tight">{step.title}</h3>
              </div>
              <p class="mt-3 leading-relaxed text-muted">{step.body}</p>
            </div>
          </li>
        ))}
      </ol>
    </section>
  )
}
