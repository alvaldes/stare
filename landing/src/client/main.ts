// Client entry: hydrates the interactive parts of the prerendered page.
import { runClock } from '../demo/clock'
import { fitLivePage } from './browser'
import { playCreatorNote } from './creatorNote'
import { mountDemo } from './demo'
import { mountKeyboardPanel } from './keyboard'
import { mountPointer } from './pointer'
import { enableDownloads } from './download'
import { lightUpShortcuts, revealOnScroll, trackSpotlights } from './effects'

const demo = document.getElementById('demo')
if (demo) mountDemo(demo)

const clock = document.getElementById('demo-clock')
if (clock) runClock(clock)

const keyPreview = document.getElementById('key-preview')
const shortcuts = document.getElementById('shortcuts')
if (keyPreview && shortcuts) mountKeyboardPanel(keyPreview, shortcuts)

playCreatorNote()

const pointerControls = document.getElementById('pointer-controls')
if (pointerControls) mountPointer(pointerControls)

const livePage = document.getElementById('demo-page')
if (livePage instanceof HTMLIFrameElement) fitLivePage(livePage)
revealOnScroll()
trackSpotlights()
lightUpShortcuts()
void enableDownloads()

// 404 page: Esc leaves, the same key that clears and leaves in the app.
const escHome = document.querySelector<HTMLAnchorElement>('[data-esc-home]')
if (escHome) {
  document.addEventListener('keydown', (event) => {
    if (event.key === 'Escape' && !event.defaultPrevented) location.assign(escHome.href)
  })
}
