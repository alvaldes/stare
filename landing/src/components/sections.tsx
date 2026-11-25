import { releasesUrl, repoUrl, site } from '../site'
import { Aurora } from './Backdrop'
import { HeroScene } from './HeroScene'
import { DownloadButton, Kbd, Logo } from './ui'

export const container = 'mx-auto max-w-[1240px] px-4 md:px-8'
export const sectionTitle = 'text-[clamp(1.75rem,3.2vw,2.5rem)] leading-[1.1] font-bold tracking-[-0.02em]'

export function Nav() {
  return (
    // Same container as the page content, so the pill's edges line up with it.
    // w-full keeps it at max-width when a page lays it out as a flex item.
    <header class={`${container} sticky top-3 z-50 w-full`}>
      <nav
        aria-label="Main"
        class="flex h-14 items-center gap-6 rounded-full border border-white/70 bg-paper/55 pr-2 pl-5 shadow-glass backdrop-blur-xl backdrop-saturate-150"
      >
        {/* flex, not inline: an inline link adds the text line's descender
            space and pushes the icon off the pill's vertical centre. */}
        <a href="/" aria-label="Stare home" class="flex items-center">
          <Logo />
        </a>
        <div class="ml-auto hidden items-center gap-1 text-[15px] text-muted sm:flex">
          {[
            ['/#try', 'Try it'],
            ['/#shortcuts', 'Shortcuts'],
            ['/#faq', 'FAQ'],
            [repoUrl, 'GitHub'],
          ].map(([href, label]) => (
            <a href={href} class="rounded-full px-3 py-1.5 transition-colors hover:bg-graphite/6 hover:text-graphite">
              {label}
            </a>
          ))}
        </div>
        <a
          href="/#download"
          class="ml-auto inline-flex h-10 items-center rounded-full bg-graphite px-4 text-[14px] font-semibold text-paper transition-colors hover:bg-graphite/90 sm:ml-0"
        >
          Download
        </a>
      </nav>
    </header>
  )
}

const headline = ['Draw', 'on', 'your', 'screen,', 'then', 'paste', 'it', 'anywhere.']

export function Hero() {
  return (
    <section class={`${container} relative flex items-center gap-10 pt-14 pb-12 md:pt-20 md:pb-24`}>
      <div class="min-w-0 flex-1">
      <h1
        aria-label={headline.join(' ')}
        class="max-w-[15ch] text-[clamp(2.6rem,6.2vw,5.25rem)] lg:text-[clamp(3.25rem,4.6vw,4.5rem)] leading-[0.98] font-extrabold tracking-[-0.035em]"
      >
        {headline.map((word, i) => (
          <span aria-hidden="true" class="inline-block motion-safe:animate-blur-in" style={{ animationDelay: `${80 + i * 70}ms` }}>
            {word}
            {i < headline.length - 1 ? ' ' : ''}
          </span>
        ))}
      </h1>
      <p
        class="mt-7 max-w-[36rem] text-[clamp(1.0625rem,1.6vw,1.25rem)] leading-relaxed text-muted motion-safe:animate-blur-in"
        style={{ animationDelay: '650ms' }}
      >
        Stare is an open-source menu bar app for macOS. Press <Kbd>⌥⇧A</Kbd> to draw over any app, press <Kbd>S</Kbd>{' '}
        to capture the screen with your marks, and paste the image into a chat, an issue or a doc.
      </p>
      <div class="mt-9 flex flex-wrap items-center gap-x-6 gap-y-4 motion-safe:animate-blur-in" style={{ animationDelay: '780ms' }}>
        <DownloadButton />
        <a href="#try" class="text-[15px] font-semibold underline decoration-rule decoration-2 underline-offset-[6px] hover:decoration-graphite">
          Try it in your browser
        </a>
      </div>
      <p class="mt-5 text-[14px] text-muted motion-safe:animate-blur-in" style={{ animationDelay: "900ms" }}>
        Requires {site.minimumMacOS} or later.
      </p>
      </div>

      <HeroScene />

      {/* Between tablet and desktop there is no room for the scene: an ink
          arrow draws itself toward the demo instead. */}
      <svg
        aria-hidden="true"
        viewBox="0 0 300 260"
        class="pointer-events-none absolute right-[6%] bottom-[-5.5rem] hidden w-[min(26vw,300px)] md:block lg:hidden"
        fill="none"
        stroke="var(--color-ink-red)"
        stroke-width="4"
        stroke-linecap="round"
        stroke-linejoin="round"
      >
        <path
          d="M28 34c62-26 150-22 196 28 34 37 30 97 4 160"
          pathLength="1"
          stroke-dasharray="1"
          class="motion-safe:animate-draw-in"
        />
        <path d="M206 204l22 22 18-28" class="origin-[228px_224px] motion-safe:animate-pop-in" />
      </svg>
    </section>
  )
}

// Each claim is backed elsewhere: menu bar app (LSUIElement), no sign-in
// anywhere in the app, captures stay local (see FAQ), source on GitHub.
const guarantees = [
  { label: 'Lives in the menu bar', icon: 'M3 5.5h18M6.5 3v2.5M17.5 3v2.5M4.5 5.5h15v14h-15z' },
  { label: 'No account to create', icon: 'M12 12a4 4 0 1 0 0-8 4 4 0 0 0 0 8zM4.5 20.5c1.3-3.6 4.1-5.5 7.5-5.5s6.2 1.9 7.5 5.5' },
  { label: 'Captures stay on your Mac', icon: 'M6.5 10V7.5a5.5 5.5 0 0 1 11 0V10M5 10h14v10.5H5zM12 14v3' },
  { label: 'Open source', icon: 'M8.5 7.5L4 12l4.5 4.5M15.5 7.5L20 12l-4.5 4.5M13.5 5l-3 14' },
]

export function Download() {
  return (
    <section id="download" aria-labelledby="download-title" class="scroll-mt-20 px-4 md:px-8">
      <div
        data-reveal
        class="relative isolate mx-auto max-w-[1240px] overflow-hidden rounded-[28px] bg-graphite px-6 py-16 text-paper md:px-16 md:py-24"
      >
        <Aurora tone="dark" />
        <div aria-hidden="true" class="grain pointer-events-none absolute inset-0 -z-10 opacity-[0.35] mix-blend-overlay" />
        <h2 id="download-title" class="relative max-w-[14ch] text-[clamp(2.25rem,5vw,4rem)] leading-[1.02] font-extrabold tracking-[-0.03em]">
          Point at things. Then show them.
          <svg
            aria-hidden="true"
            viewBox="0 0 400 24"
            preserveAspectRatio="none"
            class="mt-2 block h-[0.35em] w-[min(100%,9.5em)]"
            fill="none"
            stroke="var(--color-ink-red)"
            stroke-width="5"
            stroke-linecap="round"
          >
            <path class="ink-draw" pathLength="1" d="M4 15c70-9 150-12 230-8 54 3 108 6 162 1" />
          </svg>
        </h2>
        <p class="relative mt-5 max-w-[34rem] text-[17px] leading-relaxed text-paper/70">
          Stare runs on {site.minimumMacOS} or later. It is open source, so you can also read the code and build it
          yourself.
        </p>
        <div class="relative mt-9 flex flex-wrap items-center gap-x-6 gap-y-4">
          <DownloadButton tone="light" />
          <a href={repoUrl} class="text-[15px] font-semibold underline decoration-paper/30 decoration-2 underline-offset-[6px] hover:decoration-paper">
            View the source
          </a>
        </div>
        <p data-download-version class="relative mt-5 text-[14px] text-paper/60" />

        {/* What you can count on, said where the install decision happens. */}
        <ul aria-label="What to expect" class="relative mt-12 grid gap-x-8 gap-y-4 border-t border-paper/15 pt-8 text-[15px] text-paper/80 sm:grid-cols-2 lg:grid-cols-4">
          {guarantees.map((item) => (
            <li class="flex items-center gap-3">
              <svg aria-hidden="true" viewBox="0 0 24 24" width="20" height="20" class="shrink-0 text-ink-sky" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round">
                <path d={item.icon} />
              </svg>
              {item.label}
            </li>
          ))}
        </ul>
      </div>
    </section>
  )
}

const faqs = [
  {
    q: 'What does Stare need from my Mac?',
    a: `${site.minimumMacOS} or later. Drawing works without any permission. To capture the screen or read text from it, Stare needs the Screen Recording permission, which you allow once in System Settings.`,
  },
  {
    q: 'How is it different from a screenshot tool?',
    a: 'You mark up the live screen first and capture second, so pointing at something takes a couple of key presses. When you do want an editor, any capture opens in one to crop it, zoom in on a detail or drop another image on top.',
  },
  {
    q: 'Does drawing take focus away from the app I am using?',
    a: 'No. The app underneath stays active, so you can draw over it and keep working in it.',
  },
  {
    q: 'Where do my captures go?',
    a: 'Each capture appears as a card in the corner of the screen. Copy it, save it, drag it into another app, or pin it above your windows. Your last 50 captures stay in a history on your Mac (⌥⇧I), or you can save straight to a folder with your own file names. Stare does not upload anything.',
  },
  {
    q: 'Can it copy the text on my screen?',
    a: 'Yes. Press ⌥⇧O and drag over any text or QR code, and it lands on your clipboard as plain text. Recognition runs on your Mac, so nothing is uploaded.',
  },
  {
    q: 'Can I try it before installing?',
    a: 'Yes. The demo on this page uses the drawing tools, inks and keys of the app. Moving marks, the capture editor and the whiteboard are only in the app.',
  },
]

export function Faq() {
  return (
    <section id="faq" aria-labelledby="faq-title" class={`${container} scroll-mt-20 py-20 md:py-28`}>
      <div class="grid gap-10 md:grid-cols-[1fr_2fr]">
        <h2 id="faq-title" data-reveal class={sectionTitle}>
          Questions
        </h2>
        <div data-reveal style={{ '--delay': '120ms' }} class="border-t border-rule">
          {faqs.map((item) => (
            <details class="group border-b border-rule">
              <summary class="flex cursor-pointer list-none items-center justify-between gap-6 py-5 text-[17px] font-semibold transition-colors hover:text-ink-blue [&::-webkit-details-marker]:hidden">
                {item.q}
                <span aria-hidden="true" class="text-[22px] leading-none font-normal text-muted transition-transform duration-300 group-open:rotate-45">
                  +
                </span>
              </summary>
              <p class="max-w-[60ch] pb-6 leading-relaxed text-muted">{item.a}</p>
            </details>
          ))}
        </div>
      </div>
    </section>
  )
}

export function Footer() {
  return (
    <footer class={`${container} relative w-full pt-10 pb-12`}>
      <div class="flex flex-wrap items-center gap-x-6 gap-y-3 border-t border-rule pt-8 text-[14px] text-muted">
        <Logo />
        <span>Open source, made for macOS.</span>
        <div class="flex gap-6 sm:ml-auto">
          <a href={repoUrl} class="hover:text-graphite">GitHub</a>
          <a href={releasesUrl} class="hover:text-graphite">Releases</a>
          <a href={`${repoUrl}/issues`} class="hover:text-graphite">Report an issue</a>
        </div>
      </div>
      <p
        aria-hidden="true"
        data-reveal
        class="mt-10 bg-gradient-to-b from-graphite/12 to-graphite/0 bg-clip-text text-[clamp(5rem,24vw,20rem)] leading-[0.8] font-extrabold tracking-[-0.05em] text-transparent select-none"
      >
        Stare
      </p>
    </footer>
  )
}
