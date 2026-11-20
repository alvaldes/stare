import { jsxRenderer } from 'hono/jsx-renderer'
import { Link, Script, ViteClient } from 'vite-ssr-components/hono'
import { site } from './site'

export const renderer = jsxRenderer(({ children }) => {
  return (
    <html lang="en">
      <head>
        <meta charset="utf-8" />
        <meta name="viewport" content="width=device-width, initial-scale=1" />
        <title>Stare: draw on your screen, capture it, paste it</title>
        <meta name="description" content={site.description} />
        <meta property="og:title" content="Stare" />
        <meta property="og:description" content={site.description} />
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
