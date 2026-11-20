// Living backgrounds: slow-drifting aurora light in the demo wallpaper's
// colours, a dotted grid and film grain. Purely decorative.

export function Aurora({ tone = 'light' }: { tone?: 'light' | 'dark' }) {
  const strength = tone === 'light' ? 'opacity-60' : 'opacity-45'
  return (
    <div aria-hidden="true" class={`pointer-events-none absolute inset-0 -z-10 overflow-hidden ${strength}`}>
      <div class="absolute -top-[20%] -left-[10%] size-[55vmax] rounded-full bg-aurora-blue blur-[90px] motion-safe:animate-drift-a" />
      <div class="absolute top-[5%] -right-[15%] size-[45vmax] rounded-full bg-aurora-lilac blur-[100px] motion-safe:animate-drift-b" />
      <div class="absolute -bottom-[25%] left-[25%] size-[40vmax] rounded-full bg-aurora-peach blur-[100px] motion-safe:animate-drift-c" />
    </div>
  )
}

/** The backdrop behind the hero and the demo. */
export function HeroBackdrop() {
  return (
    <div aria-hidden="true" class="pointer-events-none absolute inset-x-0 top-0 -z-10 h-[min(1400px,140vh)]">
      <Aurora />
      <div class="bg-dots absolute inset-0" />
      <div class="grain absolute inset-0 opacity-[0.18]" />
      {/* Fade into the plain desk colour so the next section starts calm. */}
      <div class="absolute inset-x-0 bottom-0 h-1/3 bg-gradient-to-b from-desk/0 to-desk" />
    </div>
  )
}
