// Client entry: hydrates the interactive parts of the prerendered page.
import { runClock } from '../demo/clock'
import { fitLivePage } from './browser'
import { mountDemo } from './demo'
import { enableDownloads } from './download'
import { lightUpShortcuts, revealOnScroll, trackSpotlights } from './effects'

const demo = document.getElementById('demo')
if (demo) mountDemo(demo)

const clock = document.getElementById('demo-clock')
if (clock) runClock(clock)

const livePage = document.getElementById('demo-page')
if (livePage instanceof HTMLIFrameElement) fitLivePage(livePage)
revealOnScroll()
trackSpotlights()
lightUpShortcuts()
void enableDownloads()
