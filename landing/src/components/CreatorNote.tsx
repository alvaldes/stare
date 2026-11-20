// The creator "marks up" his own URL with Stare: a red ring around the domain
// in the demo's Safari bar, a stroke out of the pretend Mac, and a comment
// bubble that types itself and links to the portfolio. The ring and stroke are
// drawn by client/creatorNote.ts, which measures where the URL sits; the
// bubble is a plain link, so it works without JavaScript.
import { PORTFOLIO_HOST, PORTFOLIO_URL } from './DemoScreen'

// No "up there" / "down there": the note sits above the demo on desktop and
// below it on phones, so a direction would be wrong on one of them.
export const CREATOR_MESSAGE = "I built Stare, and that's my site in the Safari window. Come say hi!"

export function CreatorNote() {
  return (
    <>
      {/* Ring and connector, laid over the whole section on wide screens. */}
      <svg
        id="creator-ink"
        aria-hidden="true"
        class="pointer-events-none absolute inset-0 z-20 hidden h-full w-full overflow-visible lg:block"
        fill="none"
        stroke="var(--color-ink-red)"
        stroke-linecap="round"
        stroke-linejoin="round"
      >
        <path id="creator-ring" pathLength="1" stroke-dasharray="1" stroke-dashoffset="1" stroke-width="3" />
        <path id="creator-line" pathLength="1" stroke-dasharray="1" stroke-dashoffset="1" stroke-width="3" />
      </svg>

      <a
        id="creator-note"
        href={PORTFOLIO_URL}
        target="_blank"
        rel="noopener"
        aria-label={`${CREATOR_MESSAGE} Visit ${PORTFOLIO_HOST}, opens in a new tab`}
        class="group/note relative z-30 mt-6 flex w-full max-w-[340px] flex-col gap-3 rounded-3xl rounded-bl-md border border-white/80 bg-paper/80 p-4 font-mac shadow-glass backdrop-blur-xl transition-transform hover:-translate-y-0.5 lg:absolute lg:top-4 lg:right-8 lg:mt-0"
      >
        <span class="flex items-center gap-3">
          {/* Cropped from the portfolio's own photo (portfolio/src/assets/images/angel.webp). */}
          <img
            src="/creator.jpg"
            alt=""
            width="40"
            height="40"
            loading="lazy"
            class="size-10 shrink-0 rounded-full object-cover ring-2 ring-white"
          />
          <span class="flex flex-col">
            <span class="text-[14px] font-semibold text-graphite">Angel Valdés</span>
            <span class="text-[12px] text-muted">Software Engineer</span>
          </span>
          <span class="ml-auto text-[11px] text-muted">now</span>
        </span>
        {/* The full text is here for no-JS and screen readers; the client
            retypes it letter by letter when the note appears. */}
        <span id="creator-text" class="min-h-[2.6em] text-[15px] leading-snug text-graphite">
          {CREATOR_MESSAGE}
        </span>
        <span class="inline-flex items-center gap-1.5 self-start rounded-full bg-graphite px-3 py-1.5 text-[13px] font-semibold text-paper transition-colors group-hover/note:bg-ink-blue">
          Visit {PORTFOLIO_HOST}
          <svg aria-hidden="true" viewBox="0 0 24 24" width="13" height="13" fill="none" stroke="currentColor" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round">
            <path d="M7 17L17 7M9 7h8v8" />
          </svg>
        </span>
      </a>
    </>
  )
}
