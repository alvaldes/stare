import type { Child } from 'hono/jsx'
import { ACTION_ICONS } from '../demo/icons'
import { repoUrl } from '../site'

export function Kbd({ children }: { children: Child }) {
  return (
    <kbd class="inline-flex h-[1.7em] min-w-[1.7em] items-center justify-center rounded-md border border-b-2 border-rule bg-paper px-1.5 align-[0.1em] font-mac text-[0.78em] leading-none font-medium text-graphite">
      {children}
    </kbd>
  )
}

/**
 * Renders as "Coming soon" pointing at the repository. The client script swaps
 * in the latest release's download once one exists (see client/download.ts).
 */
export function DownloadButton({ tone = 'dark' }: { tone?: 'dark' | 'light' }) {
  const colors =
    tone === 'dark' ? 'bg-graphite text-paper hover:bg-graphite/90' : 'bg-paper text-graphite hover:bg-paper/90'
  return (
    <a
      href={repoUrl}
      data-download
      aria-disabled="true"
      title="Stare has not been released yet. Follow it on GitHub."
      class={`group/dl relative inline-flex h-12 items-center gap-2.5 overflow-hidden rounded-full px-6 text-[15px] font-semibold shadow-toolbar transition-[background-color,transform] hover:-translate-y-px active:translate-y-0 ${colors}`}
    >
      {/* A band of light sweeps across now and then, like a reflection on glass. */}
      <span
        aria-hidden="true"
        class={`pointer-events-none absolute inset-y-0 left-0 w-1/3 bg-gradient-to-r from-transparent to-transparent motion-safe:animate-sheen ${
          tone === 'dark' ? 'via-white/25' : 'via-aurora-blue/35'
        }`}
      />
      <svg aria-hidden="true" viewBox="0 0 24 24" width="18" height="18" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
        <path d={ACTION_ICONS.save} />
      </svg>
      <span data-download-label>Coming soon</span>
    </a>
  )
}

export function Logo() {
  return (
    <span class="inline-flex items-center gap-2.5 text-[17px] leading-none font-bold tracking-tight">
      <img src="/favicon.svg" alt="" width="28" height="28" class="block drop-shadow-sm" />
      Stare
    </span>
  )
}
