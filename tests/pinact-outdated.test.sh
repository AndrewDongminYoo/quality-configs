#!/bin/bash
# Unit test for actions/pinact-outdated/pinact-outdated.sh and notify.sh.
# pinact itself is replaced by a stub on PATH, so the test needs no network and
# no GitHub token: what is under test is the copy-then-diff around pinact and
# the shape of the reported lines, not pinact's own resolution of the latest
# release.

set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)
core="$repo_root/actions/pinact-outdated/pinact-outdated.sh"
test_root=$(mktemp -d "${TMPDIR:-/tmp}/pinact-outdated-test.XXXXXX")
trap 'rm -rf "$test_root"' EXIT

failures=0
fail() {
  printf 'FAIL: %s\n' "$1" >&2
  failures=$((failures + 1))
}
pass() {
  printf 'ok: %s\n' "$1"
}

# A fixture repository with one workflow holding two pinned actions.
fixture="$test_root/repo"
mkdir -p "$fixture/.github/workflows"
cat >"$fixture/.github/workflows/ci.yml" <<'YAML'
name: CI
on: push
jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1 # v7.0.1
      - uses: pnpm/action-setup@0977fd99725f1db4007ccb2928dbb4e90d06cc86 # v6.0.10
YAML
cp "$fixture/.github/workflows/ci.yml" "$test_root/ci.yml.orig"
# A composite action outside .github, which pinact scans from the repository
# root and the copy must therefore carry at the same relative path.
mkdir -p "$fixture/actions/setup"
cat >"$fixture/actions/setup/action.yml" <<'YAML'
name: setup
runs:
  using: composite
  steps:
    - uses: actions/setup-node@820762786026740c76f36085b0efc47a31fe5020 # v7.0.0
YAML

# The stub honours the one contract the core relies on: `pinact run --update`
# rewrites workflow files under the current directory in place. Its behavior
# is chosen per test through PINACT_STUB_MODE.
stub_dir="$test_root/bin"
mkdir -p "$stub_dir"
cat >"$stub_dir/pinact" <<'SH'
#!/bin/bash
set -euo pipefail
[[ "${1:-}" == run && "${2:-}" == --update ]] || { echo "stub: unexpected arguments: $*" >&2; exit 64; }
case "${PINACT_STUB_MODE:-bump}" in
  bump)
    sed -i.bak 's|pnpm/action-setup@0977fd99725f1db4007ccb2928dbb4e90d06cc86 # v6.0.10|pnpm/action-setup@ea17c68df8912ef543352723c149a84f56e3d413 # v6.1.0|' .github/workflows/ci.yml
    rm -f .github/workflows/ci.yml.bak
    ;;
  current) ;;
  bump-all)
    # Same rewrite as bump, applied to every workflow file in the copy.
    for f in .github/workflows/*.yml; do
      sed -i.bak 's|pnpm/action-setup@0977fd99725f1db4007ccb2928dbb4e90d06cc86 # v6.0.10|pnpm/action-setup@ea17c68df8912ef543352723c149a84f56e3d413 # v6.1.0|' "$f"
      rm -f "$f.bak"
    done
    ;;
  nested)
    sed -i.bak 's|actions/setup-node@820762786026740c76f36085b0efc47a31fe5020 # v7.0.0|actions/setup-node@0000000000000000000000000000000000000000 # v7.1.0|' actions/setup/action.yml
    rm -f actions/setup/action.yml.bak
    ;;
  fail) echo "stub: simulated pinact failure" >&2; exit 1 ;;
  resolved-nothing)
    # Every lookup failed (a rate limit): nothing changed, nonzero exit.
    echo "ERROR failed to handle a line: get the latest version: 403 API rate limit" >&2
    exit 1
    ;;
  partial)
    # pinact updates what it can, then exits nonzero for the line it cannot pin.
    sed -i.bak 's|pnpm/action-setup@0977fd99725f1db4007ccb2928dbb4e90d06cc86 # v6.0.10|pnpm/action-setup@ea17c68df8912ef543352723c149a84f56e3d413 # v6.1.0|' .github/workflows/ci.yml
    rm -f .github/workflows/ci.yml.bak
    echo "ERROR failed to handle a line: action can't be pinned" >&2
    exit 1
    ;;
esac
SH
chmod +x "$stub_dir/pinact"
export PATH="$stub_dir:$PATH"

# 1. One outdated pin is reported as a single line with its file, line, old and new value.
expected='.github/workflows/ci.yml:8: pnpm/action-setup@0977fd99725f1db4007ccb2928dbb4e90d06cc86 # v6.0.10 -> pnpm/action-setup@ea17c68df8912ef543352723c149a84f56e3d413 # v6.1.0'
actual=$(PINACT_STUB_MODE=bump bash "$core" "$fixture")
if [[ "$actual" == "$expected" ]]; then
  pass "an outdated pin is reported with file, line, old and new value"
else
  fail "unexpected report:
$actual"
fi

# 2. The repository itself is never modified.
if cmp -s "$fixture/.github/workflows/ci.yml" "$test_root/ci.yml.orig"; then
  pass "the scanned repository is left untouched"
else
  fail "the scanned repository was modified"
fi

# 2b. A composite action outside .github is scanned and reported at its own path.
expected_nested='actions/setup/action.yml:5: actions/setup-node@820762786026740c76f36085b0efc47a31fe5020 # v7.0.0 -> actions/setup-node@0000000000000000000000000000000000000000 # v7.1.0'
actual=$(PINACT_STUB_MODE=nested bash "$core" "$fixture")
if [[ "$actual" == "$expected_nested" ]]; then
  pass "a composite action outside .github is reported at its own path"
else
  fail "nested action report: $actual"
fi

# 2c. A symlinked workflow is materialized in the copy, so pinact's write lands
#     in the copy and the link's real target stays untouched.
mkdir -p "$fixture/shared"
cp "$test_root/ci.yml.orig" "$fixture/shared/linked.yml"
ln -s ../../shared/linked.yml "$fixture/.github/workflows/linked.yml"
actual=$(PINACT_STUB_MODE=bump-all bash "$core" "$fixture")
if grep -q '^\.github/workflows/linked\.yml:8: ' <<<"$actual" && cmp -s "$fixture/shared/linked.yml" "$test_root/ci.yml.orig"; then
  pass "a symlinked workflow is scanned through a copy and its target stays untouched"
else
  fail "symlink case: report [$actual], target changed: $(cmp -s "$fixture/shared/linked.yml" "$test_root/ci.yml.orig" || echo yes)"
fi
rm "$fixture/.github/workflows/linked.yml"
rm -r "$fixture/shared"

# 2d. A workflow whose path contains a space is reported with its full path.
cp "$test_root/ci.yml.orig" "$fixture/.github/workflows/with space.yml"
actual=$(PINACT_STUB_MODE=bump-all bash "$core" "$fixture")
if grep -q '^\.github/workflows/with space\.yml:8: pnpm/action-setup@0977' <<<"$actual"; then
  pass "a path with a space is reported in full"
else
  fail "path with a space: $actual"
fi
rm "$fixture/.github/workflows/with space.yml"

# 3. Nothing is printed when every pin is current, and the exit code is still 0.
if actual=$(PINACT_STUB_MODE=current bash "$core" "$fixture") && [[ -z "$actual" ]]; then
  pass "a current repository prints nothing"
else
  fail "a current repository printed something or exited nonzero: $actual"
fi

# 4. A pinact failure is a nonzero exit, not an empty (clean-looking) report.
if PINACT_STUB_MODE=fail bash "$core" "$fixture" >/dev/null 2>&1; then
  fail "a pinact failure exited 0"
else
  pass "a pinact failure exits nonzero"
fi

# 5. A partial scan still reports the resolved lines and exits 3, so the
#    caller can show them and flag the repository at the same time.
status=0
actual=$(PINACT_STUB_MODE=partial bash "$core" "$fixture" 2>"$test_root/partial.err") || status=$?
if [[ "$status" == 3 && "$actual" == "$expected" ]] && grep -q "can't be pinned" "$test_root/partial.err"; then
  pass "a partial scan reports what resolved, relays pinact's error, and exits 3"
else
  fail "partial scan: exit $status, output: $actual, stderr: $(cat "$test_root/partial.err")"
fi

# 6. The notification adapter clears its notification only after a complete
#    scan; a partial scan that resolved nothing leaves the last one standing.
notify="$repo_root/actions/pinact-outdated/notify.sh"
git -C "$fixture" init -q
if out=$(cd "$fixture" && PINACT_STUB_MODE=current bash "$notify") && grep -q "notifications_to_delete" <<<"$out"; then
  pass "a complete clean scan clears the notification"
else
  fail "a complete clean scan did not clear the notification: $out"
fi
if out=$(cd "$fixture" && PINACT_STUB_MODE=resolved-nothing bash "$notify") && [[ -z "$out" ]]; then
  pass "a partial scan that resolved nothing keeps the last notification"
else
  fail "a partial scan that resolved nothing printed: $out"
fi
if out=$(cd "$fixture" && PINACT_STUB_MODE=partial bash "$notify") && grep -q "The scan was partial" <<<"$out" && grep -q "pnpm/action-setup" <<<"$out"; then
  pass "a partial scan with findings is marked partial in the notification"
else
  fail "a partial scan with findings printed: $out"
fi
# The notification with findings must be a document trunk can parse; ruby's
# YAML parser is the one the repository's own proof already relies on.
if command -v ruby >/dev/null 2>&1; then
  out=$(cd "$fixture" && PINACT_STUB_MODE=bump bash "$notify")
  if printf '%s\n' "$out" | ruby -ryaml -e 'd = YAML.safe_load(STDIN.read); n = d.fetch("notifications").first; abort unless n["commands"].first["run"].end_with?(" run") && n["message"].include?("pnpm/action-setup")'; then
    pass "a notification with findings parses as YAML with its command intact"
  else
    fail "a notification with findings did not parse as YAML:
$out"
  fi
else
  printf 'skip: ruby is not available, the notification YAML was not parsed\n'
fi

if ((failures > 0)); then
  printf '%d failure(s)\n' "$failures" >&2
  exit 1
fi
printf 'all pinact-outdated tests passed\n'
