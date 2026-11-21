#!/usr/bin/env bash
# Scripts/write-cask.sh rewrites the version and sha256 lines of a Homebrew
# cask and refuses anything it cannot rewrite, so release.sh can validate the
# cask before it publishes. Tests the real script, not a copy of its sed.
set -euo pipefail
cd "$(dirname "$0")/../.."

version="9.9.9"
sha="deadbeef"

# A two-space cask is rewritten with exactly two-space indentation.
good="$(mktemp)"
bad="$(mktemp)"
trap 'rm -f "$good" "$bad"' EXIT
cat >"$good" <<'EOF'
cask "stare" do
  version "0.0.0"
  sha256 "1111"

  url "https://github.com/alvaldes/stare/releases/download/v#{version}/Stare.dmg"
  app "Stare.app"
end
EOF

out="$(Scripts/write-cask.sh "$version" "$sha" "$good")"
if ! grep -qx '  version "9.9.9"' <<<"$out"; then
    echo "FAIL: the version line is not exactly two-space indented:" >&2
    grep -n 'version' <<<"$out" >&2
    exit 1
fi
if ! grep -qx '  sha256 "deadbeef"' <<<"$out"; then
    echo "FAIL: the sha256 line is not exactly two-space indented:" >&2
    grep -n 'sha256' <<<"$out" >&2
    exit 1
fi
if grep -q '0\.0\.0\|"1111"' <<<"$out"; then
    echo "FAIL: old values survived the rewrite" >&2
    exit 1
fi
if ! grep -q 'url "https://github.com/alvaldes/stare/releases/download/v#{version}/Stare.dmg"' <<<"$out"; then
    echo "FAIL: the rest of the cask did not survive the rewrite" >&2
    exit 1
fi

# A cask whose lines are not two-space indented must make the guard exit
# non-zero, never pass silently.
sed 's/^  /    /' "$good" >"$bad"
if out="$(Scripts/write-cask.sh "$version" "$sha" "$bad" 2>/dev/null)"; then
    echo "FAIL: a four-space cask was accepted; the guard did not fire" >&2
    exit 1
fi

echo "PASS: two-space lines rewritten exactly; a four-space cask exits non-zero"
