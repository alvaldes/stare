import { describe, expect, it } from 'vitest'
import app from './index'

describe('404 page', () => {
  it('answers unknown paths with a styled 404 page', async () => {
    const res = await app.request('/does/not/exist')

    expect(res.status).toBe(404)
    expect(res.headers.get('content-type')).toContain('text/html')
    const html = await res.text()
    expect(html).toContain('<title>Page not found · Stare</title>')
    expect(html).toContain('<meta name="robots" content="noindex"/>')
    expect(html).toContain('Nothing to draw on here.')
    expect(html).toContain('href="/"')
  })

  it('links the nav to sections of the home page from any path', async () => {
    const html = await (await app.request('/does/not/exist')).text()

    expect(html).toContain('href="/#try"')
    expect(html).toContain('href="/#download"')
  })

  it('keeps the home page title and status', async () => {
    const res = await app.request('/')

    expect(res.status).toBe(200)
    const html = await res.text()
    expect(html).toContain('<title>Stare: draw on your screen, capture it, paste it</title>')
    expect(html).not.toContain('noindex')
  })
})
