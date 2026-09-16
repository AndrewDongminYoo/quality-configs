#!/usr/bin/env bash
# Keep one tracking issue in this repository in step with a sweep report, and
# comment on it only when the set of outdated pins changed, so the issue is
# the single notification channel: a comment arrives when there is something
# new to act on, and nothing arrives while the picture is unchanged.
#
# Usage: action-pin-sweep-report.sh <report.md>
# Needs `gh` authenticated for this repository (GH_TOKEN) with issues: write,
# and GITHUB_REPOSITORY; GITHUB_SERVER_URL and GITHUB_RUN_ID, when set, link
# the comment to the run that produced it.

set -euo pipefail

report_file=${1:?usage: action-pin-sweep-report.sh <report.md>}
repo=${GITHUB_REPOSITORY:?GITHUB_REPOSITORY is not set}
label=action-pin-sweep
title="Outdated GitHub Actions pins"

report=$(cat "$report_file")
# The body carries the whole report minus its title, never the date. The
# comment decision reads only the outdated set out of it: repository headings,
# the pin and problem bullets, the private-repository counts and the private
# set digest. The sweep statistics ("Skipped N ...") change when an unrelated
# repository appears and must not produce a comment on their own. The lines
# are kept in report order, not sorted: the sweep already lists repositories
# by name and bullets in file order, and sorting would let a pin that moved
# from one repository to another read as no change.
body=$(printf '%s\n' "$report" | sed '1,/^$/d')
outdated_set() {
  grep -E '^(### |- `|[0-9]+ private repositories |Private set digest: )'
}
has_findings=0
grep -q '^### ' <<<"$body" && has_findings=1

gh label create "$label" --repo "$repo" --force --color 0E8A16 \
  --description "Weekly sweep of SHA-pinned GitHub Actions with a newer release" >/dev/null

existing=$(gh issue list --repo "$repo" --label "$label" --state open --limit 1 --json number,body)
number=$(jq -r '.[0].number // empty' <<<"$existing")
old_body=$(jq -r '.[0].body // empty' <<<"$existing")

run_link=""
if [[ -n "${GITHUB_SERVER_URL:-}" && -n "${GITHUB_RUN_ID:-}" ]]; then
  run_link=" ([run]($GITHUB_SERVER_URL/$repo/actions/runs/$GITHUB_RUN_ID))"
fi
today=$(date -u +%Y-%m-%d)

if [[ -z "$number" ]]; then
  if ((has_findings == 0)); then
    echo "no open tracking issue and nothing outdated; nothing to do"
    exit 0
  fi
  url=$(gh issue create --repo "$repo" --title "$title" --label "$label" \
    --assignee "${repo%%/*}" --body "$body")
  echo "created $url"
  exit 0
fi

if [[ "$body" == "$old_body" ]]; then
  echo "issue #$number unchanged; no comment"
  exit 0
fi

if [[ "$(outdated_set <<<"$body")" == "$(outdated_set <<<"$old_body")" ]]; then
  gh issue edit "$number" --repo "$repo" --body "$body" >/dev/null
  echo "updated issue #$number body; the outdated set is unchanged, no comment"
  exit 0
fi
had_findings=0
grep -q '^### ' <<<"$old_body" && had_findings=1

# The comment goes first and the body second. A failed comment then fails the
# step before the body records the new state, so the next run sees a changed
# body and comments again; a failed body edit after a delivered comment costs
# at most one duplicate comment on the next run.
if ((has_findings == 1)); then
  gh issue comment "$number" --repo "$repo" \
    --body "$(printf 'Sweep on %s%s changed the outdated set.\n\n%s' "$today" "$run_link" "$body")" >/dev/null
  gh issue edit "$number" --repo "$repo" --body "$body" >/dev/null
  echo "commented on and updated issue #$number"
elif ((had_findings == 1)); then
  gh issue comment "$number" --repo "$repo" \
    --body "$(printf 'Sweep on %s%s: every pin is at its latest release.' "$today" "$run_link")" >/dev/null
  gh issue edit "$number" --repo "$repo" --body "$body" >/dev/null
  echo "commented on and updated issue #$number: all current"
else
  gh issue edit "$number" --repo "$repo" --body "$body" >/dev/null
  echo "updated issue #$number body; no findings before or after"
fi
