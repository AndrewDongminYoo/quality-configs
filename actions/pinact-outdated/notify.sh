#!/usr/bin/env bash
# Trunk action adapter: run pinact-outdated.sh against the workspace and turn
# its report into a notification_v1 document, so `trunk check` and the IDE show
# "N action pins have a newer release" without editing anything.
#
# Silent when pinact is unavailable or fails: a daily background action must
# never turn a missing tool or a network error into a standing warning. A
# machine without pinact simply gets no notification.

set -euo pipefail

here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)
id=pinact-outdated

repo_root=$(git rev-parse --show-toplevel 2>/dev/null) || exit 0

# Exit 3 is a partial scan: the resolved lines are still worth showing, and the
# unresolvable ones are the repository's own floating refs.
status=0
report=$(bash "$here/pinact-outdated.sh" "$repo_root" 2>/dev/null) || status=$?
if ((status != 0 && status != 3)); then
  exit 0
fi

if [[ -z "$report" ]]; then
  # Only a complete scan may clear a standing notification; a partial scan
  # that resolved nothing (a lookup failure on every line) says nothing about
  # whether the pins it last reported are still outdated.
  ((status == 0)) && printf 'notifications_to_delete:\n  - %s\n' "$id"
  exit 0
fi

count=$(printf '%s\n' "$report" | wc -l | tr -d ' ')
noun="pins have"
[[ "$count" == 1 ]] && noun="pin has"
partial_note=""
((status == 3)) && partial_note=" The scan was partial (pinact could not resolve every line), so more pins may be outdated."

printf 'notifications:\n'
printf '  - id: %s\n' "$id"
printf '    title: GitHub Actions pins\n'
printf '    message: |\n'
printf '      %s action %s a newer release.%s Edit the version comment to the tag you want, then run pinact from the repository root to pin it:\n' "$count" "$noun" "$partial_note"
printf '%s\n' "$report" | sed 's/^/      /'
# The repair runs pinact itself from the repository root, not trunk: the scan
# covers every action.yml in the tree, while trunk's github-actions file type
# reaches only .github/actions/**. The binary is the one the scan used, by
# absolute path, since trunk's copy is not on PATH.
pinact_bin=$(command -v pinact 2>/dev/null || true)
if [[ -z "$pinact_bin" ]]; then
  cache="${TRUNK_CACHE:-$HOME/.cache/trunk}/tools/pinact"
  pinact_bin=$(find "$cache" -mindepth 2 -maxdepth 2 -type f -name pinact 2>/dev/null | sort -V | tail -n 1 || true)
fi
# The command is one single-quoted YAML scalar; the shell quoting of the
# binary path lives inside it.
printf '    commands:\n'
printf "      - run: '\"%s\" run'\n" "${pinact_bin:-pinact}"
printf '        title: Re-pin with pinact\n'
