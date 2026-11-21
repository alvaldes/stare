cask "stare" do
  version "0.2.0"
  # Placeholder: Scripts/release.sh --upload replaces this line with the real
  # sha256 of dist/Stare.dmg. Until then this seed file is not installable.
  sha256 "0000000000000000000000000000000000000000000000000000000000000000"

  url "https://github.com/alvaldes/stare/releases/download/v#{version}/Stare.dmg"
  name "Stare"
  desc "Draw over the live screen to point things out, then capture and paste"
  homepage "https://github.com/alvaldes/stare"

  livecheck do
    url :url
    strategy :github_latest
  end

  depends_on macos: :tahoe

  app "Stare.app"

  caveats <<~EOS
    Stare is not notarized (no Apple Developer account behind it). What you see
    depends on how you install it: Homebrew does not quarantine the download,
    so `brew install --cask` opens Stare without a Gatekeeper prompt, while a
    browser download of Stare.dmg is quarantined and macOS stops the first
    launch — choose Done, then open System Settings → Privacy & Security and
    click Open Anyway, or run
    xattr -d com.apple.quarantine /Applications/Stare.app

    Stare needs Screen Recording to capture the screen (drawing itself needs no
    permission). Grant it once; macOS keys the grant to the code signature, and
    releases are signed with the same Apple Development identity — but that
    certificate expires (2026-04-15) and renewing it resets the grant.
  EOS

  zap trash: [
    "~/Library/Caches/dev.alvaldes.stare",
    "~/Library/Preferences/dev.alvaldes.stare.plist",
  ]
end
