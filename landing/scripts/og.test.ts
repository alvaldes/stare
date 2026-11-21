import { describe, expect, it } from 'vitest'
import { OG_SIZE, renderOgImage } from './og'

describe('og:image', () => {
  it('renders a 1200x630 PNG for link previews', async () => {
    const png = await renderOgImage()

    // PNG signature, then the IHDR chunk carries width and height as big-endian u32.
    expect([...png.subarray(0, 8)]).toEqual([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a])
    const view = new DataView(png.buffer, png.byteOffset, png.byteLength)
    expect(view.getUint32(16)).toBe(OG_SIZE.width)
    expect(view.getUint32(20)).toBe(OG_SIZE.height)
    expect(OG_SIZE).toEqual({ width: 1200, height: 630 })
  })
})
