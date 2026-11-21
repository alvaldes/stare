/** Facts about the product shared by every section of the landing. */
export const site = {
  name: 'Stare',
  description:
    'Stare is an open-source macOS menu bar app. Draw over any app, capture the screen with your marks, and paste the image anywhere.',
  /** GitHub repository that hosts the source and the release downloads. */
  repo: 'alvaldes/stare',
  minimumMacOS: 'macOS 26',
  /** Production address of the landing; link previews need absolute URLs. */
  url: 'https://stare.alvaldes.workers.dev',
} as const

export const repoUrl = `https://github.com/${site.repo}`
export const releasesUrl = `${repoUrl}/releases/latest`
export const latestReleaseApi = `https://api.github.com/repos/${site.repo}/releases/latest`
