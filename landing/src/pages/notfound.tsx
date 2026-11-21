import { HeroBackdrop } from '../components/Backdrop'
import { container, Footer, Nav } from '../components/sections'
import { Kbd } from '../components/ui'

/** The ink ring drawn around the 404, the same red the app's first ink uses. */
const RING = 'M30 92C38 30 170 8 300 18c120 9 196 50 186 104-10 58-150 86-276 76C88 188 22 150 30 92z'

export function NotFound() {
  return (
    <div class="relative isolate flex min-h-svh flex-col overflow-x-clip">
      <HeroBackdrop />
      <Nav />
      <main class={`${container} flex w-full flex-1 flex-col items-center justify-center py-20 text-center`}>
        <div data-reveal class="relative">
          <p
            aria-hidden="true"
            class="px-10 text-[clamp(7rem,22vw,12rem)] leading-none font-extrabold tracking-[-0.06em] text-graphite/90"
          >
            404
          </p>
          <svg
            aria-hidden="true"
            viewBox="0 0 516 210"
            fill="none"
            preserveAspectRatio="none"
            class="pointer-events-none absolute top-[-22%] left-[-8%] h-[144%] w-[116%] overflow-visible"
          >
            <path class="ink-draw" pathLength="1" d={RING} stroke="#ff3b30" stroke-width="7" stroke-linecap="round" />
          </svg>
        </div>
        <h1 class="mt-10 text-[clamp(2rem,4.5vw,3.25rem)] leading-[1.05] font-extrabold tracking-[-0.03em]">
          Nothing to draw on here.
        </h1>
        <p class="mt-5 max-w-[32rem] text-[clamp(1.0625rem,1.6vw,1.2rem)] leading-relaxed text-muted">
          This page doesn't exist, or it moved. Press <Kbd>Esc</Kbd> to clear and leave, like in the app.
        </p>
        <div class="mt-9 flex flex-wrap items-center justify-center gap-x-6 gap-y-4">
          <a
            href="/"
            data-esc-home
            class="inline-flex h-12 items-center rounded-full bg-graphite px-6 text-[15px] font-semibold text-paper shadow-toolbar transition-[background-color,transform] hover:-translate-y-px hover:bg-graphite/90 active:translate-y-0"
          >
            Back to Stare
          </a>
          <a href="/#try" class="text-[15px] font-semibold underline decoration-rule decoration-2 underline-offset-[6px] hover:decoration-graphite">
            Try it in your browser
          </a>
        </div>
      </main>
      <Footer />
    </div>
  )
}
