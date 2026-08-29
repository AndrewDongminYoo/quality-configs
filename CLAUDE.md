# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

`AGENTS.md` owns the editing rules, the documentation layout, and the release verification block; read it and do not restate it here.
`docs/specs/2026-08-19-quality-configs-design.md` records why each baseline decision was made.

## What This Repository Is

There is no application code here.
The deliverable is a Trunk external plugin that other repositories consume by tag or SHA, plus consumer-side overlay files that a human copies into a target repository.
`README.md` documents the consumer-facing rollout flow.

## The Duplication Is Load-Bearing

`trunk init` writes consumer-local runtime, action, and linter entries, and consumer-local `.trunk/trunk.yaml` overrides the remote plugin.
The root `plugin.yaml` therefore cannot enforce the runtime and action contract on its own.
That is why every file under `profiles/` repeats `runtimes.enabled`, the identical `actions` block, and `cli.version`.

Do not deduplicate those blocks.
Removing the repeated `actions` block from a profile silently re-enables the generated `trunk-fmt-pre-commit` action in consumer repositories, which is the one mutation this baseline exists to withhold.

## Version Pins Move Together

A linter or runtime version appears in three independent places, and all three must change in the same commit:

1. `plugin.yaml` under `lint.enabled` and `runtimes.enabled`.
2. Each `profiles/*/trunk.yaml` that re-declares the same tool.
3. The hardcoded `expected_linters` and `expected_runtimes` arrays inside the Ruby block in `scripts/test-plugin.sh`.

Bumping the plugin alone fails the script; changing the script alone produces a vacuous pass.
`cli.version` has the same shape across the four profiles and `.trunk/trunk.yaml`, and must stay compatible with `required_trunk_version` in `plugin.yaml`.

## Every New Linter Needs a Canary Pair

CSpell exits with code 1 both for spelling findings and for an engine error, so an incompatible Node runtime once produced a false clean result rather than a failure.
`scripts/test-plugin.sh` therefore pairs `expect_failure` against a deliberate violation with `expect_success` against a clean file for every linter it trusts.
Adding a linter to the baseline means adding a fixture pair under `tests/fixtures/violations/` and `tests/fixtures/clean/` and wiring both calls into the script.
`node@22.22.3` is not an arbitrary pin: CSpell 10.0.1 requires Node 22.18.0 or newer.

## This Repository Consumes Its Own Plugin

`.trunk/trunk.yaml` declares the plugin source as `local: .`, so editing `plugin.yaml` or anything under `configs/` changes this repository's own lint results immediately.
Its two ignore blocks are deliberate:

- `tests/fixtures/**` is excluded because those files hold intentional violations.
- `profiles/flutter/**` and `profiles/next/**` are excluded from Prettier because Prettier resolves the nearest config file, and those profile configs load plugins that the root run cannot supply.

## Verification

```bash
./scripts/test-plugin.sh
```

The script builds temporary Git repositories under `TMPDIR`, adds this checkout as a uniquely identified local plugin, and exercises the baseline plus all three stack profiles from isolated consumers.
Run it whenever `plugin.yaml`, an exported config under `configs/`, or a profile changes.
Trunk's target selection is Git-aware, so stage a new or changed file with `git add` before running `trunk check` on it, exactly as the script does.
