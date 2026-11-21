// A pretend Mac desktop the visitor can mark up: Safari showing the creator's
// portfolio. The desktop, menu bar and Safari chrome are SVG with styling in
// attributes only (no CSS classes) so the capture renders them pixel for pixel.
// The page itself is a live iframe laid over BROWSER_VIEWPORT (see Demo.tsx);
// browsers never let a page read a cross-origin iframe's pixels, so captures
// show the placeholder drawn underneath it instead.

import { SCREEN_HEIGHT, SCREEN_WIDTH } from '../demo/model'

const FONT = "-apple-system, BlinkMacSystemFont, 'Helvetica Neue', Arial, sans-serif"

export const PORTFOLIO_URL = 'https://www.alvaldes.dev/'
export const PORTFOLIO_HOST = 'alvaldes.dev'

const WINDOW = { x: 100, y: 46, width: 1000, height: 650, radius: 12 }
const TOOLBAR_HEIGHT = 28

/** Horizontal position inside the window, in screen points. */
const X = (offset: number) => WINDOW.x + offset

/** Where the page shows inside the window, in screen points. */
export const BROWSER_VIEWPORT = {
  x: WINDOW.x,
  y: WINDOW.y + TOOLBAR_HEIGHT,
  width: WINDOW.width,
  height: WINDOW.height - TOOLBAR_HEIGHT,
  radius: WINDOW.radius,
}

const ink = '#1c2030'
const chrome = '#3c4049'

export function DemoScreen() {
  const v = BROWSER_VIEWPORT
  const toolbarY = WINDOW.y + TOOLBAR_HEIGHT / 2
  return (
    <svg
      id="demo-screen"
      xmlns="http://www.w3.org/2000/svg"
      viewBox={`0 0 ${SCREEN_WIDTH} ${SCREEN_HEIGHT}`}
      width={SCREEN_WIDTH}
      height={SCREEN_HEIGHT}
      class="absolute inset-0 h-full w-full select-none"
      role="img"
      aria-label={`A Mac desktop with Safari open on ${PORTFOLIO_HOST}`}
      font-family={FONT}
    >
      <defs>
        <linearGradient id="wall" x1="0" y1="0" x2="1" y2="1">
          <stop offset="0" stop-color="#7fa3db" />
          <stop offset="0.55" stop-color="#b3aee8" />
          <stop offset="1" stop-color="#f1c2b0" />
        </linearGradient>
        <radialGradient id="glow" cx="0.2" cy="0.95" r="0.6">
          <stop offset="0" stop-color="#ffe7d6" stop-opacity="0.9" />
          <stop offset="1" stop-color="#ffe7d6" stop-opacity="0" />
        </radialGradient>
        <filter id="capsule-shadow" x="-10%" y="-20%" width="120%" height="160%">
          <feDropShadow dx="0" dy="0.4" stdDeviation="0.5" flood-color="#000" flood-opacity="0.12" />
        </filter>
        <filter id="window-shadow" x="-10%" y="-10%" width="120%" height="130%">
          <feDropShadow dx="0" dy="18" stdDeviation="22" flood-color="#1c2030" flood-opacity="0.28" />
        </filter>
        <clipPath id="window-clip">
          <rect x={WINDOW.x} y={WINDOW.y} width={WINDOW.width} height={WINDOW.height} rx={WINDOW.radius} />
        </clipPath>
        <mask id="stare-glyph-nib" maskUnits="userSpaceOnUse" x="0" y="0" width="64" height="64">
          <path d="M32 6c8 7 12.5 16 10.3 28.5L32 56 21.7 34.5C19.5 22 24 13 32 6z" fill="#fff" />
          <circle cx="32" cy="30.5" r="3.4" fill="#000" />
          <path d="M31 32h2v26h-2z" fill="#000" />
        </mask>
      </defs>

      <rect width={SCREEN_WIDTH} height={SCREEN_HEIGHT} fill="url(#wall)" />
      <rect width={SCREEN_WIDTH} height={SCREEN_HEIGHT} fill="url(#glow)" />

      {/* Menu bar. Safari has focus: Stare draws over it without taking it. */}
      <rect width={SCREEN_WIDTH} height="28" fill="#ffffff" fill-opacity="0.42" />
      {/* Apple menu. Using the Apple logo here is a deliberate choice by the
          project owner, aware that Apple's trademark guidelines restrict it
          (see odd/tasks/landing.md, L11). Path from svgl.app, 814×1000,
          scaled to 14 points tall and centred on the menu glyph spot (22,14). */}
      <path
        transform="translate(16.3 7) scale(0.014)"
        fill={ink}
        d="M788.1 340.9c-5.8 4.5-108.2 62.2-108.2 190.5 0 148.4 130.3 200.9 134.2 202.2-.6 3.2-20.7 71.9-68.7 141.9-42.8 61.6-87.5 123.1-155.5 123.1s-85.5-39.5-164-39.5c-76.5 0-103.7 40.8-165.9 40.8s-105.6-57-155.5-127C46.7 790.7 0 663 0 541.8c0-194.4 126.4-297.5 250.8-297.5 66.1 0 121.2 43.4 162.7 43.4 39.5 0 101.1-46 176.3-46 28.5 0 130.9 2.6 198.3 99.2zm-234-181.5c31.1-36.9 53.1-88.1 53.1-139.3 0-7.1-.6-14.3-1.9-20.1-50.6 1.9-110.8 33.7-147.1 75.8-28.5 32.4-55.1 83.6-55.1 135.5 0 7.8 1.3 15.6 1.9 18.1 3.2.6 8.4 1.3 13.6 1.3 45.4 0 102.5-30.4 135.5-71.3z"
      />
      <text x="42" y="19" font-size="13" font-weight="700" fill={ink}>Safari</text>
      <text x="100" y="19" font-size="13" fill={ink} word-spacing="14">File Edit View History Bookmarks Window Help</text>
      {/* Stare's menu bar glyph: the open nib from the logo, 16 points wide. */}
      <g transform="translate(1010 6) scale(0.25) rotate(40 32 32)">
        <rect width="64" height="64" fill={ink} mask="url(#stare-glyph-nib)" />
      </g>
      <rect x="1042" y="9" width="20" height="10" rx="3" fill="none" stroke={ink} stroke-width="1.4" />
      <rect x="1044.5" y="11.5" width="12" height="5" rx="1.2" fill={ink} />
      {/* Replaced with the visitor's real time by client/main.ts */}
      <text id="demo-clock" x="1178" y="19" font-size="13" fill={ink} text-anchor="end">
        Thu 9:41
      </text>

      {/* Safari window */}
      <rect
        x={WINDOW.x}
        y={WINDOW.y}
        width={WINDOW.width}
        height={WINDOW.height}
        rx={WINDOW.radius}
        fill="#ffffff"
        filter="url(#window-shadow)"
      />
      <g clip-path="url(#window-clip)">
        {/* Toolbar, measured from a Safari 26 screenshot (window 2576 px wide →
            1000 units, factor 0.388): controls in glass capsules on a grey bar.
            The extension and settings icons of that install are left out. */}
        <rect x={WINDOW.x} y={WINDOW.y} width={WINDOW.width} height={TOOLBAR_HEIGHT} fill="#ececec" />
        <rect x={WINDOW.x} y={v.y - 0.5} width={WINDOW.width} height="0.5" fill="#cfcfd2" />

        <circle cx={X(13.6)} cy={toolbarY} r="4.4" fill="#ff5f57" />
        <circle cx={X(25.9)} cy={toolbarY} r="4.4" fill="#febc2e" />
        <circle cx={X(38.1)} cy={toolbarY} r="4.4" fill="#28c840" />

        {/* Sidebar capsule (sidebar icon + menu chevron) and back/forward capsule */}
        <g fill="#fbfbfb" stroke="#000" stroke-opacity="0.1" stroke-width="0.5" filter="url(#capsule-shadow)">
          <rect x={X(50.4)} y={toolbarY - 9.3} width="32.2" height="18.6" rx="9.3" />
          <rect x={X(87.7)} y={toolbarY - 9.3} width="37.6" height="18.6" rx="9.3" />
        </g>
        <path d={`M${X(106.4)} ${toolbarY - 4.6}v9.2`} stroke="#000" stroke-opacity="0.14" stroke-width="0.6" />

        <g fill="none" stroke={chrome} stroke-width="0.9" stroke-linecap="round" stroke-linejoin="round">
          <rect x={X(54.9)} y={toolbarY - 4.1} width="10.4" height="8.2" rx="1.8" />
          <path d={`M${X(58.6)} ${toolbarY - 4.1}v8.2`} />
          <path d={`M${X(56.5)} ${toolbarY - 2}h0.8M${X(56.5)} ${toolbarY - 0.4}h0.8`} stroke-width="0.7" />
          <path d={`M${X(71.8)} ${toolbarY - 0.9}l1.9 1.9 1.9-1.9`} />
          <path d={`M${X(98.4)} ${toolbarY - 3.6}l-3.2 3.6 3.2 3.6`} />
          <path d={`M${X(114.5)} ${toolbarY - 3.6}l3.2 3.6-3.2 3.6`} opacity="0.45" />

          {/* Share: tray with an arrow out of it */}
          <path d={`M${X(946.5)} ${toolbarY - 5.6}v6.6M${X(944)} ${toolbarY - 3.4}l2.5-2.5 2.5 2.5M${X(944.4)} ${toolbarY - 1.7}h-1.6v6.6h7.4v-6.6h-1.6`} />
          {/* New tab */}
          <path d={`M${X(965.2)} ${toolbarY - 4.3}v8.6M${X(960.9)} ${toolbarY}h8.6`} />
          {/* Tab overview: two overlapping rounded squares */}
          <path d={`M${X(981.9)} ${toolbarY - 4.9}h4.4a1.6 1.6 0 0 1 1.6 1.6v4.4`} />
          <rect x={X(979.4)} y={toolbarY - 2.6} width="7" height="7" rx="1.6" />
        </g>

        {/* Address field: a full capsule, domain centred, reload at the end */}
        <rect x={X(293.7)} y={toolbarY - 10} width="411.3" height="20" rx="10" fill="#000" fill-opacity="0.055" />
        <text x={X(499.4)} y={toolbarY + 2.7} font-size="7.6" fill={ink} text-anchor="middle">{PORTFOLIO_HOST}</text>
        <path
          d={`M${X(693)} ${toolbarY - 2.2}a3 3 0 1 0 0.7 2.8M${X(693.6)} ${toolbarY - 4.8}v2.7h-2.7`}
          fill="none"
          stroke={chrome}
          stroke-width="0.85"
          stroke-linecap="round"
          stroke-linejoin="round"
        />

        {/* Under the live page, in its dark theme: what captures show, since the iframe can't be read. */}
        <rect x={v.x} y={v.y} width={v.width} height={v.height} fill="#16181f" />
        <text x={v.x + v.width / 2} y={v.y + v.height / 2} font-size="22" font-weight="600" fill="#4a5060" text-anchor="middle">
          {PORTFOLIO_HOST}
        </text>
      </g>
    </svg>
  )
}
