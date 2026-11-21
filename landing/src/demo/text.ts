// Text helpers for the typing effect in the creator's note.

const segmenter = new Intl.Segmenter('en', { granularity: 'grapheme' })

/**
 * Splits text into what a reader sees as single characters. An emoji with a
 * skin tone (👋🏻) is several UTF-16 code units; typing those one at a time
 * would flash broken glyphs.
 */
export function graphemes(text: string): string[] {
  return Array.from(segmenter.segment(text), (s) => s.segment)
}

/** The text without emoji, for labels read aloud by screen readers. */
export function withoutEmoji(text: string): string {
  return text
    .replace(/\p{Extended_Pictographic}[\p{Emoji_Modifier}\uFE0F\u200D]*/gu, '')
    .replace(/\s+/g, ' ')
    .trim()
}
