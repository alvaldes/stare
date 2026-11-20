// Download buttons render as "Coming soon". Once GitHub has a release, they
// turn into real download links. The request goes from the visitor's browser
// straight to GitHub, so it costs nothing on Cloudflare.
import { pickDownload } from '../release'
import { latestReleaseApi } from '../site'

export async function enableDownloads(): Promise<void> {
  const buttons = document.querySelectorAll<HTMLAnchorElement>('[data-download]')
  if (buttons.length === 0) return

  let download = null
  try {
    const response = await fetch(latestReleaseApi, { headers: { Accept: 'application/vnd.github+json' } })
    if (!response.ok) return
    download = pickDownload(await response.json())
  } catch {
    return
  }
  if (!download) return

  for (const button of buttons) {
    button.href = download.href
    button.removeAttribute('aria-disabled')
    button.dataset.available = ''
    const label = button.querySelector('[data-download-label]')
    if (label) label.textContent = 'Download for Mac'
  }
  for (const note of document.querySelectorAll('[data-download-version]')) {
    note.textContent = `Version ${download.version.replace(/^v/, '')}`
  }
}
