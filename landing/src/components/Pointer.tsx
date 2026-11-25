// The pointer highlight: the app's presentation mode, tried on this page. The
// server renders the copy; client/pointer.tsx mounts the toggle, settings and
// preview into #pointer-controls and draws the ring over the real cursor.
import { container, sectionTitle } from './sections'
import { Kbd } from './ui'

export function PointerSection() {
  return (
    <section id="pointer" aria-labelledby="pointer-title" class={`${container} scroll-mt-20 py-20 md:py-28`}>
      <div data-reveal class="max-w-[38rem]">
        <h2 id="pointer-title" class={sectionTitle}>
          Presenting? Point at it
        </h2>
        <p class="mt-3 text-[17px] leading-relaxed text-muted">
          Press <Kbd>⌥⇧M</Kbd> and a highlight follows your pointer, so everyone watching your screen knows where to look.
          Clicks and focus stay with the app you're presenting. Try it right here.
        </p>
      </div>
      <div id="pointer-controls" data-reveal style={{ '--delay': '120ms' }} class="mt-10 min-h-[360px]">
        <noscript>
          <p class="text-muted">Turn on JavaScript to try the pointer highlight on this page.</p>
        </noscript>
      </div>
    </section>
  )
}
