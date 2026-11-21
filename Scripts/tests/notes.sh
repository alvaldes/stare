#!/usr/bin/env bash
# Scripts/release-notes.sh extracts the "## <version>" section of CHANGELOG.md
# for the release notes. Tests the real script release.sh calls.
set -euo pipefail
cd "$(dirname "$0")/../.."

out="$(Scripts/release-notes.sh 0.2.0)"
if [[ -z "$out" ]]; then
    echo "FAIL: 0.2.0 produced no notes" >&2
    exit 1
fi
if ! head -1 <<<"$out" | grep -q '^[-*+] '; then
    echo "FAIL: the notes do not start with a bullet (the heading must be stripped):" >&2
    head -2 <<<"$out" >&2
    exit 1
fi
if grep -q '^## ' <<<"$out"; then
    echo "FAIL: the notes still contain a ## heading" >&2
    exit 1
fi
if ! grep -q 'New logo' <<<"$out"; then
    echo "FAIL: the 0.2.0 bullets are not all there" >&2
    exit 1
fi

if Scripts/release-notes.sh 0.0.0 >/dev/null 2>&1; then
    echo "FAIL: an unknown version exited 0" >&2
    exit 1
fi

echo "PASS: 0.2.0 yields the changelog bullets without headings; an unknown version exits non-zero"
