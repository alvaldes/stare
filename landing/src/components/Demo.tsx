import { SCREEN_HEIGHT, SCREEN_WIDTH } from '../demo/model'
import { BROWSER_VIEWPORT, DemoScreen, PORTFOLIO_HOST, PORTFOLIO_URL } from './DemoScreen'
import { CreatorNote } from './CreatorNote'
import { Kbd } from './ui'

/** The portfolio lays out at a laptop width, then scales down to fit. */
export const PAGE_WIDTH = 1280
const PAGE_HEIGHT = Math.round((PAGE_WIDTH * BROWSER_VIEWPORT.height) / BROWSER_VIEWPORT.width)

const pct = (value: number, of: number) => `${((value / of) * 100).toFixed(4)}%`

/**
 * The creator's portfolio, live, always in its dark theme, kept as light as
 * that allows:
 * - sandbox="allow-scripts" and nothing else: the site's theme script may run,
 *   but there are no cookies, storage, forms or popups.
 * - color-scheme: dark on the iframe makes the page see
 *   prefers-color-scheme: dark; with no saved preference (no storage in the
 *   sandbox) its theme script picks dark. Verified in Chromium.
 * - Lazy-loaded, no referrer, and inert so it never takes the pointer or
 *   keyboard from the drawing layer above it.
 * client/browser.ts scales it to the window; until then it shows top-left.
 */
function LivePage() {
  const v = BROWSER_VIEWPORT
  return (
    <div
      class="pointer-events-none absolute overflow-hidden"
      style={{
        left: pct(v.x, SCREEN_WIDTH),
        top: pct(v.y, SCREEN_HEIGHT),
        width: pct(v.width, SCREEN_WIDTH),
        height: pct(v.height, SCREEN_HEIGHT),
        borderRadius: `0 0 ${pct(v.radius, v.width)} ${pct(v.radius, v.width)} / 0 0 ${pct(v.radius, v.height)} ${pct(v.radius, v.height)}`,
      }}
    >
      <iframe
        id="demo-page"
        src={PORTFOLIO_URL}
        title={`${PORTFOLIO_HOST}, shown inside the pretend Safari window`}
        loading="lazy"
        sandbox="allow-scripts"
        referrerpolicy="no-referrer"
        tabindex={-1}
        inert
        width={PAGE_WIDTH}
        height={PAGE_HEIGHT}
        class="block origin-top-left border-0 bg-graphite scheme-dark"
      />
    </div>
  )
}

/**
 * The try-it section. The server renders the screen and an empty layer; the
 * client mounts the toolbar, drawing and capture cards on top of it.
 */
export function Demo() {
  return (
    <section id="try" aria-labelledby="try-title" class="relative mx-auto max-w-[1240px] scroll-mt-20 px-4 pt-6 pb-24 md:px-8">
      <div data-reveal class="mb-8 max-w-[38rem]">
        <h2 id="try-title" class="text-[clamp(1.75rem,3.2vw,2.5rem)] leading-[1.1] font-bold tracking-[-0.02em]">
          Try it on this pretend Mac
        </h2>
        <p class="mt-3 text-[17px] leading-relaxed text-muted">
          Draw with your mouse, trackpad or finger. Switch tools from the toolbar or with the same keys as the app, then
          press <Kbd>S</Kbd> to capture the screen with your marks.
        </p>
      </div>

      <div id="demo" tabindex={-1} class="group/demo relative outline-none">
        <div class="relative aspect-[5/3] overflow-hidden rounded-[clamp(10px,1.6vw,18px)] bg-graphite shadow-window ring-1 ring-graphite/10">
          <DemoScreen />
          <LivePage />
          <canvas
            id="demo-ink"
            aria-label="Drawing surface. Use the toolbar or keyboard shortcuts to mark up the screen."
            class="absolute inset-0 h-full w-full cursor-crosshair touch-none"
          />
          <p class="pointer-events-none absolute inset-x-0 bottom-[6%] mx-auto w-max rounded-full bg-chrome/80 px-4 py-2 font-mac text-[13px] text-white backdrop-blur-md transition-opacity duration-300 group-data-drawn/demo:opacity-0">
            Draw anywhere on this screen
          </p>
          <div id="demo-flash" aria-hidden="true" class="pointer-events-none absolute inset-0 bg-white opacity-0" />
        </div>
        <div id="demo-ui" class="md:pointer-events-none md:absolute md:inset-0" />
        <noscript>
          <p class="mt-4 text-muted">The demo needs JavaScript. Everything else on this page works without it.</p>
        </noscript>
      </div>

      <CreatorNote />

      <ul class="mt-6 flex flex-wrap [@media(hover:none)]:hidden gap-x-6 gap-y-3 text-[14px] text-muted" aria-label="Demo shortcuts">
        <li>
          <Kbd>P</Kbd> <Kbd>H</Kbd> <Kbd>A</Kbd> <Kbd>L</Kbd> <Kbd>R</Kbd> <Kbd>O</Kbd> <Kbd>C</Kbd> pick a tool
        </li>
        <li>
          <Kbd>1</Kbd>–<Kbd>8</Kbd> change ink
        </li>
        <li>
          <Kbd>⌘Z</Kbd> undo
        </li>
        <li>
          <Kbd>Esc</Kbd> clear
        </li>
        <li>
          <Kbd>S</Kbd> capture
        </li>
      </ul>
    </section>
  )
}
