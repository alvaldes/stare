#!/usr/bin/env bash
# Scripts/release.sh must reject more than one argument instead of treating the
# extras as noise: "Scripts/release.sh --upload --dry-run" must exit non-zero,
# print the usage line to stderr, and leave the tree and dist/Stare.dmg alone.
# A typo next to --upload must never reach the upload path.
set -euo pipefail
cd "$(dirname "$0")/../.."

before_status="$(git status --porcelain)"
before_dmg=""
if [[ -f dist/Stare.dmg ]]; then
    before_dmg="$(shasum -a 256 dist/Stare.dmg | cut -d' ' -f1)"
fi

rc=0
err="$(Scripts/release.sh --upload --dry-run 2>&1 1>/dev/null)" || rc=$?

if [[ "$rc" -eq 0 ]]; then
    echo "FAIL: --upload --dry-run exited 0; the extra argument was ignored and the upload path ran" >&2
    exit 1
fi
if ! grep -q '^usage: Scripts/release.sh \[--upload\]$' <<<"$err"; then
    echo "FAIL: exit $rc but stderr has no usage line:" >&2
    sed 's/^/  /' <<<"$err" >&2
    exit 1
fi

after_status="$(git status --porcelain)"
if [[ "$before_status" != "$after_status" ]]; then
    echo "FAIL: git status changed during the run:" >&2
    diff <(sort <<<"$before_status") <(sort <<<"$after_status") >&2 || true
    exit 1
fi
if [[ -f dist/Stare.dmg ]]; then
    after_dmg="$(shasum -a 256 dist/Stare.dmg | cut -d' ' -f1)"
    if [[ "$before_dmg" != "$after_dmg" ]]; then
        echo "FAIL: dist/Stare.dmg changed during the run" >&2
        exit 1
    fi
fi

echo "PASS: --upload --dry-run exits $rc with the usage line on stderr; tree and dist/Stare.dmg untouched"
