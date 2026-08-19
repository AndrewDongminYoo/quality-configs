# Quality Configs

Reusable Trunk configuration for repositories owned by `AndrewDongminYoo`.
The repository follows the public plugin pattern used by [`trunk-io/configs`](https://github.com/trunk-io/configs) while keeping stack policy explicit and conservative.

## Status

The public GitHub repository contains the reusable baseline.
Published consumers must use an immutable release tag or commit SHA.
Migration of existing projects remains a separate, repository-by-repository task.

## Design

The root [`plugin.yaml`](./plugin.yaml) provides universal linters and exported linter configs.
The local runtime and action contract lives in [`profiles/baseline`](./profiles/baseline), while stack-specific settings live in [`profiles/flutter`](./profiles/flutter), [`profiles/react-native`](./profiles/react-native), and [`profiles/next`](./profiles/next).

Trunk does not select an external plugin or a named profile during `trunk init`.
The supported flow is to initialize Trunk, add the shared plugin, and then merge exactly one explicit profile overlay into the consumer repository.
The overlay must replace the generated Node, Python, and action entries because consumer-local configuration overrides the remote plugin.
This avoids a custom YAML-merging CLI in the initial baseline.

## Universal Baseline

The plugin enables:

- `actionlint`
- `checkov`
- `cspell`
- `git-diff-check`
- `markdownlint`
- `osv-scanner`
- `prettier`
- `trufflehog`
- `yamllint`

It exports shared configuration for Markdownlint, CSpell, Prettier, SVGO, and yamllint.
SVGO is exported but is only enabled by the Next profile.

The plugin enables the non-formatting `trunk-check-pre-push` gate and update notifications.
It deliberately does not enable `trunk-fmt-pre-commit`; preview formatter changes before opting into automatic mutation in a consumer repository.

## Local Evaluation

To evaluate a local checkout before a release, add it to an initialized test repository by absolute local path:

```bash
trunk init
# Merge profiles/baseline/trunk.yaml into .trunk/trunk.yaml.
trunk plugins add /Volumes/dongminyu/Development/01_personal/quality-configs --id=quality-configs
trunk config print
```

For published consumers, use an immutable release tag or commit SHA:

```bash
trunk init
# Merge exactly one profile into .trunk/trunk.yaml.
trunk plugins add https://github.com/AndrewDongminYoo/quality-configs <release-tag-or-sha> --id=quality-configs
```

Do not source `main` from consumer repositories.

## Profiles

Choose exactly one profile and merge its `trunk.yaml` into the consumer's `.trunk/trunk.yaml` after `trunk init` and before adding the root plugin.
The consumer configuration has the final override position, so project-specific ignores and versions remain local.

### Baseline

Use [`profiles/baseline/trunk.yaml`](./profiles/baseline/trunk.yaml) for repositories that do not match the three stack profiles.
It pins a CSpell-compatible Node 22 LTS runtime and keeps the mutating formatter hook disabled.

### Flutter

Merge [`profiles/flutter/trunk.yaml`](./profiles/flutter/trunk.yaml).
Copy [`profiles/flutter/analysis_options.yaml`](./profiles/flutter/analysis_options.yaml) only for a new project, or review it as a diff against an existing analyzer configuration.
The analyzer template requires `very_good_analysis` in the consumer's `dev_dependencies`.
Bloc-specific linting remains project-local because it was not common across the surveyed Flutter repositories.
Copy [`profiles/flutter/prettier.config.mjs`](./profiles/flutter/prettier.config.mjs) to enable `prettier-plugin-markdown-dart` for fenced Dart blocks.
Trunk supplies plugin version `1.1.1`, while the consumer environment must provide a Dart or Flutter SDK with `dart` on `PATH`.
Install the same plugin in the consumer when editor integration or project-owned Prettier scripts also need it.

### React Native

Merge [`profiles/react-native/trunk.yaml`](./profiles/react-native/trunk.yaml).
The profile uses `eslint@SYSTEM`, so the consumer must provide its own compatible ESLint binary and configuration.
SVGO, oxipng, and dotenv-linter remain disabled because they can rewrite mobile assets or Xcode environment files.

### Next.js

Merge [`profiles/next/trunk.yaml`](./profiles/next/trunk.yaml).
The profile uses the consumer's ESLint and enables SVGO without enabling automatic formatting hooks.
Review `trunk fmt --no-fix --diff=full --filter=svgo` before accepting SVG rewrites.
For Tailwind projects, copy [`profiles/next/prettier.config.mjs`](./profiles/next/prettier.config.mjs) to the consumer root and set `tailwindStylesheet` when using Tailwind CSS v4.
The profile supplies `prettier-plugin-tailwindcss` to Trunk; install the same package in the consumer when editor integration or project-owned Prettier scripts also need it.

## Existing Repositories

Do not overwrite an existing root CSpell, Prettier, Markdownlint, yamllint, or SVGO configuration.
Trunk's exported configs act as defaults; a consumer-local config with the same supported name takes precedence.
Keep project-specific custom dictionaries in the consumer repository.

Roll out one repository at a time:

1. Run `trunk init` if the repository is not initialized.
2. Merge the selected profile overlay, replacing generated Node, Python, and conflicting action entries.
3. Add the shared plugin at a tag or SHA.
4. Run `trunk fmt --no-fix --diff=full`.
5. Run each newly enabled linter with `trunk check --all --no-fix --filter=<linter>`.
6. Review findings before enabling any mutating hook.

## Sources

- [Trunk initialization](https://docs.trunk.io/code-quality/overview/initialize-trunk)
- [External plugin repositories](https://docs.trunk.io/code-quality/overview/getting-started/configuration/plugins/external-repositories)
- [Exported configs](https://docs.trunk.io/code-quality/overview/getting-started/configuration/plugins/exported-configs)
- [Trunk shared configs](https://docs.trunk.io/code-quality/overview/linters/shared-configs)
- [`trunk-io/configs`](https://github.com/trunk-io/configs)
- [Prettier configuration](https://prettier.io/docs/configuration)
- [Prettier plugins](https://prettier.io/docs/plugins)
- [`prettier-plugin-markdown-dart`](https://github.com/AndrewDongminYoo/prettier-plugin-markdown-dart)
- [`very_good_analysis`](https://github.com/VeryGoodOpenSource/very_good_analysis)

The owned-repository evidence for this baseline is recorded in [`docs/notes/2026-08-19-source-inventory.md`](./docs/notes/2026-08-19-source-inventory.md).

## Verification

Run the isolated plugin and profile proof:

```bash
./scripts/test-plugin.sh
```

The script creates repositories only under a validated temporary directory, commits test fixtures there so Trunk has a real Git baseline, adds this checkout as a local plugin, exercises intentional violations, and removes the temporary directory on exit.
