#!/usr/bin/env bash
# Sweep every repository of one GitHub owner for SHA-pinned GitHub Actions that
# have a newer release, and print one Markdown report to stdout.
#
# Only repositories whose `.trunk/trunk.yaml` enables the pinact linter are
# scanned: those are the ones that chose SHA pins, so a newer release there is
# a pin gone stale. A repository that disabled pinact chose floating tags and
# has nothing to report. Archived repositories and forks are skipped.
#
# The report is meant for a public place (this repository's tracking issue and
# its Actions log), so private repositories appear in it only as counts. Their
# names, paths and pins are printed only with --show-private, for a run on the
# operator's own machine.
#
# The report edits nothing and opens no pull request anywhere; it is the input
# of scripts/action-pin-sweep-report.sh, which keeps one tracking issue.
#
# Usage: action-pin-sweep.sh [--show-private] <owner>   print the report
#        action-pin-sweep.sh --enforces-pinact           read a trunk.yaml on
#                                                        stdin; exit 0 when it
#                                                        enables pinact, 1 otherwise
#
# Exit: 0 when the sweep ran, even with repositories it could not scan (those
#       are listed in the report); 1 when the repository listing failed or
#       nothing was scanned, so a broken token never yields an "all current"
#       report.
#
# Needs `gh` authenticated with a token that can list and read the owner's
# repositories (GH_TOKEN), `git`, and `pinact` on PATH; the same token serves
# pinact's release lookups through GITHUB_TOKEN.

set -euo pipefail

here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)
core="$here/../actions/pinact-outdated/pinact-outdated.sh"

# True when the trunk.yaml on stdin enables pinact and does not disable it.
# pinact is enabled either by a literal entry under `lint.enabled`, with or
# without a version, or by inheritance from the quality-configs plugin, whose
# root plugin.yaml enables it for every consumer that lists the plugin under
# `plugins.sources` (by its GitHub uri, or as the local source this repository
# uses on itself). A `lint.disabled` entry wins over both: trunk uses it to
# switch off a linter that a plugin or profile enables, so a repository that
# carries it has chosen floating tags.
enforces_pinact() {
  awk '
    /^lint:/            { in_lint = 1; in_plugins = 0; section = ""; next }
    /^plugins:/         { in_plugins = 1; in_lint = 0; section = ""; next }
    /^[A-Za-z]/         { in_lint = 0; in_plugins = 0; section = ""; next }
    in_lint && /^  [a-z_]+:/ { section = $1; sub(":", "", section); next }
    in_lint && /^ +- pinact(@[0-9][0-9A-Za-z.+-]*)? *$/ {
      if (section == "enabled") enabled = 1
      if (section == "disabled") disabled = 1
    }
    in_plugins && /^ +(- )?uri: +https:\/\/github\.com\/AndrewDongminYoo\/quality-configs(\.git)? *$/ { inherited = 1 }
    in_plugins && /^ +(- )?id: +quality-configs *$/ { inherited = 1 }
    END                 { exit ((enabled || inherited) && !disabled) ? 0 : 1 }
  '
}

show_private=0
owner=""
for arg in "$@"; do
  case "$arg" in
    --enforces-pinact)
      enforces_pinact
      exit $?
      ;;
    --show-private) show_private=1 ;;
    -*)
      echo "action-pin-sweep: unknown option $arg" >&2
      exit 64
      ;;
    *) owner=$arg ;;
  esac
done
[[ -n "$owner" ]] || {
  echo "usage: action-pin-sweep.sh [--show-private] <owner>" >&2
  exit 64
}

work=$(mktemp -d "${TMPDIR:-/tmp}/action-pin-sweep.XXXXXX")
trap 'rm -rf "$work"' EXIT

# The listing is taken first, on its own, so a failed or empty listing stops
# the sweep instead of feeding an empty loop that would report every pin as
# current. Each line is "<name>\t<true|false>" for the private flag. gh caps
# the listing at --limit and succeeds silently at the cap, so a result that
# reaches it is treated as truncated and fails the sweep.
list_limit=1000
if ! repos=$(gh repo list "$owner" --limit "$list_limit" --no-archived --source --json name,isPrivate --jq '.[] | "\(.name)\t\(.isPrivate)"' 2>"$work/list.err"); then
  echo "action-pin-sweep: listing $owner's repositories failed: $(head -n 1 "$work/list.err")" >&2
  exit 1
fi
if [[ -z "$repos" ]]; then
  echo "action-pin-sweep: $owner has no repositories to scan" >&2
  exit 1
fi
if (($(printf '%s\n' "$repos" | wc -l) >= list_limit)); then
  echo "action-pin-sweep: the listing reached $list_limit repositories and may be truncated; raise list_limit" >&2
  exit 1
fi
# gh orders the listing by last push, so it is sorted by name here: the
# report's order is what the reporter compares, and an unrelated push must
# not read as a change in the outdated set.
repos=$(printf '%s\n' "$repos" | sort)

swept=0
# Repositories whose scan finished with pinact exit 0; only these can vouch
# that their pins are current.
completed=0
findings=""
partial=""
errors=""
skipped_no_trunk=0
skipped_not_enforcing=0
# Private repositories are counted here and named only with --show-private.
# Their findings and problems are also folded into a digest, so the public
# report changes whenever the private set changes even when the counts do not.
private_swept=0
private_outdated_repos=0
private_outdated_pins=0
private_incomplete=0
private_lines=""

record_finding() {
  local full=$1 report=$2 is_private=$3
  local count
  count=$(printf '%s\n' "$report" | wc -l | tr -d ' ')
  if [[ "$is_private" == true && "$show_private" == 0 ]]; then
    private_outdated_repos=$((private_outdated_repos + 1))
    private_outdated_pins=$((private_outdated_pins + count))
    private_lines+="$full"$'\n'"$report"$'\n'
    return 0
  fi
  findings+="### $full"$'\n\n'
  local line location change old new
  while IFS= read -r line; do
    location=${line%%: *}
    change=${line#*: }
    old=${change%% -> *}
    new=${change#* -> }
    findings+="- \`$location\`: \`$old\` -> \`$new\`"$'\n'
  done <<<"$report"
  findings+=$'\n'
}

record_problem() {
  local kind=$1 full=$2 reason=$3 is_private=$4
  if [[ "$is_private" == true && "$show_private" == 0 ]]; then
    private_incomplete=$((private_incomplete + 1))
    private_lines+="$kind $full: $reason"$'\n'
    return 0
  fi
  if [[ "$kind" == partial ]]; then
    partial+="- \`$full\`: $reason"$'\n'
  else
    errors+="- \`$full\`: $reason"$'\n'
  fi
}

while IFS=$'\t' read -r repo is_private; do
  [[ -n "$repo" ]] || continue
  full="$owner/$repo"

  # One API read decides whether the repository is in scope; only in-scope
  # repositories are cloned. A 404 is the one normal answer (no trunk
  # configuration); any other failure is a repository this sweep did not see.
  if ! trunk_b64=$(gh api "repos/$full/contents/.trunk/trunk.yaml" --jq '.content' 2>"$work/$repo.api"); then
    if grep -q "HTTP 404" "$work/$repo.api"; then
      skipped_no_trunk=$((skipped_no_trunk + 1))
    else
      record_problem error "$full" "reading .trunk/trunk.yaml failed: $(head -n 1 "$work/$repo.api")" "$is_private"
    fi
    continue
  fi
  if ! printf '%s' "$trunk_b64" | base64 -d | enforces_pinact; then
    skipped_not_enforcing=$((skipped_not_enforcing + 1))
    continue
  fi

  clone="$work/$repo"
  if ! gh repo clone "$full" "$clone" -- --depth 1 --quiet >/dev/null 2>&1; then
    record_problem error "$full" "clone failed" "$is_private"
    continue
  fi

  swept=$((swept + 1))
  [[ "$is_private" == true ]] && private_swept=$((private_swept + 1))
  status=0
  report=$(bash "$core" "$clone" 2>"$work/$repo.err") || status=$?
  ((status == 0)) && completed=$((completed + 1))
  if ((status != 0)); then
    # The first line of stderr is the wrapper's own notice; pinact's reason
    # follows it, so the first line carrying an error level is quoted.
    reason=$(grep -m 1 -E '^(ERROR|FATAL|WARN)' "$work/$repo.err" || sed -n '2p' "$work/$repo.err")
    if ((status == 3)); then
      # A partial scan: what resolved is reported below, and the unresolved
      # line is named here so the repository can exclude it in .pinact.yaml.
      record_problem partial "$full" "${reason:-pinact reported an error}" "$is_private"
    else
      record_problem error "$full" "pinact failed: ${reason:-no error output}" "$is_private"
      continue
    fi
  fi
  [[ -n "$report" ]] || continue
  record_finding "$full" "$report" "$is_private"
done <<<"$repos"

# A sweep in which no scan completed (every clone or every pinact run failed,
# typically a token problem) is a failure, not a clean result.
if ((completed == 0)) && [[ -z "$findings" ]] && ((private_outdated_repos == 0)); then
  echo "action-pin-sweep: no repository was scanned completely; see the report for the reasons" >&2
  printf '## Outdated GitHub Actions pins\n\nNo repository was scanned completely.\n\n'
  [[ -n "$errors" ]] && printf '### Not scanned\n\n%s\n' "$errors"
  exit 1
fi

outdated_repos=$(printf '%s' "$findings" | grep -c '^### ' || true)
outdated_repos=$((outdated_repos + private_outdated_repos))
incomplete=$((swept - completed))

printf '## Outdated GitHub Actions pins\n\n'
printf 'Swept %d repositories that enforce pinact; %d need an update.\n' "$swept" "$outdated_repos"
printf 'Skipped %d without a trunk configuration and %d whose trunk configuration does not enable pinact.\n\n' "$skipped_no_trunk" "$skipped_not_enforcing"
if [[ -n "$findings" ]]; then
  printf '%s' "$findings"
elif ((private_outdated_repos == 0)); then
  if ((incomplete == 0 && private_incomplete == 0)) && [[ -z "$errors" ]]; then
    printf 'Every pin is at its latest release.\n\n'
  else
    printf 'No outdated pin was found in the %d repositories scanned completely; the rest are listed or counted below.\n\n' "$completed"
  fi
fi
if ((private_outdated_repos > 0 || private_incomplete > 0)); then
  printf '### Private repositories\n\n'
  printf '%d private repositories were scanned; %d of them have %d outdated pins, and %d could not be scanned completely.\n' \
    "$private_swept" "$private_outdated_repos" "$private_outdated_pins" "$private_incomplete"
  printf 'They are not named here because this report is public; run the sweep locally with --show-private to list them.\n'
  # The digest is over the sorted private lines, so it moves when a private
  # finding appears, disappears or changes, and only then.
  printf 'Private set digest: %s\n\n' "$(printf '%s' "$private_lines" | sort | shasum -a 256 | cut -c1-16)"
fi
if [[ -n "$partial" ]]; then
  printf '### Partially scanned\n\nThese repositories carry a reference pinact cannot pin, such as a branch; the pins it could resolve are listed above. An ignore rule in the repository .pinact.yaml makes the scan complete.\n\n%s\n' "$partial"
fi
if [[ -n "$errors" ]]; then
  printf '### Not scanned\n\n%s\n' "$errors"
fi
