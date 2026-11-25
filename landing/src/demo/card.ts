// The capture card, ported from the app: CaptureCardView's plate and timing,
// and CaptureCardController's stack. Sizes are in screen points.

const THUMBNAIL_MAX = { width: 190, height: 126 }
export const PLATE_INSET = 6
const MINIMUM_CONTENT_WIDTH = 132
/** CaptureCardControlButton.side: the round pin and close buttons. */
export const CONTROL_SIDE = 22
const MARGIN = 20
const GAP = 10
const MAXIMUM_UNPINNED = 4

export interface CardSize {
  width: number
  height: number
  thumbnail: { width: number; height: number }
}

/** CaptureCardView.preferredSize: the capture fitted, never upscaled, on a plate. */
export function cardSize(imageWidth: number, imageHeight: number): CardSize {
  const scale = Math.min(THUMBNAIL_MAX.width / imageWidth, THUMBNAIL_MAX.height / imageHeight, 1)
  const thumbnail = { width: Math.round(imageWidth * scale), height: Math.round(imageHeight * scale) }
  return {
    width: Math.max(thumbnail.width, MINIMUM_CONTENT_WIDTH) + PLATE_INSET * 2,
    height: thumbnail.height + PLATE_INSET * 2,
    thumbnail,
  }
}

/** Milliseconds before the card leaves on its own, or null while it must stay. */
export function autoDismissDelay(state: { pinned: boolean; hovered: boolean; hasBeenHovered: boolean }): number | null {
  if (state.pinned || state.hovered) return null
  return state.hasBeenHovered ? 3000 : 5000
}

/** Closes the oldest unpinned cards until at most four unpinned remain. */
export function evictOverflow<T extends { pinned: boolean }>(cards: T[]): T[] {
  let unpinned = cards.filter((c) => !c.pinned).length
  return cards.filter((card) => {
    if (card.pinned || unpinned <= MAXIMUM_UNPINNED) return true
    unpinned--
    return false
  })
}

/** Each card's distance from the bottom edge: stacked up from the corner. */
export function stackBottoms(heights: number[]): number[] {
  let bottom = MARGIN
  return heights.map((height) => {
    const at = bottom
    bottom += height + GAP
    return at
  })
}

/** Distance of the stack from the right edge. */
export const STACK_MARGIN = MARGIN
