import { INKS, TOOLS } from '../demo/model'
import { releasesUrl, repoUrl, site } from '../site'
import { Aurora } from './Backdrop'
import { HeroScene } from './HeroScene'
import { DownloadButton, Kbd, Logo } from './ui'

const container = 'mx-auto max-w-[1240px] px-4 md:px-8'
const sectionTitle = 'text-[clamp(1.75rem,3.2vw,2.5rem)] leading-[1.1] font-bold tracking-[-0.02em]'

export function Nav() {
  return (
    // Same container as the page content, so the pill's edges line up with it.
    <header class={`${container} sticky top-3 z-30`}>
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
            ['#try', 'Try it'],
            ['#shortcuts', 'Shortcuts'],
            ['#faq', 'FAQ'],
            [repoUrl, 'GitHub'],
          ].map(([href, label]) => (
            <a href={href} class="rounded-full px-3 py-1.5 transition-colors hover:bg-graphite/6 hover:text-graphite">
              {label}
            </a>
          ))}
        </div>
        <a
          href="#download"
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
    <section class={`${container} relative flex items-center gap-10 pt-14 pb-12 md:pt-20 md:pb-16`}>
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
      <p class="mt-5 text-[14px] text-muted">Requires {site.minimumMacOS} or later.</p>
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

const steps = [
  {
    title: 'Press ⌥⇧A',
    body: 'A clear sheet covers every display, even full-screen apps. The app underneath keeps focus, so you can keep working.',
  },
  {
    title: 'Mark it up',
    body: 'Pen, highlighter, arrows, lines, boxes, ellipses and numbered steps, in eight inks. Each tool is a single key.',
  },
  {
    title: 'Press S, then paste',
    body: 'Stare captures the screen with your marks and drops it on a card in the corner. Copy it, save it or drag it out.',
  },
]

export function Steps() {
  return (
    <section aria-labelledby="how-title" class={`${container} py-20 md:py-28`}>
      <h2 id="how-title" data-reveal class={sectionTitle}>
        How it works
      </h2>
      <ol class="mt-10 grid gap-10 md:grid-cols-3 md:gap-8">
        {steps.map((step, i) => (
          <li data-reveal style={{ '--delay': `${i * 140}ms` }} class="relative pt-6">
            <span aria-hidden="true" class="rule-draw absolute inset-x-0 top-0 h-0.5 bg-graphite" />
            <span
              aria-hidden="true"
              class="grid size-[26px] place-items-center rounded-full bg-ink-red font-mac text-[14px] font-semibold text-white shadow-[0_1px_4px_rgb(0_0_0/0.18)]"
            >
              {i + 1}
            </span>
            <h3 class="mt-5 text-[20px] font-bold tracking-tight">{step.title}</h3>
            <p class="mt-2 max-w-[34ch] leading-relaxed text-muted">{step.body}</p>
          </li>
        ))}
      </ol>
    </section>
  )
}

const actions = [
  { keys: '⌥⇧A', what: 'Start drawing over any app' },
  { keys: 'S', what: 'Capture the whole screen with your marks' },
  { keys: '⇧S', what: 'Capture an area you select' },
  { keys: '⌘Z', what: 'Undo the last mark' },
  { keys: 'Esc', what: 'Clear every mark and stop drawing' },
]

export function Shortcuts() {
  return (
    <section id="shortcuts" aria-labelledby="shortcuts-title" class="relative scroll-mt-20 overflow-hidden bg-paper">
      <div aria-hidden="true" class="bg-dots pointer-events-none absolute inset-0 opacity-70" />
      <div class={`${container} relative py-20 md:py-28`}>
        <div data-reveal>
          <h2 id="shortcuts-title" class={sectionTitle}>
            Every tool is one key away
          </h2>
          <p class="mt-3 max-w-[36rem] text-[17px] leading-relaxed text-muted">
            While you draw, single keys switch tools and inks. Go ahead and press one: the list below answers.
          </p>
        </div>

        <div class="mt-12 grid gap-12 md:grid-cols-[1.1fr_1fr_1.3fr] md:gap-10">
          <ShortcutList title="Tools" delay={0} rows={TOOLS.map((t) => ({ keys: t.key, what: t.name }))} />
          <div data-reveal style={{ '--delay': '120ms' }}>
            <h3 class="border-b border-rule pb-3 text-[15px] font-semibold">Inks</h3>
            <ul class="mt-1">
              {INKS.map((ink) => (
                <li data-key={ink.key} class="-mx-2 flex items-center gap-3 rounded-md border-b border-rule/60 px-2 py-2.5 text-[15px]">
                  <Kbd>{ink.key}</Kbd>
                  <span
                    aria-hidden="true"
                    class="size-3.5 rounded-full ring-1 ring-graphite/15"
                    style={{ backgroundColor: ink.hex }}
                  />
                  {ink.name}
                </li>
              ))}
            </ul>
          </div>
          <ShortcutList title="Actions" delay={240} rows={actions} />
        </div>
      </div>
    </section>
  )
}

function ShortcutList({ title, rows, delay }: { title: string; rows: { keys: string; what: string }[]; delay: number }) {
  return (
    <div data-reveal style={{ '--delay': `${delay}ms` }}>
      <h3 class="border-b border-rule pb-3 text-[15px] font-semibold">{title}</h3>
      <dl class="mt-1">
        {rows.map((row) => (
          <div data-key={row.keys} class="-mx-2 flex items-center gap-3 rounded-md border-b border-rule/60 px-2 py-2.5 text-[15px]">
            <dt class="w-12 shrink-0">
              <Kbd>{row.keys}</Kbd>
            </dt>
            <dd>{row.what}</dd>
          </div>
        ))}
      </dl>
    </div>
  )
}

const principles = [
  {
    title: 'Lives in the menu bar',
    body: 'No Dock icon and no windows. Stare stays out of sight until you press ⌥⇧A.',
    icon: 'M4 6.5h16M7 3.5v3M17 3.5v3M5.5 6.5h13v12h-13z',
  },
  {
    title: 'Never steals focus',
    body: 'Draw over Safari and keep scrolling in Safari. The app you are marking up stays in charge.',
    icon: 'M12 5c5 0 8.5 4.5 9 7-.5 2.5-4 7-9 7s-8.5-4.5-9-7c.5-2.5 4-7 9-7zM12 9.5a2.5 2.5 0 1 1 0 5 2.5 2.5 0 0 1 0-5z',
  },
  {
    title: 'Every display, every Space',
    body: 'The drawing sheet covers all your displays, including apps in full screen.',
    icon: 'M3 5h11v8H3zM10 11h11v8H10z',
  },
  {
    title: 'Asks only for what it needs',
    body: 'Drawing works without any permission. Capturing needs Screen Recording, which macOS asks you to allow once.',
    icon: 'M12 3.5l7 3v5c0 4.5-3 7.5-7 9-4-1.5-7-4.5-7-9v-5l7-3zM9 12l2 2 4-4',
  },
]

export function Principles() {
  return (
    <section aria-labelledby="principles-title" class={`${container} py-20 md:py-28`}>
      <h2 id="principles-title" data-reveal class={`${sectionTitle} max-w-[18ch]`}>
        Out of your way until you need it
      </h2>
      <div class="mt-12 grid gap-4 sm:grid-cols-2">
        {principles.map((item, i) => (
          <div
            data-reveal
            data-spotlight
            style={{ '--delay': `${(i % 2) * 120}ms` }}
            class="spotlight group relative overflow-hidden rounded-2xl border border-white/80 bg-paper/60 p-7 shadow-glass backdrop-blur-sm transition-[border-color] hover:border-aurora-blue/50"
          >
            <svg
              aria-hidden="true"
              viewBox="0 0 24 24"
              width="26"
              height="26"
              fill="none"
              stroke="currentColor"
              stroke-width="1.7"
              stroke-linecap="round"
              stroke-linejoin="round"
              class="text-graphite/70 transition-transform duration-300 group-hover:-translate-y-0.5 group-hover:text-ink-blue"
            >
              <path d={item.icon} />
            </svg>
            <h3 class="mt-5 text-[18px] font-bold tracking-tight">{item.title}</h3>
            <p class="mt-2 max-w-[42ch] leading-relaxed text-muted">{item.body}</p>
          </div>
        ))}
      </div>
    </section>
  )
}

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
      </div>
    </section>
  )
}

const faqs = [
  {
    q: 'What does Stare need from my Mac?',
    a: `${site.minimumMacOS} or later. Drawing works without any permission. To capture the screen, Stare needs the Screen Recording permission, which you allow once in System Settings.`,
  },
  {
    q: 'How is it different from a screenshot tool?',
    a: 'You mark up the live screen first and capture second. There is no editor in between unless you want one, so pointing at something takes a couple of key presses.',
  },
  {
    q: 'Does drawing take focus away from the app I am using?',
    a: 'No. The app underneath stays active, so you can draw over it and keep working in it.',
  },
  {
    q: 'Where do my captures go?',
    a: 'Each capture appears as a card in the corner of the screen. Copy it, save it, or drag it into another app. Stare does not upload anything.',
  },
  {
    q: 'Can I try it before installing?',
    a: 'Yes. The demo on this page uses the same tools, inks and keys as the app.',
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
    <footer class={`${container} relative pt-10 pb-12`}>
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
