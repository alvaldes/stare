#!/usr/bin/env bash
# Rewrites the version and sha256 lines of a Homebrew cask: reads the cask from
# a path or stdin, writes the rewritten copy to stdout. Exits non-zero when the
# version or sha256 lines cannot be rewritten, so release.sh can validate the
# cask BEFORE it publishes anything.
# Usage: Scripts/write-cask.sh <version> <sha256> [cask-path]
set -euo pipefail

if [[ $# -lt 2 || $# -gt 3 ]]; then
    echo "usage: Scripts/write-cask.sh <version> <sha256> [cask-path]" >&2
    exit 64
fi
version="$1"
sha="$2"
input="/dev/stdin"
[[ $# -eq 3 ]] && input="$3"

tmp="$(mktemp)"
trap 'rm -f "$tmp"' EXIT

# Only lines indented with exactly two spaces are anchors; anything else must
# fail the guard below rather than pass silently.
sed -E -e "s/^  version \".*\"$/  version \"$version\"/" \
       -e "s/^  sha256 \".*\"$/  sha256 \"$sha\"/" "$input" > "$tmp"
if ! grep -qx "  version \"$version\"" "$tmp" || ! grep -qx "  sha256 \"$sha\"" "$tmp"; then
    echo "error: could not rewrite the two-space-indented version and sha256 lines of the cask" >&2
    exit 1
fi

cat "$tmp"
