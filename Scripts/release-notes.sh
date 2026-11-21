#!/usr/bin/env bash
# Prints the "## <version>" section of CHANGELOG.md, without its heading, for
# use as the GitHub release notes. Exits non-zero when the section has no
# bullets.
# Usage: Scripts/release-notes.sh <version>
set -euo pipefail

if [[ $# -ne 1 ]]; then
    echo "usage: Scripts/release-notes.sh <version>" >&2
    exit 64
fi
version="$1"
cd "$(dirname "$0")/.."

notes="$(awk -v v="$version" '/^## /{ if (found) exit; found = ($2 == v); next } found' CHANGELOG.md \
    | sed -e '/./,$!d')"
if ! grep -q '^[-*+] ' <<<"$notes"; then
    echo "error: CHANGELOG.md has no \"## $version\" section with bullets; describe what this version brings" >&2
    exit 1
fi

printf '%s\n' "$notes"
