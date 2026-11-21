// Composes the demo screen and the marks into one PNG. Like the app, it redraws
// the marks from the vector model instead of grabbing the toolbar's window.
import { drawSession } from './render'
import type { DrawingSession } from './session'

export async function renderCapture(
  screen: SVGSVGElement,
  session: DrawingSession,
  size: { width: number; height: number },
  scale = 2,
): Promise<Blob> {
  const markup = new XMLSerializer().serializeToString(screen)
  const svgUrl = URL.createObjectURL(new Blob([markup], { type: 'image/svg+xml' }))
  const image = new Image()
  try {
    image.src = svgUrl
    await image.decode()
  } finally {
    URL.revokeObjectURL(svgUrl)
  }

  const canvas = document.createElement('canvas')
  canvas.width = size.width * scale
  canvas.height = size.height * scale
  const ctx = canvas.getContext('2d')
  if (!ctx) throw new Error('Canvas 2D is not available')

  ctx.drawImage(image, 0, 0, canvas.width, canvas.height)
  ctx.scale(scale, scale)
  // Like MarkCompositor, a capture never includes the laser.
  drawSession(ctx, session, { transient: false })

  return new Promise((resolve, reject) => {
    canvas.toBlob((blob) => (blob ? resolve(blob) : reject(new Error('Could not encode the capture'))), 'image/png')
  })
}

export async function copyImage(blob: Blob): Promise<void> {
  // A promise-valued item keeps Safari's user-gesture requirement satisfied.
  await navigator.clipboard.write([new ClipboardItem({ 'image/png': Promise.resolve(blob) })])
}
