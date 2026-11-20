/**
 * The demo's menu bar clock, formatted like macOS: short weekday, then the
 * time in the visitor's locale and 12/24-hour preference.
 */
export function formatMenuBarClock(date: Date, locale?: string): string {
  const weekday = date.toLocaleDateString(locale, { weekday: 'short' })
  const time = date.toLocaleTimeString(locale, { hour: 'numeric', minute: '2-digit' })
  // Some locales use a narrow no-break space before AM/PM; macOS shows a plain one.
  return `${weekday} ${time}`.replace(/ /g, ' ')
}

/** Keeps an element showing the current time, ticking on the minute. */
export function runClock(element: Element, locale?: string): void {
  const tick = () => {
    const now = new Date()
    element.textContent = formatMenuBarClock(now, locale)
    setTimeout(tick, 60_000 - (now.getSeconds() * 1000 + now.getMilliseconds()))
  }
  tick()
}
