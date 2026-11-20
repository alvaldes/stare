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
})
