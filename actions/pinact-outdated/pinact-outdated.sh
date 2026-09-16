#!/usr/bin/env bash
# Report every pinned GitHub Action in a repository that has a newer release,
# without touching the repository.
#
# The repository's `.github/` tree, root `action.yml`/`action.yaml`, and any
# `.pinact.yaml` are copied to a temporary directory; `pinact run --update`
# rewrites the copy to the latest releases; the copy is diffed against the
# original. One line per changed `uses:` value:
#
#   <path>:<line>: <old uses value> -> <new uses value>
#
# Nothing is printed when every pin is current. A `.pinact.yaml` in the
# repository is honoured, so a deliberately floating reference that the
# repository excludes there is not reported.
#
# Usage: pinact-outdated.sh [<repo-root>]      (default: the current directory)
# Exit:  0 when every line was resolved, with or without findings; 3 when
#        pinact reported an error on some line (a floating branch ref such as
#        `@stable` that it cannot pin, or a lookup that failed) — the lines it
#        did resolve are still printed and its errors go to stderr, so a
#        partial scan never reads as "all current"; 1 when pinact is not
#        available at all.
#
# pinact needs a GitHub token to resolve the latest releases: it reads
# GITHUB_TOKEN or PINACT_GITHUB_TOKEN, and falls back to `gh auth token`.

set -euo pipefail

root=$(cd "${1:-.}" && pwd -P)

pinact_bin=$(command -v pinact 2>/dev/null || true)
if [[ -z "$pinact_bin" ]]; then
  # Trunk keeps the tool it downloaded for the pinact linter under its cache;
  # the newest version there serves when no pinact is on PATH.
  cache="${TRUNK_CACHE:-$HOME/.cache/trunk}/tools/pinact"
  pinact_bin=$(find "$cache" -mindepth 2 -maxdepth 2 -type f -name pinact 2>/dev/null | sort -V | tail -n 1 || true)
fi
if [[ -z "$pinact_bin" || ! -x "$pinact_bin" ]]; then
  echo "pinact-outdated: pinact not found on PATH or in the trunk tool cache" >&2
  exit 1
fi

# Without a token pinact shares the anonymous 60-requests-per-hour budget of
# the machine's address and fails on the first busy hour, so the local gh
# login stands in when nothing is exported (the same fallback trunk's own
# pinact wrapper makes). CI exports GITHUB_TOKEN explicitly.
if [[ -z "${GITHUB_TOKEN:-}" && -z "${PINACT_GITHUB_TOKEN:-}" ]] && command -v gh >/dev/null 2>&1; then
  if token=$(gh auth token 2>/dev/null) && [[ -n "$token" ]]; then
    export GITHUB_TOKEN="$token"
  fi
fi

work=$(mktemp -d "${TMPDIR:-/tmp}/pinact-outdated.XXXXXX")
trap 'rm -rf "$work"' EXIT
orig="$work/orig"
copy="$work/copy"
mkdir -p "$orig" "$copy"

# Only the files pinact reads are copied, so a large repository costs nothing
# beyond its workflow and action files: the .github tree, its configuration,
# and every action.yml or action.yaml anywhere in the tree (a composite action
# can live in any directory, and pinact finds it there), at the same relative
# path so the diff reports the real location.
# Every copy dereferences symlinks (-L): a symlinked workflow copied as a link
# would still point into the real repository, and pinact writing through it
# would edit the original. The copy holds regular files only.
copy_tree() {
  local dest=$1
  [[ -d "$root/.github" ]] && cp -RL "$root/.github" "$dest/.github"
  local f
  for f in .pinact.yml .pinact.yaml; do
    [[ -f "$root/$f" ]] && cp -L "$root/$f" "$dest/$f"
  done
  local rel
  while IFS= read -r rel; do
    rel=${rel#./}
    mkdir -p "$dest/$(dirname "$rel")"
    cp -L "$root/$rel" "$dest/$rel"
  done < <(cd "$root" && find . -path ./.git -prune -o -path ./.github -prune -o \( -name action.yml -o -name action.yaml \) \( -type f -o -type l \) -print)
  return 0
}
copy_tree "$orig"
copy_tree "$copy"

# pinact keeps going after a line it cannot handle and exits nonzero at the
# end, so the copy already holds every update it could resolve; the diff is
# taken either way and the exit code says whether it is complete.
pinact_status=0
(cd "$copy" && "$pinact_bin" run --update >"$work/pinact.log" 2>&1) || pinact_status=$?

# Each copied file is diffed against its original by path, so the report
# never parses a diff header (which GNU diff quotes when a path has a space).
# `diff -U0` gives one hunk per changed run of lines; pinact changes one line
# per `uses:`, so old and new lines pair up by position inside a hunk. The
# awk keeps only the `uses:` value of each side.
report_file() {
  local rel=$1
  diff -U0 "$orig/$rel" "$copy/$rel" 2>/dev/null | awk -v file="$rel" '
    function flush(   i) {
      for (i = 1; i <= n_old && i <= n_new; i++) {
        printf "%s:%d: %s -> %s\n", file, start + i - 1, old[i], new[i]
      }
      n_old = 0; n_new = 0
    }
    function uses_value(line) {
      sub(/^[-+]/, "", line)
      sub(/^[ \t]*-?[ \t]*uses:[ \t]*/, "", line)
      sub(/[ \t]+$/, "", line)
      return line
    }
    /^(\+\+\+|---) / { next }
    /^@@ /     { flush(); s = $0; sub(/^@@ -[0-9,]+ \+/, "", s); sub(/[ ,].*$/, "", s); start = s + 0; next }
    /^-/       { old[++n_old] = uses_value($0); next }
    /^\+/      { new[++n_new] = uses_value($0); next }
    END        { flush() }
  ' || true
}
while IFS= read -r rel; do
  rel=${rel#./}
  [[ -f "$orig/$rel" ]] || continue
  report_file "$rel"
done < <(cd "$copy" && find . -type f | sort)

if ((pinact_status != 0)); then
  echo "pinact-outdated: pinact reported errors in $root (exit $pinact_status); the lines above are the ones it could resolve" >&2
  cat "$work/pinact.log" >&2
  exit 3
fi
