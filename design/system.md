# Stare design system (synced from `landing/src/style.css`)

Source read: `landing/src/style.css` (755 lines). Every token below is copied verbatim from its `@theme` block (lines 9–63) or its `@media (prefers-reduced-motion: reduce)` block (line 719). No values are invented.

**Important scope note:** these tokens describe the **web landing page** (`landing/`). Stare itself is a **native macOS window** (`Sources/Stare/OnboardingView.swift`, 880 × 760 pt). The native window must use **macOS semantic colors and fonts** — `NSColor.windowBackgroundColor`, `.controlBackgroundColor`, `.separatorColor`, the system font, and SF Symbols — not these web tokens. Where a landing token coincides with an Apple system color (`--color-ink-blue` = systemBlue, `--color-ink-green` = systemGreen, `--color-ink-orange` = systemOrange, `--color-graphite` ≈ label color, `--color-desk` ≈ window background, `--color-rule` ≈ separator), the value can stand in for its macOS equivalent; anything else (aurora, chrome, board/key, grain, drift animations) is landing-only and must not leak into the native window.

## Colors

| Token | Value | Usage / source |
| --- | --- | --- |
| `--color-desk` | `#e9edf3` | Cool aluminium page background (≈ macOS `windowBackgroundColor`) — landing/src/style.css |
| `--color-paper` | `#ffffff` | Card / surface background (≈ `.controlBackgroundColor`) — landing/src/style.css |
| `--color-graphite` | `#1c2030` | Primary text on light surfaces (≈ `.labelColor`) — landing/src/style.css |
| `--color-muted` | `#5b6275` | Secondary text on landing hero sizes; too low for small body text on white (≈ 4.3:1) — use `graphite` at ≥ 0.78 opacity for small secondary text instead — landing/src/style.css |
| `--color-rule` | `#d3d9e3` | Hairline separators (≈ `.separatorColor`) — landing/src/style.css |
| `--color-ink-red` | `#ff3b30` | Toolbar ink — landing/src/style.css |
| `--color-ink-orange` | `#ff9500` | Toolbar ink; systemOrange — landing/src/style.css |
| `--color-ink-yellow` | `#ffcc00` | Toolbar ink — landing/src/style.css |
| `--color-ink-green` | `#34c759` | Toolbar ink; systemGreen — landing/src/style.css |
| `--color-ink-blue` | `#007aff` | Toolbar ink, focus outline; systemBlue — landing/src/style.css |
| `--color-ink-purple` | `#b052de` | Toolbar ink — landing/src/style.css |
| `--color-ink-white` | `#ffffff` | Toolbar ink — landing/src/style.css |
| `--color-ink-black` | `#000000` | Toolbar ink — landing/src/style.css |
| `--color-ink-sky` | `#6cb4ff` | Dark-surface accent — landing/src/style.css |
| `--color-aurora-blue` | `#7fa3db` | Demo wallpaper gradient — landing only — landing/src/style.css |
| `--color-aurora-lilac` | `#b3aee8` | Demo wallpaper gradient — landing only — landing/src/style.css |
| `--color-aurora-peach` | `#f1c2b0` | Demo wallpaper gradient — landing only — landing/src/style.css |
| `--color-chrome` | `#23262f` | Dark floating toolbar / capture cards — landing only — landing/src/style.css |
| `--color-board` | `#3a3d45` | Keyboard illustration — landing only — landing/src/style.css |
| `--color-key` | `#1d1f25` | Keyboard illustration — landing only — landing/src/style.css |
| `--color-key-lit` | `#262a33` | Keyboard illustration — landing only — landing/src/style.css |
| `--color-key-hover` | `#2f3440` | Keyboard illustration — landing only — landing/src/style.css |

## Typography

| Token | Value | Usage / source |
| --- | --- | --- |
| `--font-sans` | `'Schibsted Grotesk Variable', ui-sans-serif, system-ui, sans-serif` | Landing page text. **Web-only**: Schibsted Grotesk is loaded by `@fontsource-variable`; the native window must not use it — macOS system font (`--font-mac`) instead — landing/src/style.css |
| `--font-mac` | `-apple-system, BlinkMacSystemFont, 'SF Pro Text', 'Helvetica Neue', sans-serif` | Text inside any depicted macOS surface — landing/src/style.css |

## Spacing

No spacing tokens are defined in the source. The landing page works with Tailwind's default scale (multiples of 4px). Native artboards in this repo use 4/8/16/24/32 rhythm derived from the source's utility usage; treat that as convention, not token.

## Radius & shape

No radius tokens are defined. The landing uses rounded cards, pills and mac-style window shapes case by case. Artboards use large radii for squircles (icons) and medium radii (10–12px) for cards/buttons, matching the source's look — convention, not token.

## Depth / shadows

| Token | Value | Usage / source |
| --- | --- | --- |
| `--shadow-key` | `inset 0 1px 0 rgb(255 255 255 / 0.08), 0 0.25cqw 0 rgb(0 0 0 / 0.55)` | Keyboard key — landing only — landing/src/style.css |
| `--shadow-toolbar` | `0 12px 32px -8px rgb(28 32 48 / 0.45)` | Floating toolbar — landing/src/style.css |
| `--shadow-card` | `0 16px 40px -10px rgb(28 32 48 / 0.55)` | Cards — landing/src/style.css |
| `--shadow-window` | `0 30px 80px -24px rgb(28 32 48 / 0.45)` | Depicted Mac windows — landing/src/style.css |
| `--shadow-glass` | `0 10px 30px -12px rgb(28 32 48 / 0.25), inset 0 1px 0 rgb(255 255 255 / 0.7)` | Glass panels — landing only — landing/src/style.css |

## Motion

| Token | Value | Usage / source |
| --- | --- | --- |
| `--animate-card-in` | `card-in 220ms ease-out` | Card entrance — landing/src/style.css |
| `--animate-draw-in` | `draw-in 900ms cubic-bezier(0.65, 0, 0.35, 1) 900ms both` | Ink stroke draw-in — landing only — landing/src/style.css |
| `--animate-blur-in` | `blur-in 800ms cubic-bezier(0.22, 1, 0.36, 1) both` | Soft entrance — landing only — landing/src/style.css |
| reduced-motion rule | all animation durations forced to `1ms`, loops and reveals disabled | Source: `@media (prefers-reduced-motion: reduce)` block, line 719 — landing/src/style.css |

Drift, sheen, pop-in and the hero-scene loop keys are landing-only marketing motion; never carry them into native UI.

## Component rules

- **Focus:** `:focus-visible` → `outline: 2px solid var(--color-ink-blue); outline-offset: 2px` (line ~135). Artboards must reproduce this as a visible focus style.
- **Cards:** paper background, hairline `--color-rule` border, medium radius; one shadow from the shadow scale, not stacked. Example: `--shadow-glass` on light surfaces.
- **Status:** never color alone — pair the ink color with an icon shape and a text label.
- **Buttons:** filled primary (deeper blue with white label for AA contrast, ~`#0062cc` ≈ `--color-ink-blue` darkened), bordered secondary (`paper` fill, `--color-rule` border, graphite label), plain text tertiary (`--color-muted`-equivalent, ≥ 0.65 opacity graphite).
- **Mac window chrome:** traffic lights left, centered title, `--color-desk` window background, hairline title-bar separator. No fake browser chrome.
