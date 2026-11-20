import { describe, expect, it } from 'vitest'
import { pickDownload } from './release'

const asset = (name: string) => ({ name, browser_download_url: `https://github.com/dl/${name}` })

describe('pickDownload', () => {
  it('prefers the .dmg asset of the latest release', () => {
    const release = {
      tag_name: 'v0.1.0',
      html_url: 'https://github.com/alvaldes/stare/releases/tag/v0.1.0',
      assets: [asset('Stare-0.1.0.zip'), asset('Stare-0.1.0.dmg')],
    }
    expect(pickDownload(release)).toEqual({ href: 'https://github.com/dl/Stare-0.1.0.dmg', version: 'v0.1.0' })
  })

  it('falls back to a .zip, then to the release page', () => {
    const zipOnly = { tag_name: 'v0.2.0', html_url: 'https://x/rel', assets: [asset('Stare.zip'), asset('notes.txt')] }
    expect(pickDownload(zipOnly)?.href).toBe('https://github.com/dl/Stare.zip')

    const noAssets = { tag_name: 'v0.3.0', html_url: 'https://x/rel', assets: [] }
    expect(pickDownload(noAssets)).toEqual({ href: 'https://x/rel', version: 'v0.3.0' })
  })

  it('returns null for anything that is not a release', () => {
    expect(pickDownload({ message: 'Not Found' })).toBeNull()
    expect(pickDownload(null)).toBeNull()
  })
})
