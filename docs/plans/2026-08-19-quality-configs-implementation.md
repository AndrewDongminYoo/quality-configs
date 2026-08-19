# Quality Configs Implementation Plan

## Scope

The implementation phase originally excluded release operations, a custom installer, and consumer migration.
A later delivery authorization covers semantic commits, pushing `main`, and creating the annotated `v0.1.0` tag; custom installation tooling and consumer migration remain out of scope.

## Task 1: Create the Independent Repository

Files: `.editorconfig`, `.gitignore`, `AGENTS.md`, `LICENSE`, `README.md`, and `docs/`.

1. Initialize `/Volumes/dongminyu/Development/01_personal/quality-configs` as a new Git repository on `main`.
2. Record the design, source inventory, usage contract, and repository-local editing rules.

Verify:

```bash
git -C /Volumes/dongminyu/Development/01_personal/quality-configs rev-parse --show-toplevel
git -C /Volumes/dongminyu/Development/01_personal/quality-configs branch --show-current
```

## Task 2: Implement the Universal Plugin

Files: `plugin.yaml` and `configs/`.

1. Add the universal runtimes, linters, safe ignores, exported configs, and non-formatting actions.
2. Add focused shared configs for CSpell, Markdownlint, Prettier, SVGO, and yamllint.

Verify through the isolated consumer proof in Task 4.

## Task 3: Implement Stack Profiles

Files: `profiles/baseline/trunk.yaml`, `profiles/flutter/trunk.yaml`, `profiles/flutter/analysis_options.yaml`, `profiles/flutter/prettier.config.mjs`, `profiles/react-native/trunk.yaml`, `profiles/next/trunk.yaml`, and `profiles/next/prettier.config.mjs`.

1. Add the mobile safety ignores and ecosystem-owned linter selections.
2. Add the minimal Flutter analyzer template based on `very_good_analysis`.
3. Keep disputed or destructive settings local or explicitly disabled.

Verify each overlay by merging it into an isolated initialized consumer and running `trunk config print`.

## Task 4: Prove Reuse

1. Initialize an isolated temporary Git repository.
2. Add this repository as a local Trunk plugin.
3. Print the resolved config and confirm all baseline linters and exported configs are present.
4. Add one intentional violation for CSpell, Markdownlint, Prettier, yamllint, and SVGO where applicable.
5. Require each linter to report its canary, remove the canaries, and require a clean rerun.
6. Add a consumer-local CSpell config and prove that it overrides the exported default.

Verify:

```bash
./scripts/test-plugin.sh
```

## Completion Gate

Report exact commands and failures.
Do not claim the repository is publishable until all structural and isolated-consumer checks pass.
