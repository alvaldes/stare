// Client entry: hydrates the interactive parts of the prerendered page.
import { runClock } from '../demo/clock'
import { mountDemo } from './demo'
import { enableDownloads } from './download'
import { lightUpShortcuts, revealOnScroll, trackSpotlights } from './effects'

const demo = document.getElementById('demo')
if (demo) mountDemo(demo)

const clock = document.getElementById('demo-clock')
if (clock) runClock(clock)
revealOnScroll()
trackSpotlights()
lightUpShortcuts()
void enableDownloads()
