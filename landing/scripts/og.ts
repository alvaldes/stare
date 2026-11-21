// Renders the og:image (dist/client/og.png) for link previews at build time.
// satori lays out the card and turns the text into paths with the landing's
// font; resvg rasterizes that SVG. Both run only in this build step, never in
// the Worker, so the image is one more free static asset.
import fs from 'node:fs/promises'
import path from 'node:path'
import { fileURLToPath } from 'node:url'
import { Resvg } from '@resvg/resvg-js'
import satori from 'satori'

export const OG_SIZE = { width: 1200, height: 630 } as const

const root = fileURLToPath(new URL('..', import.meta.url))
const fontDir = path.join(root, 'node_modules/@fontsource/schibsted-grotesk/files')

// Colours from the landing's tokens (src/style.css).
const GRAPHITE = '#1c2030'
const MUTED = '#5b6275'
const DESK = '#e9edf3'

/** The hero's window sketch with the red ring around its button (HeroScene.tsx). */
const WINDOW_SVG = `<svg xmlns="http://www.w3.org/2000/svg" viewBox="-30 -20 440 290">
  <defs><filter id="s" x="-20%" y="-20%" width="140%" height="140%">
    <feDropShadow dx="0" dy="12" stdDeviation="14" flood-color="#1c2030" flood-opacity=".18"/>
  </filter></defs>
  <g filter="url(#s)"><rect width="380" height="230" rx="14" fill="#fff"/></g>
  <path d="M0 14a14 14 0 0 1 14-14h352a14 14 0 0 1 14 14v18H0z" fill="#f5f6f9"/>
  <circle cx="18" cy="16" r="5" fill="#ff5f57"/>
  <circle cx="34" cy="16" r="5" fill="#febc2e"/>
  <circle cx="50" cy="16" r="5" fill="#28c840"/>
  <rect x="22" y="52" width="170" height="11" rx="5.5" fill="#1c2030" opacity=".85"/>
  <rect x="22" y="74" width="230" height="7" rx="3.5" fill="#c9d0dc"/>
  <rect x="22" y="88" width="190" height="7" rx="3.5" fill="#c9d0dc"/>
  <rect x="22" y="112" width="150" height="88" rx="8" fill="#dbe4f3"/>
  <path d="M22 182l40-34 30 24 26-18 54 46v-2a8 8 0 0 1-8 8H30a8 8 0 0 1-8-8z" fill="#b6c6e6"/>
  <rect x="210" y="180" width="118" height="34" rx="9" fill="#007aff"/>
  <rect x="246" y="194" width="46" height="6" rx="3" fill="#fff" opacity=".9"/>
  <path d="M185 197a84 33 0 1 0 168 0a84 33 0 1 0-168 0" fill="none" stroke="#ff3b30" stroke-width="5"/>
  <path d="M186 214l13 12.5-6.2.6 3.6 7.2-2.8 1.3-3.5-7.2-4.1 4.6z" fill="#1c2030" stroke="#fff" stroke-width="1.5" stroke-linejoin="round"/>
</svg>`

type Node = { type: string; props: Record<string, unknown> }

/** Minimal element factory in the shape satori reads (no React needed). */
function h(type: string, props: Record<string, unknown>, ...children: Array<Node | string>): Node {
  return { type, props: { ...props, children: children.length === 1 ? children[0] : children } }
}

function svgDataUri(svg: string): string {
  return `data:image/svg+xml;base64,${Buffer.from(svg).toString('base64')}`
}

export async function renderOgImage(): Promise<Uint8Array> {
  const [regular, heavy, favicon] = await Promise.all([
    fs.readFile(path.join(fontDir, 'schibsted-grotesk-latin-500-normal.woff')),
    fs.readFile(path.join(fontDir, 'schibsted-grotesk-latin-800-normal.woff')),
    fs.readFile(path.join(root, 'public/favicon.svg'), 'utf8'),
  ])

  const card = h(
    'div',
    {
      style: {
        width: '100%',
        height: '100%',
        display: 'flex',
        alignItems: 'center',
        // satori sizes boxes as content-box, so padding here would widen the
        // card past 1200px; the children carry the side margins instead.
        justifyContent: 'space-between',
        backgroundColor: DESK,
        backgroundImage: [
          'radial-gradient(circle at 8% 10%, rgba(127,163,219,.75), rgba(127,163,219,0) 45%)',
          'radial-gradient(circle at 92% 30%, rgba(179,174,232,.8), rgba(179,174,232,0) 45%)',
          'radial-gradient(circle at 75% 105%, rgba(241,194,176,.85), rgba(241,194,176,0) 45%)',
        ].join(', '),
        fontFamily: 'Schibsted Grotesk',
        color: GRAPHITE,
      },
    },
    h(
      'div',
      { style: { display: 'flex', flexDirection: 'column', width: '580px', flexShrink: 0, marginLeft: '72px' } },
      h(
        'div',
        { style: { display: 'flex', alignItems: 'center', gap: '18px' } },
        h('img', { src: svgDataUri(favicon), width: 64, height: 64 }),
        h('div', { style: { fontSize: '40px', fontWeight: 800 } }, 'Stare'),
      ),
      h(
        'div',
        { style: { marginTop: '36px', fontSize: '66px', fontWeight: 800, lineHeight: 1.02, letterSpacing: '-2.4px' } },
        'Draw on your screen, then paste it anywhere.',
      ),
      h(
        'div',
        { style: { marginTop: '28px', fontSize: '28px', fontWeight: 500, color: MUTED } },
        'Open-source menu bar app for macOS',
      ),
    ),
    h('img', { src: svgDataUri(WINDOW_SVG), width: 440, height: 290, style: { flexShrink: 0, marginRight: '56px' } }),
  )

  const svg = await satori(card as never, {
    ...OG_SIZE,
    fonts: [
      { name: 'Schibsted Grotesk', data: regular, weight: 500, style: 'normal' },
      { name: 'Schibsted Grotesk', data: heavy, weight: 800, style: 'normal' },
    ],
  })
  return new Resvg(svg, { fitTo: { mode: 'width', value: OG_SIZE.width } }).render().asPng()
}

if (process.argv[1] === fileURLToPath(import.meta.url)) {
  const out = path.join(root, 'dist/client/og.png')
  await fs.writeFile(out, await renderOgImage())
  console.log(`rendered ${path.relative(process.cwd(), out)}`)
}
