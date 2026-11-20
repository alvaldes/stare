# Stare landing

The public website for Stare, with an in-browser demo of the drawing tools.
It is built with [Hono](https://hono.dev/) and deployed to Cloudflare Workers
on the free plan.

## Run it

```sh
pnpm install
pnpm dev        # Vite dev server with hot reload
pnpm test       # unit tests (Vitest)
pnpm typecheck  # TypeScript, no emit
pnpm build      # production build plus static prerender
pnpm preview    # serve the production build locally
```

## How the page is built

```
src/index.tsx          Hono app: one route per page
src/renderer.tsx       <html> shell, rendered with hono/jsx
src/pages/home.tsx     the landing, assembled from sections
src/components/        server components (hono/jsx)
src/client/            browser code: demo UI (hono/jsx/dom), download links
src/demo/              drawing model shared with the client, mirrored from StareCore
scripts/prerender.ts   turns every route into static HTML with hono/ssg
```

`pnpm build` runs `vite build` and then `scripts/prerender.ts`. That script
imports the built Worker and calls `toSSG`, which writes `index.html` next to
the client assets in `dist/client`.

## Why it costs nothing

On the Workers Free plan, requests that run Worker code are capped at 100,000
per day, but static asset requests are free and unlimited. Every page is
prerendered into static assets, so visiting the landing never runs the Worker.
Only unknown paths reach it.

The demo runs entirely in the browser. The download button asks the GitHub API
for the latest release from the visitor's browser and shows "Coming soon" until
a release exists. Neither uses Cloudflare.

Do not add Cloudflare products that are billed (R2 beyond the free tier,
Workers Paid features) without changing this section first.

## Deploy

```sh
pnpm wrangler login   # once
pnpm deploy           # build, prerender, upload
```

The Worker is named `stare-landing` (see `wrangler.jsonc`).

## Keeping the demo faithful

`src/demo/model.ts` copies the tools, shortcuts, inks, line widths and badge
size from `Sources/StareCore`. When those change in the app, update the model
and the tests in `src/demo/session.test.ts`.
