#!/bin/bash

set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)
test_root=$(mktemp -d "${TMPDIR:-/tmp}/quality-configs-test.XXXXXX")
plugin_root="$test_root/plugin"
plugin_id="quality-configs-test-$$"

mkdir -p "$plugin_root"
cp "$repo_root/plugin.yaml" "$plugin_root/plugin.yaml"
cp -R "$repo_root/configs" "$plugin_root/configs"
# Trunk discovers linters/<name>/plugin.yaml and runtimes/<name>/plugin.yaml on
# its own. The staged copy must carry them, or the test resolves a different
# plugin than consumers get. The standalone scenario removes trunk-io/plugins
# so the bundled definitions win each name collision.
cp -R "$repo_root/linters" "$plugin_root/linters"
cp -R "$repo_root/runtimes" "$plugin_root/runtimes"
# Actions resolve the same way: actions/<id>/plugin.yaml, run from that directory
# through ${cwd}, so the staged copy must carry the script beside its definition.
cp -R "$repo_root/actions" "$plugin_root/actions"

cleanup() {
  if [[ -n "${test_root:-}" && -d "$test_root" && "$(basename "$test_root")" == quality-configs-test.* ]]; then
    rm -rf "$test_root"
  fi
}

trap cleanup EXIT

initialize_repository() {
  local consumer_root=$1
  local marker_name="$plugin_id-${consumer_root##*/}.yaml"

  mkdir -p "$consumer_root"
  git init -q -b main "$consumer_root"
  git -C "$consumer_root" config user.name "Quality Configs Test"
  git -C "$consumer_root" config user.email "quality-configs-test@example.invalid"
  cp "$repo_root/tests/fixtures/clean/README.md" "$consumer_root/README.md"
  cp "$repo_root/tests/fixtures/clean/config.yaml" "$consumer_root/config.yaml"
  cp "$repo_root/tests/fixtures/clean/data.json" "$consumer_root/data.json"
  cp "$repo_root/tests/fixtures/clean/icon.svg" "$consumer_root/icon.svg"
  cp "$plugin_root/plugin.yaml" "$consumer_root/$marker_name"
  git -C "$consumer_root" add README.md config.yaml data.json icon.svg "$marker_name"
  git -C "$consumer_root" commit -q -m "test: add clean fixtures"
}

assert_resolved_baseline() {
  trunk config print --no-progress --color=false | ruby -ryaml -e '
    raw = STDIN.read
    yaml_start = raw.index(/^version:/)
    abort "resolved config did not contain a YAML document: #{raw.lines.first(3).inspect}" unless yaml_start
    data = YAML.safe_load(raw[yaml_start..], aliases: true)
    abort "resolved config was not a mapping" unless data.is_a?(Hash)
    expected_linters = %w[
      actionlint@1.7.12
      checkov@3.3.16
      cspell@10.2.0
      git-diff-check
      grype@0.110.0
      markdownlint@0.49.1
      osv-scanner@2.4.0
      pinact@4.0.0
      prettier@3.9.6
      trufflehog@3.96.0
      yamllint@1.38.0
    ]
    missing = expected_linters - Array(data.dig("lint", "enabled"))
    abort "missing baseline linters: #{missing.join(", ")}" unless missing.empty?

    expected_runtimes = %w[node@22.22.3 python@3.14.4]
    actual_runtimes = Array(data.dig("runtimes", "enabled"))
    missing_runtimes = expected_runtimes - actual_runtimes
    unless missing_runtimes.empty?
      warn "plugin source:\n#{File.read(ENV.fetch("QUALITY_CONFIGS_PLUGIN_YAML"))}"
      warn "consumer config:\n#{File.read(".trunk/trunk.yaml")}"
      abort "missing baseline runtimes: #{missing_runtimes.join(", ")}; actual: #{actual_runtimes.inspect}"
    end

    exported = Array(data.dig("lint", "exported_configs")).flat_map { |entry| Array(entry["configs"]) }
    expected_configs = %w[
      configs/cspell.config.yaml
      configs/.markdownlint.yaml
      configs/prettier.config.mjs
      configs/svgo.config.mjs
      configs/.yamllint.yaml
    ]
    missing_configs = expected_configs - exported
    abort "missing exported configs: #{missing_configs.join(", ")}" unless missing_configs.empty?
  '
}

# A consumer merges a profile into its existing .trunk/trunk.yaml, so the
# generated plugin sources survive. Copying the profile over the file would
# discard them, and the runtime pins resolve only through trunk-io/plugins.
apply_profile() {
  local profile_name=$1
  local target_file=$2

  awk '
    /^runtimes:$/ && !inserted {
      print "plugins:"
      print "  sources:"
      print "    - id: trunk"
      print "      ref: v1.11.0"
      print "      uri: https://github.com/trunk-io/plugins"
      print ""
      inserted = 1
    }
    { print }
  ' "$repo_root/profiles/$profile_name/trunk.yaml" >"$target_file"
}

expect_failure() {
  local linter_id=$1
  local target_file=$2
  local expected_issue=${3:-}
  local expected_message=${4:-}
  local expected_location=${5:-}
  local output_file="$test_root/${linter_id//\//-}-failure.log"

  git add -- "$target_file"
  if trunk check --no-fix --no-progress --color=false --print-failures --verbose --cache=false --filter="$linter_id" "$target_file" 2>&1 | tee "$output_file"; then
    find .trunk/out -maxdepth 1 -type f -name '*.yaml' -print -exec sed -n '1,240p' {} \;
    find .trunk/logs -maxdepth 2 -type f -print -exec tail -n 160 {} \;
    printf 'Expected %s to reject %s\n' "$linter_id" "$target_file" >&2
    exit 1
  fi

  if ! grep -Eq '(^|[^0-9])[1-9][0-9]* (new |existing )?(lint|security) issues?' "$output_file"; then
    printf '%s rejected %s without reporting a lint or security issue\n' "$linter_id" "$target_file" >&2
    exit 1
  fi

  if grep -Eq 'Some tools failed to run|(^|[^0-9])[1-9][0-9]* failures?' "$output_file"; then
    printf '%s rejected %s because a tool failed\n' "$linter_id" "$target_file" >&2
    exit 1
  fi

  if [[ -n "$expected_issue" ]] && ! grep -Fq -- "$expected_issue" "$output_file"; then
    printf '%s rejected %s without the expected issue marker: %s\n' "$linter_id" "$target_file" "$expected_issue" >&2
    exit 1
  fi

  if [[ -n "$expected_message" ]] && ! grep -Fq -- "$expected_message" "$output_file"; then
    printf '%s rejected %s without the expected message: %s\n' "$linter_id" "$target_file" "$expected_message" >&2
    exit 1
  fi

  if [[ -n "$expected_location" ]] && ! grep -Fq -- "$expected_location:" "$output_file"; then
    printf '%s rejected %s without reporting the expected location: %s\n' "$linter_id" "$target_file" "$expected_location" >&2
    exit 1
  fi
}

expect_success() {
  local linter_id=$1
  local target_file=$2

  git add -- "$target_file"
  trunk check --no-fix --no-progress --cache=false --filter="$linter_id" "$target_file"
}

expect_format_failure() {
  local linter_id=$1
  local target_file=$2
  local output_file="$test_root/${linter_id//\//-}-format-failure.log"

  git add -- "$target_file"
  if trunk fmt --no-fix --diff=full --no-progress --color=false --filter="$linter_id" "$target_file" 2>&1 | tee "$output_file"; then
    printf 'Expected %s to reject the formatting of %s\n' "$linter_id" "$target_file" >&2
    exit 1
  fi

  if ! grep -Eq '(^|[^0-9])[1-9][0-9]* (new |existing )?unformatted files?' "$output_file"; then
    printf '%s rejected %s without reporting an unformatted file\n' "$linter_id" "$target_file" >&2
    exit 1
  fi

  if grep -Eq 'Some tools failed to run|(^|[^0-9])[1-9][0-9]* failures?' "$output_file"; then
    printf '%s rejected %s because a tool failed\n' "$linter_id" "$target_file" >&2
    exit 1
  fi
}

expect_format_success() {
  local linter_id=$1
  local target_file=$2

  git add -- "$target_file"
  trunk fmt --no-fix --no-progress --filter="$linter_id" "$target_file"
}

# The security-review-findings action is an adapter around a hook shipped by a
# separate Claude Code plugin, so what this script can prove is the adapter's
# contract: the action is defined and enabled for the consumer, it is silent
# when nothing points at that plugin, and it relays the hook's stdout when
# something does. The hook itself is tested in its own repository.
expect_action_enabled() {
  local action_id=$1
  local output_file="$test_root/actions-list.log"

  trunk actions list --no-progress --color=false 2>&1 | tee "$output_file" >/dev/null
  if ! awk '/^Enabled actions:/{on=1; next} /^Disabled actions:/{on=0} on' "$output_file" | grep -Fq "  $action_id"; then
    printf 'Expected %s among the enabled actions\n' "$action_id" >&2
    exit 1
  fi
}

expect_action_silent() {
  local action_id=$1
  local output_file="$test_root/${action_id}-silent.log"

  # An empty config dir: no plugin manifest, so the adapter must exit 0 quietly.
  # The action's ${env.CLAUDE_CONFIG_DIR} forward reads the environment the
  # trunk daemon was started with, so the daemon is stopped first and restarts
  # under this invocation's variable (otherwise the run silently uses the
  # authoring machine's real ~/.claude).
  trunk daemon shutdown --no-progress --color=false >/dev/null 2>&1 || true
  if ! CLAUDE_CONFIG_DIR="$test_root/empty-claude" trunk actions run "$action_id" --no-progress --color=false >"$output_file" 2>&1; then
    printf '%s failed instead of staying silent without a plugin\n' "$action_id" >&2
    cat "$output_file" >&2
    exit 1
  fi
  if grep -Fq 'Automatic security review' "$output_file"; then
    printf '%s printed findings with no plugin installed\n' "$action_id" >&2
    exit 1
  fi
}

expect_action_prints() {
  local action_id=$1
  local output_file="$test_root/${action_id}-prints.log"
  local fake_claude="$test_root/fake-claude"
  local fake_plugin="$fake_claude/plugins/cache/cc-agents-kit/guard-hooks/0.0.0-test"

  # A manifest that points at a stand-in hook, which records what it was
  # called with; the adapter must find it through installed_plugins.json and
  # pass --print plus the repository root. The stand-in writes its arguments to
  # a file as well as stdout, so "the adapter never ran the hook" and "trunk did
  # not relay the hook's stdout" fail as two different messages.
  local called_file="$test_root/${action_id}-called.log"
  mkdir -p "$fake_plugin/hooks" "$fake_claude/plugins"
  cat >"$fake_plugin/hooks/security-review-findings.sh" <<STAND_IN
#!/usr/bin/env bash
printf '%s %s\n' "\$1" "\$2" >"$called_file"
printf 'Automatic security review stand-in: %s %s\n' "\$1" "\$2"
STAND_IN
  printf '{"version":2,"plugins":{"guard-hooks@cc-agents-kit":[{"installPath":"%s"}]}}\n' "$fake_plugin" >"$fake_claude/plugins/installed_plugins.json"

  # Same daemon restart as expect_action_silent, for the same reason.
  trunk daemon shutdown --no-progress --color=false >/dev/null 2>&1 || true
  if ! CLAUDE_CONFIG_DIR="$fake_claude" trunk actions run "$action_id" --no-progress --color=false >"$output_file" 2>&1; then
    printf '%s failed with a plugin installed\n' "$action_id" >&2
    cat "$output_file" >&2
    exit 1
  fi
  if [[ ! -f "$called_file" ]]; then
    printf '%s never ran the plugin hook: CLAUDE_CONFIG_DIR did not reach the action, or the adapter did not resolve the manifest\n' "$action_id" >&2
    cat "$output_file" >&2
    exit 1
  fi
  if ! grep -Fqx -- "--print $(git rev-parse --show-toplevel)" "$called_file"; then
    printf '%s called the plugin hook with the wrong arguments (want --print and the repository root): %s\n' "$action_id" "$(cat "$called_file")" >&2
    exit 1
  fi
  if ! grep -Fq "Automatic security review stand-in: --print $(git rev-parse --show-toplevel)" "$output_file"; then
    printf '%s ran the plugin hook but trunk did not relay its stdout\n' "$action_id" >&2
    cat "$output_file" >&2
    exit 1
  fi
}

assert_generated_output_contains() {
  local expected_text=$1

  if ! grep -Fq -- "$expected_text" .trunk/out/*.yaml; then
    printf 'Generated Trunk output did not contain: %s\n' "$expected_text" >&2
    exit 1
  fi
}

baseline_root="$test_root/baseline"
initialize_repository "$baseline_root"
(
  cd "$baseline_root"
  trunk init --no-to-all --only-detected-linters --no-progress
  apply_profile baseline .trunk/trunk.yaml
  trunk plugins add "$plugin_root" --id="$plugin_id" --no-progress
  QUALITY_CONFIGS_PLUGIN_YAML="$plugin_root/plugin.yaml" assert_resolved_baseline

  expect_action_enabled security-review-findings
  expect_action_silent security-review-findings
  expect_action_prints security-review-findings

  cp "$repo_root/tests/fixtures/violations/cspell.md" spell.md
  expect_failure cspell spell.md
  cp "$repo_root/tests/fixtures/clean/README.md" spell.md
  expect_success cspell spell.md
  cp "$repo_root/tests/fixtures/clean/cspell-shared.md" spell.md
  expect_success cspell spell.md

  cp "$repo_root/tests/fixtures/violations/markdownlint.md" markdown.md
  expect_failure markdownlint markdown.md
  cp "$repo_root/tests/fixtures/clean/README.md" markdown.md
  expect_success markdownlint markdown.md

  cp "$repo_root/tests/fixtures/violations/prettier.json" format.json
  expect_format_failure prettier format.json
  cp "$repo_root/tests/fixtures/clean/data.json" format.json
  expect_format_success prettier format.json

  cp "$repo_root/tests/fixtures/violations/yamllint.yaml" lint.yaml
  expect_failure yamllint lint.yaml
  cp "$repo_root/tests/fixtures/clean/config.yaml" lint.yaml
  expect_success yamllint lint.yaml

  cp "$repo_root/tests/fixtures/violations/cspell.md" spell.md
  cp "$repo_root/tests/fixtures/overrides/cspell.config.yaml" cspell.config.yaml
  expect_success cspell spell.md

  if [[ ! -f "$repo_root/configs/cspell/vgv.config.yaml" ]]; then
    printf 'Missing optional VGV CSpell config: %s\n' "$repo_root/configs/cspell/vgv.config.yaml" >&2
    exit 1
  fi
  awk -v shared_config="$plugin_root/configs/cspell.config.yaml" -v vgv_config="$repo_root/configs/cspell/vgv.config.yaml" '
    { gsub("__SHARED_CONFIG__", shared_config) }
    { gsub("__VGV_CONFIG__", vgv_config) }
    { print }
  ' "$repo_root/tests/fixtures/overrides/cspell-shared-vgv.config.yaml" >cspell.config.yaml
  cp "$repo_root/tests/fixtures/violations/cspell.md" spell.md
  expect_success cspell spell.md
  cp "$repo_root/tests/fixtures/clean/cspell-shared.md" spell.md
  expect_success cspell spell.md
  cp "$repo_root/tests/fixtures/violations/cspell-vgv.md" spell.md
  expect_failure cspell spell.md cspell/error "Forbidden word (meta-data)" spell.md
  cp "$repo_root/tests/fixtures/clean/AndroidManifest.xml" AndroidManifest.xml
  expect_success cspell AndroidManifest.xml

  if grep -Eq 'very_good_dictionaries/(refs/heads/)?main/' "$repo_root/configs/cspell/vgv.config.yaml"; then
    printf 'Optional VGV CSpell config used a mutable main URL\n' >&2
    exit 1
  fi
)

# A consumer that drops trunk-io/plugins depends on the bundled runtime, and on
# it alone: python@3.14.4 is absent from the CLI's built-in definitions, so
# without runtimes/python the config is rejected before any linter runs. This is
# also the only configuration in which the bundled linter definitions win, since
# nothing is left to collide with their names.
#
# The source is written into the file rather than added with `trunk plugins add`.
# That command needs a config it can already resolve, and a profile pinning a
# runtime only this plugin defines is not resolvable until the plugin is in the
# sources, so the bootstrap has to happen in one write.
standalone_root="$test_root/standalone"
initialize_repository "$standalone_root"
mkdir -p "$standalone_root/.trunk"
awk -v id="$plugin_id" -v path="$plugin_root" '
  /^runtimes:$/ && !inserted {
    print "plugins:"
    print "  sources:"
    print "    - id: " id
    print "      local: " path
    print ""
    inserted = 1
  }
  { print }
  END {
    print ""
    print "lint:"
    print "  enabled:"
    print "    - dart@3.10.8"
    print "    - grype@0.110.0"
    print "    - osv-scanner@2.4.0"
    print "    - pinact@4.0.0"
    print "    - toml-tidy@0.4.1"
  }
' "$repo_root/profiles/baseline/trunk.yaml" >"$standalone_root/.trunk/trunk.yaml"
(
  cd "$standalone_root"
  trunk config print --no-progress --color=false >/dev/null

  mkdir -p lib
  cp "$repo_root/tests/fixtures/violations/main.dart" lib/main.dart
  expect_failure dart lib/main.dart dart/undefined_identifier
  assert_generated_output_contains 'analyze --no-fatal-warnings --format=json'
  cp "$repo_root/tests/fixtures/clean/main.dart" lib/main.dart
  expect_success dart lib/main.dart

  cp "$repo_root/tests/fixtures/violations/pyproject.toml" pyproject.toml
  expect_format_failure toml-tidy pyproject.toml
  cp "$repo_root/tests/fixtures/clean/pyproject.toml" pyproject.toml
  expect_format_success toml-tidy pyproject.toml

  mkdir -p .github/actions/fixture
  cp "$repo_root/tests/fixtures/violations/action.yaml" .github/actions/fixture/action.yaml
  export PINACT_DISABLE_GH_AUTH=1
  expect_failure pinact .github/actions/fixture/action.yaml pinact/parse-error "action can't be pinned"
  assert_generated_output_contains '/plugin/linters/pinact/pinact_run.py'
  cp "$repo_root/tests/fixtures/clean/action.yaml" .github/actions/fixture/action.yaml
  expect_success pinact .github/actions/fixture/action.yaml
  unset PINACT_DISABLE_GH_AUTH

  cp "$repo_root/tests/fixtures/violations/Gemfile.lock" Gemfile.lock
  expect_failure grype Gemfile.lock grype/ "vulnerability in gem package: rack" Gemfile.lock
  assert_generated_output_contains '/plugin/linters/grype/grype_to_sarif.py'
  cp "$repo_root/tests/fixtures/clean/Gemfile.lock" Gemfile.lock
  expect_success grype Gemfile.lock

  cp "$repo_root/tests/fixtures/violations/Gemfile.lock" Gemfile.lock
  expect_failure osv-scanner Gemfile.lock osv-scanner/ "Current version is vulnerable: 2.2.6.2." Gemfile.lock
  cp "$repo_root/tests/fixtures/clean/Gemfile.lock" Gemfile.lock
  expect_success osv-scanner Gemfile.lock
)

for profile_name in flutter react-native next; do
  profile_root="$test_root/profile-$profile_name"
  initialize_repository "$profile_root"
  mkdir -p "$profile_root/.trunk"
  apply_profile "$profile_name" "$profile_root/.trunk/trunk.yaml"
  if [[ -f "$repo_root/profiles/$profile_name/prettier.config.mjs" ]]; then
    cp "$repo_root/profiles/$profile_name/prettier.config.mjs" "$profile_root/prettier.config.mjs"
  fi
  (
    cd "$profile_root"
    trunk plugins add "$plugin_root" --id="$plugin_id" --no-progress
    trunk config print --no-progress --color=false >/dev/null
  )
done

flutter_root="$test_root/profile-flutter"
(
  cd "$flutter_root"
  cp "$repo_root/tests/fixtures/violations/markdown-dart.md" dart.md
  expect_format_failure prettier dart.md
  cp "$repo_root/tests/fixtures/clean/markdown-dart.md" dart.md
  expect_format_success prettier dart.md
)

next_root="$test_root/profile-next"
(
  cd "$next_root"
  cp "$repo_root/tests/fixtures/violations/svgo.svg" optimize.svg
  expect_format_failure svgo optimize.svg
  trunk fmt --no-progress --filter=svgo optimize.svg
  expect_format_success svgo optimize.svg

  cp "$repo_root/tests/fixtures/violations/tailwind.jsx" tailwind.jsx
  expect_format_failure prettier tailwind.jsx
  cp "$repo_root/tests/fixtures/clean/tailwind.jsx" tailwind.jsx
  expect_format_success prettier tailwind.jsx
)

printf 'Plugin and profile verification passed.\n'
