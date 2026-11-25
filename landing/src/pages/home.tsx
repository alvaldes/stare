import { HeroBackdrop } from '../components/Backdrop'
import { Captures } from '../components/Captures'
import { Demo } from '../components/Demo'
import { Shortcuts } from '../components/Keyboard'
import { PointerSection } from '../components/Pointer'
import { Download, Faq, Footer, Hero, Nav } from '../components/sections'
import { Steps } from '../components/Steps'

export function Home() {
  return (
    <div class="relative isolate overflow-x-clip">
      <HeroBackdrop />
      <Nav />
      <main>
        <Hero />
        <Demo />
        <Steps />
        <Shortcuts />
        <Captures />
        <PointerSection />
        <Download />
        <Faq />
      </main>
      <Footer />
    </div>
  )
}
