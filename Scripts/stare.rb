cask "stare" do
  version "0.2.0"
  # Placeholder: Scripts/release.sh --upload rewrites this line with the real
  # sha256 of dist/Stare.dmg on every upload.
  sha256 "0000000000000000000000000000000000000000000000000000000000000000"

  url "https://github.com/alvaldes/stare/releases/download/v#{version}/Stare.dmg"
  name "Stare"
  desc "Draw over the live screen to point things out, then capture and paste the result"
  homepage "https://github.com/alvaldes/stare"

  livecheck do
    url :url
    strategy :github_latest
  end

  depends_on macos: :tahoe

  app "Stare.app"

  caveats <<~EOS
    Stare is not notarized (no Apple Developer account), so macOS stops it the
    first time: choose Done, then open System Settings → Privacy & Security and
    click Open Anyway next to “Stare.app” was blocked. Removing the quarantine
    flag also works: xattr -d com.apple.quarantine /Applications/Stare.app

    Stare needs Screen Recording to capture the screen (drawing itself needs no
    permission). Grant it once; macOS remembers the grant per code signature,
    and the release is always signed with the same identity, so updates keep it.
  EOS

  zap trash: [
    "~/Library/Caches/dev.alvaldes.stare",
    "~/Library/Preferences/dev.alvaldes.stare.plist",
  ]
end
