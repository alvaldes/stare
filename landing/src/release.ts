// Turns GitHub's "latest release" response into the download the page offers.

export interface Download {
  href: string
  version: string
}

interface ReleaseAsset {
  name: string
  browser_download_url: string
}

interface Release {
  tag_name: string
  html_url: string
  assets: ReleaseAsset[]
}

function isRelease(value: unknown): value is Release {
  if (typeof value !== 'object' || value === null) return false
  const v = value as Partial<Release>
  return typeof v.tag_name === 'string' && typeof v.html_url === 'string' && Array.isArray(v.assets)
}

/** The disk image if there is one, else an archive, else the release page. */
export function pickDownload(release: unknown): Download | null {
  if (!isRelease(release)) return null
  const byExtension = (ext: string) => release.assets.find((a) => a.name.toLowerCase().endsWith(ext))
  const asset = byExtension('.dmg') ?? byExtension('.zip')
  return { href: asset?.browser_download_url ?? release.html_url, version: release.tag_name }
}
