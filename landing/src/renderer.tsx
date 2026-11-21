import { jsxRenderer } from 'hono/jsx-renderer'
import { Link, Script, ViteClient } from 'vite-ssr-components/hono'
import { site } from './site'

const DEFAULT_TITLE = 'Stare: draw on your screen, capture it, paste it'

/** Per-page head values; pages pass them as c.render's second argument. */
type PageHead = { title?: string; robots?: string }

declare module 'hono' {
  interface ContextRenderer {
    (content: string | Promise<string>, head?: PageHead): Response | Promise<Response>
  }
}

export const renderer = jsxRenderer(({ children, title, robots }: { children?: unknown } & PageHead) => {
  return (
    <html lang="en">
      <head>
        <meta charset="utf-8" />
        <meta name="viewport" content="width=device-width, initial-scale=1" />
        <title>{title ?? DEFAULT_TITLE}</title>
        {robots && <meta name="robots" content={robots} />}
        <meta name="description" content={site.description} />
        <meta property="og:title" content="Stare" />
        <meta property="og:description" content={site.description} />
        <meta property="og:type" content="website" />
        <meta property="og:url" content={`${site.url}/`} />
        <meta property="og:image" content={`${site.url}/og.png`} />
        <meta property="og:image:width" content="1200" />
        <meta property="og:image:height" content="630" />
        <meta property="og:image:alt" content="Stare: draw on your screen, then paste it anywhere." />
        <meta name="twitter:card" content="summary_large_image" />
        <meta name="twitter:image" content={`${site.url}/og.png`} />
        <meta name="theme-color" content="#e9edf3" />
        <link rel="icon" href="/favicon.svg" type="image/svg+xml" />
        {/* Runs before first paint so scroll-reveal content never flashes in and
            out; without JavaScript the class is absent and everything shows. */}
        <script dangerouslySetInnerHTML={{ __html: "document.documentElement.classList.add('js')" }} />
        <ViteClient />
        <Link href="/src/style.css" rel="stylesheet" />
        <Script src="/src/client/main.ts" />
      </head>
      <body>{children}</body>
    </html>
  )
})
