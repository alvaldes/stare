// A fictional Mac desktop the visitor can mark up. Styling lives in SVG
// attributes only (no CSS classes) so the capture renders it pixel for pixel.
// It contains a few deliberate flaws worth circling: a typo in a button, a card
// that sits lower than its neighbours and a dip in the chart.

import { SCREEN_HEIGHT, SCREEN_WIDTH } from '../demo/model'

const FONT = "-apple-system, BlinkMacSystemFont, 'Helvetica Neue', Arial, sans-serif"

const plans = [
  { x: 372, y: 206, name: 'Starter', price: '$0', cta: 'Get started', features: ['1 project', 'Community support'] },
  { x: 592, y: 206, name: 'Pro', price: '$12', cta: 'Start free trail', features: ['Unlimited projects', 'Email support'], featured: true },
  { x: 812, y: 218, name: 'Team', price: '$29', cta: 'Contact sales', features: ['Shared workspaces', 'Priority support'] },
]

const signups = [
  { day: 'Mon', value: 62 },
  { day: 'Tue', value: 74 },
  { day: 'Wed', value: 81 },
  { day: 'Thu', value: 23 },
  { day: 'Fri', value: 88 },
  { day: 'Sat', value: 70 },
  { day: 'Sun', value: 76 },
]

const sidebar = ['Overview', 'Pricing page', 'Checkout', 'Emails', 'Changelog']

export function DemoScreen() {
  return (
    <svg
      id="demo-screen"
      xmlns="http://www.w3.org/2000/svg"
      viewBox={`0 0 ${SCREEN_WIDTH} ${SCREEN_HEIGHT}`}
      width={SCREEN_WIDTH}
      height={SCREEN_HEIGHT}
      class="absolute inset-0 h-full w-full select-none"
      role="img"
      aria-label="A Mac desktop showing a draft pricing page in an app called Ledger"
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
        <filter id="window-shadow" x="-10%" y="-10%" width="120%" height="130%">
          <feDropShadow dx="0" dy="18" stdDeviation="22" flood-color="#1c2030" flood-opacity="0.28" />
        </filter>
        <clipPath id="window-clip">
          <rect x="150" y="62" width="900" height="610" rx="12" />
        </clipPath>
      </defs>

      <rect width={SCREEN_WIDTH} height={SCREEN_HEIGHT} fill="url(#wall)" />
      <rect width={SCREEN_WIDTH} height={SCREEN_HEIGHT} fill="url(#glow)" />

      {/* Menu bar */}
      <rect width={SCREEN_WIDTH} height="28" fill="#ffffff" fill-opacity="0.42" />
      {/* Apple menu. Using the Apple logo here is a deliberate choice by the
          project owner, aware that Apple's trademark guidelines restrict it
          (see odd/tasks/landing.md, L11). Path from svgl.app, 814\u00d71000,
          scaled to 14 points tall and centred on the menu glyph spot (22,14). */}
      <path
        transform="translate(16.3 7) scale(0.014)"
        fill="#1c2030"
        d="M788.1 340.9c-5.8 4.5-108.2 62.2-108.2 190.5 0 148.4 130.3 200.9 134.2 202.2-.6 3.2-20.7 71.9-68.7 141.9-42.8 61.6-87.5 123.1-155.5 123.1s-85.5-39.5-164-39.5c-76.5 0-103.7 40.8-165.9 40.8s-105.6-57-155.5-127C46.7 790.7 0 663 0 541.8c0-194.4 126.4-297.5 250.8-297.5 66.1 0 121.2 43.4 162.7 43.4 39.5 0 101.1-46 176.3-46 28.5 0 130.9 2.6 198.3 99.2zm-234-181.5c31.1-36.9 53.1-88.1 53.1-139.3 0-7.1-.6-14.3-1.9-20.1-50.6 1.9-110.8 33.7-147.1 75.8-28.5 32.4-55.1 83.6-55.1 135.5 0 7.8 1.3 15.6 1.9 18.1 3.2.6 8.4 1.3 13.6 1.3 45.4 0 102.5-30.4 135.5-71.3z"
      />
      <text x="42" y="19" font-size="13" font-weight="700" fill="#1c2030">Ledger</text>
      <text x="104" y="19" font-size="13" fill="#1c2030" word-spacing="14">File Edit View Window Help</text>
      {/* Stare's menu bar glyph: the open nib from the logo, 16 points wide. */}
      <mask id="stare-glyph-nib" maskUnits="userSpaceOnUse" x="0" y="0" width="64" height="64">
        <path d="M32 6c8 7 12.5 16 10.3 28.5L32 56 21.7 34.5C19.5 22 24 13 32 6z" fill="#fff" />
        <circle cx="32" cy="30.5" r="3.4" fill="#000" />
        <path d="M31 32h2v26h-2z" fill="#000" />
      </mask>
      <g transform="translate(1010 6) scale(0.25) rotate(40 32 32)">
        <rect width="64" height="64" fill="#1c2030" mask="url(#stare-glyph-nib)" />
      </g>
      <rect x="1042" y="9" width="20" height="10" rx="3" fill="none" stroke="#1c2030" stroke-width="1.4" />
      <rect x="1044.5" y="11.5" width="12" height="5" rx="1.2" fill="#1c2030" />
      {/* Replaced with the visitor's real time by client/main.ts */}
      <text id="demo-clock" x="1178" y="19" font-size="13" fill="#1c2030" text-anchor="end">
        Thu 9:41
      </text>

      {/* App window */}
      <rect x="150" y="62" width="900" height="610" rx="12" fill="#ffffff" filter="url(#window-shadow)" />
      <g clip-path="url(#window-clip)">
        <rect x="150" y="62" width="900" height="42" fill="#f5f6f9" />
        <rect x="150" y="104" width="900" height="1" fill="#e2e6ee" />
        <circle cx="172" cy="83" r="6" fill="#ff5f57" />
        <circle cx="192" cy="83" r="6" fill="#febc2e" />
        <circle cx="212" cy="83" r="6" fill="#28c840" />
        <text x="600" y="88" font-size="13" font-weight="600" fill="#4a5060" text-anchor="middle">Pricing page</text>

        <rect x="150" y="105" width="190" height="567" fill="#f3f5f9" />
        <rect x="340" y="105" width="1" height="567" fill="#e2e6ee" />
        {sidebar.map((item, i) => (
          <g>
            {i === 1 && <rect x="160" y={124 + i * 34} width="170" height="28" rx="7" fill="#dbe4f3" />}
            <text x="176" y={143 + i * 34} font-size="13" fill={i === 1 ? '#1c2030' : '#5b6275'} font-weight={i === 1 ? '600' : '400'}>
              {item}
            </text>
          </g>
        ))}

        <text x="372" y="146" font-size="22" font-weight="700" fill="#1c2030">Pricing page review</text>
        <text x="372" y="170" font-size="13" fill="#5b6275">Draft 3, waiting for comments before Friday</text>

        {plans.map((plan) => (
          <g>
            <rect
              x={plan.x}
              y={plan.y}
              width="200"
              height="196"
              rx="10"
              fill="#ffffff"
              stroke={plan.featured ? '#007aff' : '#e2e6ee'}
              stroke-width={plan.featured ? 2 : 1}
            />
            <text x={plan.x + 18} y={plan.y + 32} font-size="14" font-weight="600" fill="#1c2030">{plan.name}</text>
            <text x={plan.x + 18} y={plan.y + 72} font-size="30" font-weight="700" fill="#1c2030">{plan.price}</text>
            <text x={plan.x + 22 + plan.price.length * 17} y={plan.y + 72} font-size="12" fill="#5b6275">/ month</text>
            {plan.features.map((feature, i) => (
              <text x={plan.x + 18} y={plan.y + 102 + i * 20} font-size="12" fill="#5b6275">{feature}</text>
            ))}
            <rect
              x={plan.x + 18}
              y={plan.y + 146}
              width="164"
              height="32"
              rx="7"
              fill={plan.featured ? '#007aff' : '#f0f2f6'}
            />
            <text
              x={plan.x + 100}
              y={plan.y + 166}
              font-size="12.5"
              font-weight="600"
              fill={plan.featured ? '#ffffff' : '#1c2030'}
              text-anchor="middle"
            >
              {plan.cta}
            </text>
          </g>
        ))}

        <text x="372" y="452" font-size="14" font-weight="600" fill="#1c2030">Sign-ups this week</text>
        <text x="1012" y="452" font-size="12" fill="#5b6275" text-anchor="end">474 total</text>
        <rect x="372" y="466" width="640" height="1" fill="#e2e6ee" />
        {signups.map((bar, i) => {
          const height = bar.value * 1.6
          const x = 392 + i * 88
          return (
            <g>
              <rect x={x} y={630 - height} width="48" height={height} rx="6" fill={i === 3 ? '#c5cede' : '#8fa8d6'} />
              <text x={x + 24} y="652" font-size="11.5" fill="#5b6275" text-anchor="middle">{bar.day}</text>
            </g>
          )
        })}
      </g>
    </svg>
  )
}
