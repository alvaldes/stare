// The hero's illustration: a short loop that acts out the headline. A cursor
// circles a button in red ink, S captures it, the card says Copied and the
// image lands in a chat. Pure CSS animation (see .scene-* in style.css).
// Every element's resting state is its visible one; animations only hide
// parts of the loop, so with reduced motion the scene shows complete and still.

/** The ink ellipse around the button; the cursor follows the same path. */
const RING = 'M205 207a84 33 0 1 0 168 0a84 33 0 1 0-168 0'

function WindowSketch() {
  return (
    <>
      <rect width="380" height="230" rx="14" fill="#fff" />
      <path d="M0 14a14 14 0 0 1 14-14h352a14 14 0 0 1 14 14v18H0z" fill="#f5f6f9" />
      <circle cx="18" cy="16" r="5" fill="#ff5f57" />
      <circle cx="34" cy="16" r="5" fill="#febc2e" />
      <circle cx="50" cy="16" r="5" fill="#28c840" />
      <rect x="22" y="52" width="170" height="11" rx="5.5" fill="#1c2030" opacity=".85" />
      <rect x="22" y="74" width="230" height="7" rx="3.5" fill="#c9d0dc" />
      <rect x="22" y="88" width="190" height="7" rx="3.5" fill="#c9d0dc" />
      <rect x="22" y="112" width="150" height="88" rx="8" fill="#dbe4f3" />
      <path d="M22 182l40-34 30 24 26-18 54 46v-2a8 8 0 0 1-8 8H30a8 8 0 0 1-8-8z" fill="#b6c6e6" />
      <rect x="210" y="180" width="118" height="34" rx="9" fill="#007aff" />
      <text x="269" y="202" font-size="13" font-weight="600" fill="#fff" text-anchor="middle" font-family="-apple-system, BlinkMacSystemFont, sans-serif">
        Publi
      </text>
    </>
  )
}

/** The captured image: the window with the ring, as shown in the card and chat. */
function Thumbnail({ class: className }: { class: string }) {
  return (
    <svg viewBox="-10 -10 400 250" class={className} aria-hidden="true">
      <rect x="-10" y="-10" width="400" height="250" fill="#b3aee8" />
      <WindowSketch />
      <path d={RING} transform="translate(-20 -10)" fill="none" stroke="#ff3b30" stroke-width="5" />
    </svg>
  )
}

export function HeroScene() {
  return (
    <div aria-hidden="true" class="hero-scene relative hidden h-[440px] w-[480px] shrink-0 lg:block">
      {/* The window being marked up */}
      <div class="absolute top-2.5 left-5 rounded-[14px] shadow-window">
        <svg width="380" height="230" viewBox="0 0 380 230" class="block overflow-visible">
          <WindowSketch />
          <path
            d={RING}
            transform="translate(-20 -10)"
            pathLength="1"
            stroke-dasharray="1"
            class="scene-ink"
            fill="none"
            stroke="#ff3b30"
            stroke-width="4"
            stroke-linecap="round"
          />
        </svg>
        <div class="scene-flash absolute inset-0 rounded-[14px] bg-white" />
      </div>

      {/* Cursor tracing the ring */}
      <svg width="18" height="24" viewBox="0 0 18 24" class="scene-cursor absolute top-0 left-0" style={{ offsetPath: `path('${RING}')` }}>
        <path d="M2 2l13 12.5-6.2.6 3.6 7.2-2.8 1.3-3.5-7.2L2 21z" fill="#1c2030" stroke="#fff" stroke-width="1.5" stroke-linejoin="round" />
      </svg>

      {/* The S key, pressed */}
      <kbd class="scene-key absolute top-[200px] left-[-14px] grid size-11 place-items-center rounded-xl border border-b-[3px] border-rule bg-paper font-mac text-[18px] font-semibold text-graphite shadow-toolbar">
        S
      </kbd>

      {/* Capture card */}
      <div class="scene-card absolute top-[262px] left-[44px] w-[170px] overflow-hidden rounded-xl border border-white/12 bg-chrome/90 font-mac text-white shadow-card backdrop-blur-xl">
        <Thumbnail class="block aspect-[400/250] w-full" />
        <div class="flex items-center justify-center gap-1.5 py-2 text-[12px]">
          <span class="scene-copied inline-flex items-center gap-1.5">
            <svg viewBox="0 0 24 24" width="13" height="13" fill="none" stroke="#34c759" stroke-width="2.6" stroke-linecap="round" stroke-linejoin="round">
              <path d="M5 12.5l4.5 4.5L19 7.5" />
            </svg>
            Copied
          </span>
        </div>
      </div>

      {/* Pasted into a chat */}
      <div class="scene-chat absolute top-[250px] left-[236px] w-[236px] rounded-2xl rounded-bl-md border border-white/80 bg-paper/85 p-3 font-mac shadow-glass backdrop-blur-xl">
        <div class="flex items-center gap-2">
          <span class="grid size-7 place-items-center rounded-full bg-ink-purple text-[11px] font-semibold text-white">MK</span>
          <span class="text-[13px] font-semibold text-graphite">Maya</span>
          <span class="ml-auto text-[11px] text-muted">9:42</span>
        </div>
        <p class="mt-2 text-[13px] leading-snug text-graphite">The button label gets cut off here</p>
        <Thumbnail class="scene-paste mt-2 block aspect-[400/250] w-full rounded-lg" />
      </div>
    </div>
  )
}
