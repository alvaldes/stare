import { HeroBackdrop } from '../components/Backdrop'
import { Demo } from '../components/Demo'
import { Download, Faq, Footer, Hero, Nav, Principles, Shortcuts, Steps } from '../components/sections'

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
        <Principles />
        <Download />
        <Faq />
      </main>
      <Footer />
    </div>
  )
}
