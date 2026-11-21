import { describe, expect, it } from 'vitest'
import { graphemes, withoutEmoji } from './text'

describe('typing text', () => {
  it('keeps an emoji with a skin tone as one character', () => {
    expect(graphemes('Hi 👋🏻!')).toEqual(['H', 'i', ' ', '👋🏻', '!'])
  })

  it('splits plain text letter by letter', () => {
    expect(graphemes('abc')).toEqual(['a', 'b', 'c'])
  })

  it('drops emoji for screen reader labels', () => {
    expect(withoutEmoji("Hey there 👋🏻 Stare's creator here.")).toBe("Hey there Stare's creator here.")
  })

  it('reads a line break in the label as a space', () => {
    expect(withoutEmoji("Hey there 👋🏻\nStare's creator here.")).toBe("Hey there Stare's creator here.")
  })
})
