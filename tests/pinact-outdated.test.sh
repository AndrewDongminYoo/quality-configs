#!/bin/bash
# Unit test for actions/pinact-outdated/pinact-outdated.sh and the trunk.yaml
# filter of scripts/action-pin-sweep.sh. pinact itself is replaced by a stub on
# PATH, so the test needs no network and no GitHub token: what is under test is
# the copy-then-diff around pinact and the shape of the reported lines, not
# pinact's own resolution of the latest release.

set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)
core="$repo_root/actions/pinact-outdated/pinact-outdated.sh"
sweep="$repo_root/scripts/action-pin-sweep.sh"
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

# 6. The sweep only covers repositories whose trunk.yaml enables pinact.
enforcing=$(
  cat <<'YAML'
version: 0.1
lint:
  disabled:
    - dart
  enabled:
    - actionlint@1.7.12
    - pinact@4.1.1
YAML
)
withheld=$(
  cat <<'YAML'
version: 0.1
lint:
  disabled:
    - dart
    - pinact
  enabled:
    - actionlint@1.7.12
YAML
)
if bash "$sweep" --enforces-pinact <<<"$enforcing"; then
  pass "a trunk.yaml that enables pinact is selected"
else
  fail "a trunk.yaml that enables pinact was not selected"
fi
if bash "$sweep" --enforces-pinact <<<"$withheld"; then
  fail "a trunk.yaml that disables pinact was selected"
else
  pass "a trunk.yaml that disables pinact is skipped"
fi

# A consumer can inherit an enabled pinact from a plugin or profile and switch
# it off locally; the disabled entry is the repository's decision.
overridden=$(
  cat <<'YAML'
version: 0.1
lint:
  disabled:
    - pinact
  enabled:
    - actionlint@1.7.12
    - pinact@4.0.0
YAML
)
if bash "$sweep" --enforces-pinact <<<"$overridden"; then
  fail "a trunk.yaml that both enables and disables pinact was selected"
else
  pass "a disabled entry overrides an inherited enabled one"
fi

# 7. The notification adapter clears its notification only after a complete
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

# 8. A sweep in which every scan failed exits nonzero instead of reporting
#    every pin as current. The gh stub lists one repository that enforces
#    pinact and then fails its clone.
gh_all_fail_dir="$test_root/gh-all-fail"
mkdir -p "$gh_all_fail_dir"
cat >"$gh_all_fail_dir/gh" <<'SH'
#!/bin/bash
case "$1 $2" in
  "repo list") printf 'only-repo\tfalse\n' ;;
  "api repos/some-owner/only-repo/contents/.trunk/trunk.yaml")
    printf 'version: 0.1\nlint:\n  enabled:\n    - pinact@4.1.1\n' | base64 ;;
  "repo clone") echo "gh: clone failed" >&2; exit 1 ;;
  *) echo "stub: unexpected gh $*" >&2; exit 64 ;;
esac
SH
chmod +x "$gh_all_fail_dir/gh"
if sweep_out=$(PATH="$gh_all_fail_dir:$PATH" bash "$sweep" some-owner 2>"$test_root/sweep-all-fail.err"); then
  fail "the sweep exited 0 although no repository was scanned: $sweep_out"
elif grep -q "No repository was scanned completely" <<<"$sweep_out" && grep -q "clone failed" <<<"$sweep_out"; then
  pass "a sweep in which every scan failed exits nonzero and lists the failures"
else
  fail "unexpected all-failed report: $sweep_out / $(cat "$test_root/sweep-all-fail.err")"
fi

# 9. A failed repository listing stops the sweep instead of producing an
#    "every pin is current" report from an empty loop.
gh_stub_dir="$test_root/gh-bin"
mkdir -p "$gh_stub_dir"
cat >"$gh_stub_dir/gh" <<'SH'
#!/bin/bash
echo "gh: HTTP 401: Bad credentials" >&2
exit 1
SH
chmod +x "$gh_stub_dir/gh"
if sweep_out=$(PATH="$gh_stub_dir:$PATH" bash "$sweep" some-owner 2>"$test_root/sweep.err"); then
  fail "the sweep exited 0 although the repository listing failed: $sweep_out"
elif grep -q "listing some-owner's repositories failed" "$test_root/sweep.err"; then
  pass "a failed repository listing stops the sweep"
else
  fail "the sweep failed for another reason: $(cat "$test_root/sweep.err")"
fi

if ((failures > 0)); then
  printf '%d failure(s)\n' "$failures" >&2
  exit 1
fi
printf 'all pinact-outdated tests passed\n'
