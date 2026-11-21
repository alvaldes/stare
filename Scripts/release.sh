#!/usr/bin/env bash
# Builds the signed Release app with Scripts/bundle.sh and packs it into
# dist/Stare.dmg. The name never changes so the landing (landing/src/release.ts)
# can link to releases/latest/download/Stare.dmg; the volume name carries the
# version.
#
# Without --upload it works in a dirty tree and on an untagged HEAD: the clean
# tree and tag checks belong to the upload path only, so you can pack a local
# DMG at any time. That is a deliberate difference from the upload run, which
# must publish exactly what the tag names.
#
# With --upload it also attaches the .dmg to the GitHub release for that tag,
# creating the release if it does not exist, sets the release notes to the
# version's section of CHANGELOG.md, and rewrites the version and sha256 lines
# of the Homebrew cask in alvaldes/homebrew-tap.
#
# Usage: Scripts/release.sh [--upload]
#
# Signing: an ad-hoc signature changes on every build, so users would lose the
# Screen Recording permission on each update. The release refuses ad-hoc
# signatures; build with an Apple Development identity (the same one JUMP and
# Netty use) or set CODESIGN_IDENTITY.
set -euo pipefail

upload=false
case "${1:-}" in
  "") ;;
  --upload) upload=true ;;
  *) echo "usage: Scripts/release.sh [--upload]" >&2; exit 64 ;;
esac

root="$(git rev-parse --show-toplevel)"
cd "$root"

version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Resources/Info.plist)"
[[ -n "$version" ]] || { echo "error: CFBundleShortVersionString not found in Resources/Info.plist" >&2; exit 1; }
tag="v$version"

if $upload; then
  # The .dmg must be exactly what the tag names; a local run has no such claim.
  if [[ -n "$(git status --porcelain)" ]]; then
    echo "error: the working tree has changes; commit or stash them first" >&2; exit 1
  fi
  if [[ "$(git rev-parse -q --verify "refs/tags/$tag^{commit}" || true)" != "$(git rev-parse HEAD)" ]]; then
    echo "error: HEAD is not tagged $tag (the version in Resources/Info.plist)" >&2; exit 1
  fi
fi

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

# The release notes: the "## <version>" section of CHANGELOG.md, without its heading.
notes="$work/notes.md"
awk -v v="$version" '/^## /{ if (found) exit; found = ($2 == v); next } found' CHANGELOG.md \
  | sed -e '/./,$!d' > "$notes"
if ! grep -q '^[-*+] ' "$notes"; then
  echo "error: CHANGELOG.md has no \"## $version\" section with bullets; describe what this version brings" >&2; exit 1
fi

echo "Building Stare $version (Release)…"
Scripts/bundle.sh release

codesign --verify --strict build/Stare.app
authority="$(codesign -dvv build/Stare.app 2>&1 | sed -n 's/^Authority=//p' | head -1)"
if [[ -z "$authority" ]]; then
  echo "error: the app is ad-hoc signed; the release refuses it because an ad-hoc signature changes on every build and users would lose the Screen Recording permission on each update. Sign with your Apple Development identity (same one as JUMP and Netty) or set CODESIGN_IDENTITY (see README)." >&2; exit 1
fi
built="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' build/Stare.app/Contents/Info.plist)"
[[ "$built" == "$version" ]] || { echo "error: built version $built, expected $version" >&2; exit 1; }

echo "Packing the disk image…"
mkdir -p "$work/dmg" dist
cp -R build/Stare.app "$work/dmg/"
ln -s /Applications "$work/dmg/Applications"
dmg="dist/Stare.dmg"
hdiutil create -quiet -volname "Stare $version" -srcfolder "$work/dmg" -ov -format UDZO "$dmg"
hdiutil verify -quiet "$dmg"

sha="$(shasum -a 256 "$dmg" | cut -d' ' -f1)"
echo "$dmg"
echo "  signed by: $authority"
echo "  sha256:    $sha"

if $upload; then
  if gh release view "$tag" >/dev/null 2>&1; then
    gh release upload "$tag" "$dmg" --clobber
    gh release edit "$tag" --notes-file "$notes"
  else
    # --verify-tag: the tag must already be pushed.
    gh release create "$tag" "$dmg" --title "Stare $version" --notes-file "$notes" --verify-tag
  fi
  echo "Uploaded to release $tag."

  # The cask pins the .dmg's sha256, so it must follow every upload, even a
  # rebuild of the same version.
  cask="repos/alvaldes/homebrew-tap/contents/Casks/stare.rb"
  cask_sha="$(gh api "$cask" -q .sha)"
  gh api "$cask" -q .content | base64 -D > "$work/stare.rb"
  sed -E -e "s/^  version \".*\"$/  version \"$version\"/" \
         -e "s/^  sha256 \".*\"$/  sha256 \"$sha\"/" "$work/stare.rb" > "$work/stare.new.rb"
  if ! grep -qx "  version \"$version\"" "$work/stare.new.rb" || ! grep -qx "  sha256 \"$sha\"" "$work/stare.new.rb"; then
    echo "error: could not find the version and sha256 lines in Casks/stare.rb" >&2; exit 1
  fi
  if cmp -s "$work/stare.rb" "$work/stare.new.rb"; then
    echo "The Homebrew cask is already up to date."
  else
    gh api -X PUT "$cask" --silent \
      -f message="chore: update stare to $version" \
      -f content="$(base64 < "$work/stare.new.rb")" \
      -f sha="$cask_sha"
    echo "Updated the Homebrew cask to $version."
  fi
fi
