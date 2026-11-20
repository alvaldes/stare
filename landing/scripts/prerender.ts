// Renders every route of the built Worker into static HTML next to the client
// assets, so Cloudflare serves the landing without running the Worker.
import fs from 'node:fs/promises'
import path from 'node:path'
import { fileURLToPath, pathToFileURL } from 'node:url'
import { toSSG } from 'hono/ssg'

const distDir = fileURLToPath(new URL('../dist', import.meta.url))
const outputDir = path.join(distDir, 'client')

/**
 * The Cloudflare Vite plugin names the Worker output directory after the
 * Worker (`stare_landing` today), so look for the build that has a
 * wrangler.json instead of hard-coding the name.
 */
async function findWorkerEntry(): Promise<string> {
  const entries = await fs.readdir(distDir, { withFileTypes: true })
  for (const entry of entries) {
    if (!entry.isDirectory() || entry.name === 'client') continue
    const configPath = path.join(distDir, entry.name, 'wrangler.json')
    const config = await fs.readFile(configPath, 'utf8').catch(() => null)
    if (config === null) continue
    const { main } = JSON.parse(config) as { main: string }
    return path.join(distDir, entry.name, main)
  }
  throw new Error(`No Worker build with a wrangler.json found in ${distDir}. Run vite build first.`)
}

const workerEntry = await findWorkerEntry()
const { default: app } = await import(pathToFileURL(workerEntry).href)
const result = await toSSG(app, fs, { dir: outputDir })

if (!result.success) {
  console.error('Prerender failed:', result.error)
  process.exit(1)
}

for (const file of result.files) {
  console.log(`prerendered ${path.relative(process.cwd(), file)}`)
}
