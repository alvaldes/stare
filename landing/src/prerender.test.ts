import { toSSG } from 'hono/ssg'
import { describe, expect, it } from 'vitest'
import app from './index'

/** Minimal in-memory file system with the two calls toSSG makes. */
function memoryFs() {
  const files = new Map<string, string>()
  return {
    files,
    fs: {
      async mkdir() {},
      async writeFile(path: string, data: string | Uint8Array) {
        files.set(path, typeof data === 'string' ? data : new TextDecoder().decode(data))
      },
    },
  }
}

describe('static prerender', () => {
  it('renders the landing into index.html with the demo section', async () => {
    const { files, fs } = memoryFs()
    const result = await toSSG(app, fs, { dir: 'out' })

    expect(result.success).toBe(true)
    const html = files.get('out/index.html')
    expect(html).toBeDefined()
    expect(html).toContain('<title>Stare')
    expect(html).toContain('id="try"')
  })

  it('points link previews at the absolute og:image', async () => {
    const { files, fs } = memoryFs()
    await toSSG(app, fs, { dir: 'out' })
    const html = files.get('out/index.html') ?? ''

    expect(html).toContain('<meta property="og:image" content="https://stare.alvaldes.workers.dev/og.png"/>')
    expect(html).toContain('<meta property="og:image:width" content="1200"/>')
    expect(html).toContain('<meta property="og:image:height" content="630"/>')
    expect(html).toContain('<meta property="og:url" content="https://stare.alvaldes.workers.dev/"/>')
    expect(html).toContain('<meta name="twitter:card" content="summary_large_image"/>')
    expect(html).toContain('<meta name="twitter:image" content="https://stare.alvaldes.workers.dev/og.png"/>')
  })
})
