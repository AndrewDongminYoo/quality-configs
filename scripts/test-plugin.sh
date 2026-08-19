#!/bin/bash

set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)
test_root=$(mktemp -d "${TMPDIR:-/tmp}/quality-configs-test.XXXXXX")
plugin_root="$test_root/plugin"
plugin_id="quality-configs-test-$$"

mkdir -p "$plugin_root"
cp "$repo_root/plugin.yaml" "$plugin_root/plugin.yaml"
cp -R "$repo_root/configs" "$plugin_root/configs"

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
      checkov@3.3.8
      cspell@10.0.1
      git-diff-check
      markdownlint@0.49.1
      osv-scanner@2.4.0
      prettier@3.9.6
      trufflehog@3.96.0
      yamllint@1.38.0
    ]
    missing = expected_linters - Array(data.dig("lint", "enabled"))
    abort "missing baseline linters: #{missing.join(", ")}" unless missing.empty?

    expected_runtimes = %w[node@22.22.3 python@3.10.8]
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

expect_failure() {
  local linter_id=$1
  local target_file=$2

  git add -- "$target_file"
  if trunk check --no-fix --no-progress --print-failures --verbose --filter="$linter_id" "$target_file"; then
    find .trunk/out -maxdepth 1 -type f -name '*.yaml' -print -exec sed -n '1,240p' {} \;
    find .trunk/logs -maxdepth 2 -type f -print -exec tail -n 160 {} \;
    printf 'Expected %s to reject %s\n' "$linter_id" "$target_file" >&2
    exit 1
  fi
}

expect_success() {
  local linter_id=$1
  local target_file=$2

  git add -- "$target_file"
  trunk check --no-fix --no-progress --filter="$linter_id" "$target_file"
}

baseline_root="$test_root/baseline"
initialize_repository "$baseline_root"
(
  cd "$baseline_root"
  trunk init --no-to-all --only-detected-linters --no-progress
  cp "$repo_root/profiles/baseline/trunk.yaml" .trunk/trunk.yaml
  trunk plugins add https://github.com/trunk-io/plugins v1.11.0 --id=trunk --no-progress
  trunk plugins add "$plugin_root" --id="$plugin_id" --no-progress
  QUALITY_CONFIGS_PLUGIN_YAML="$plugin_root/plugin.yaml" assert_resolved_baseline

  cp "$repo_root/tests/fixtures/violations/cspell.md" spell.md
  expect_failure cspell spell.md
  cp "$repo_root/tests/fixtures/clean/README.md" spell.md
  expect_success cspell spell.md

  cp "$repo_root/tests/fixtures/violations/markdownlint.md" markdown.md
  expect_failure markdownlint markdown.md
  cp "$repo_root/tests/fixtures/clean/README.md" markdown.md
  expect_success markdownlint markdown.md

  cp "$repo_root/tests/fixtures/violations/prettier.json" format.json
  expect_failure prettier format.json
  cp "$repo_root/tests/fixtures/clean/data.json" format.json
  expect_success prettier format.json

  cp "$repo_root/tests/fixtures/violations/yamllint.yaml" lint.yaml
  expect_failure yamllint lint.yaml
  cp "$repo_root/tests/fixtures/clean/config.yaml" lint.yaml
  expect_success yamllint lint.yaml

  cp "$repo_root/tests/fixtures/violations/cspell.md" spell.md
  cp "$repo_root/tests/fixtures/overrides/cspell.config.yaml" cspell.config.yaml
  expect_success cspell spell.md
)

for profile_name in flutter react-native next; do
  profile_root="$test_root/profile-$profile_name"
  initialize_repository "$profile_root"
  mkdir -p "$profile_root/.trunk"
  cp "$repo_root/profiles/$profile_name/trunk.yaml" "$profile_root/.trunk/trunk.yaml"
  if [[ -f "$repo_root/profiles/$profile_name/prettier.config.mjs" ]]; then
    cp "$repo_root/profiles/$profile_name/prettier.config.mjs" "$profile_root/prettier.config.mjs"
  fi
  (
    cd "$profile_root"
    trunk plugins add https://github.com/trunk-io/plugins v1.11.0 --id=trunk --no-progress
    trunk plugins add "$plugin_root" --id="$plugin_id" --no-progress
    trunk config print --no-progress --color=false >/dev/null
  )
done

flutter_root="$test_root/profile-flutter"
(
  cd "$flutter_root"
  cp "$repo_root/tests/fixtures/violations/markdown-dart.md" dart.md
  expect_failure prettier dart.md
  cp "$repo_root/tests/fixtures/clean/markdown-dart.md" dart.md
  expect_success prettier dart.md
)

next_root="$test_root/profile-next"
(
  cd "$next_root"
  cp "$repo_root/tests/fixtures/violations/svgo.svg" optimize.svg
  expect_failure svgo optimize.svg
  trunk fmt --no-progress --filter=svgo optimize.svg
  expect_success svgo optimize.svg

  cp "$repo_root/tests/fixtures/violations/tailwind.jsx" tailwind.jsx
  expect_failure prettier tailwind.jsx
  cp "$repo_root/tests/fixtures/clean/tailwind.jsx" tailwind.jsx
  expect_success prettier tailwind.jsx
)

printf 'Plugin and profile verification passed.\n'
