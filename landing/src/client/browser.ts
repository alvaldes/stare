// Scales the live page in the demo's Safari window. The iframe lays out at a
// laptop width (its width attribute) and is shrunk with a transform, so the
// portfolio shows its desktop layout at any demo size.

export function fitLivePage(iframe: HTMLIFrameElement): void {
  const frame = iframe.parentElement
  if (!frame) return
  const pageWidth = iframe.width ? Number(iframe.width) : 1280
  const fit = () => {
    iframe.style.transform = `scale(${frame.clientWidth / pageWidth})`
  }
  new ResizeObserver(fit).observe(frame)
  fit()
}
