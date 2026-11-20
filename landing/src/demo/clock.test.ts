import { describe, expect, it } from 'vitest'
import { formatMenuBarClock } from './clock'

// Thursday 19 November 2026, 16:58 local time.
const at = new Date(2026, 10, 19, 16, 58)

describe('menu bar clock', () => {
  it('reads like the macOS menu bar: short weekday, then the time', () => {
    expect(formatMenuBarClock(at, 'en-US')).toBe('Thu 4:58 PM')
  })

  it("follows the visitor's locale and 24-hour preference", () => {
    expect(formatMenuBarClock(at, 'en-GB')).toBe('Thu 16:58')
  })

  it('pads minutes but not hours', () => {
    expect(formatMenuBarClock(new Date(2026, 10, 19, 9, 5), 'en-US')).toBe('Thu 9:05 AM')
  })
})
