// SVG for the pointer highlight, drawn the way PointerHighlightRenderer paints
// it: the glow first, then the translucent band punched out with the hole
// shape (`.clear` in the app, which also wipes the glow inside the hole), and
// one bright line on the outer boundary.
import { inkHex } from './model'
import { type PointerLook, pointerAppearance } from './pointer'

/** A rounded square centred on the origin; a corner equal to r makes it a circle. */
export function roundedSquare(r: number, corner: number): string {
  const c = Math.min(corner, r)
  return `M${-r + c} ${-r}H${r - c}A${c} ${c} 0 0 1 ${r} ${-r + c}V${r - c}A${c} ${c} 0 0 1 ${r - c} ${r}H${-r + c}A${c} ${c} 0 0 1 ${-r} ${r - c}V${-r + c}A${c} ${c} 0 0 1 ${-r + c} ${-r}Z`
}

/** `gradientId` must be unique on the page: the markup defines its own gradient. */
export function highlightMarkup(look: PointerLook, gradientId: string): string {
  const a = pointerAppearance(look)
  const color = inkHex(look.ink)
  // The rhombus' rounded corners reach about 1.16 × the radius.
  const half = Math.ceil(Math.max(a.glowRadius, a.radius * 1.2)) + 2
  const ratio = a.corner / a.radius
  const banded = a.shape && a.edgeWidth > 0

  // Nothing paints inside the gradient's start radius, and a banded shape then
  // clears its whole hole, so the glow is a disc with the hole's own shape cut
  // out: the inside of a rhombus stays a clear rhombus. The dot keeps its glow
  // outside its rim; the spotlight is glow from the centre out.
  const cutout = banded
    ? roundedSquare(a.holeRadius, a.holeRadius * ratio)
    : a.glowStart > 0
      ? roundedSquare(a.glowStart, a.glowStart)
      : ''
  const glow =
    a.glowStops.length === 0
      ? ''
      : `<defs><radialGradient id="${gradientId}" gradientUnits="userSpaceOnUse" cx="0" cy="0" r="${a.glowRadius}" fr="${a.glowStart}">${a.glowStops
          .map((stop) => `<stop offset="${stop.offset}" stop-color="${color}" stop-opacity="${stop.alpha}"/>`)
          .join('')}</radialGradient></defs><path d="${roundedSquare(a.glowRadius, a.glowRadius)}${cutout}" fill="url(#${gradientId})" fill-rule="evenodd"/>`

  if (!banded) {
    // The dot is a translucent disc, so the pointer under it stays visible.
    const dot = a.shape ? `<path d="${roundedSquare(a.radius, a.radius)}" fill="${color}" fill-opacity="${a.bandFillAlpha}"/>` : ''
    return svg(half, glow + dot)
  }

  const outer = roundedSquare(a.radius, a.corner)
  const hole = roundedSquare(a.holeRadius, a.holeRadius * ratio)
  const dash = a.dash ? ` stroke-dasharray="${a.dash.join(' ')}" stroke-linecap="butt"` : ''
  // The glow is radially symmetric, so turning it with the shape changes
  // nothing but where its cut-out hole sits.
  return svg(
    half,
    `<g transform="rotate(${a.rotation})">${glow}<path d="${outer}${hole}" fill="${color}" fill-opacity="${a.bandFillAlpha}" fill-rule="evenodd"/><path d="${outer}" fill="none" stroke="${color}" stroke-opacity="${a.edgeAlpha}" stroke-width="${a.edgeWidth}"${dash}/></g>`,
  )
}

function svg(half: number, body: string): string {
  return `<svg width="${half * 2}" height="${half * 2}" viewBox="${-half} ${-half} ${half * 2} ${half * 2}" aria-hidden="true">${body}</svg>`
}
