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
Consumer-local configuration overrides the remote plugin, so the overlay must replace any generated Node, Python, and action entries that already exist in the consumer.
A consumer that has none of those entries inherits the contract from the plugin alone; the overlay then keeps `trunk-fmt-pre-commit` explicitly disabled instead of merely absent, so a later `trunk init` or an accepted upgrade prompt cannot reintroduce it.
This avoids a custom YAML-merging CLI in the initial baseline.

Merge the overlay rather than copying it over the consumer's file, so the `plugins.sources` block survives.
`python@3.14.4` is absent from the CLI's built-in runtime definitions, and a configuration naming a runtime no source defines is rejected before any linter runs.
This plugin bundles [`runtimes/python`](./runtimes/python/plugin.yaml) so it can supply that version itself, which means a consumer may keep `trunk-io/plugins` or drop it.

Dropping it is what makes the bundled linter definitions in [`linters/`](./linters) take effect.
Trunk discovers those definitions by directory, but an external source that uses the same name wins.
The bundled definitions provide `dart` and `toml-tidy` changes that are not yet available upstream.
They also preserve `pinact`, `grype`, and the current `osv-scanner` download definition when a consumer drops `trunk-io/plugins`.
The bundled [`linters/plugin.yaml`](./linters/plugin.yaml) provides the `github-actions` file type that `pinact` uses for composite actions.
The GDScript linters `gdformat` and `gdlint` in [`linters/gdtoolkit`](./linters/gdtoolkit/plugin.yaml) have no upstream counterpart, so they take effect whether or not the consumer keeps `trunk-io/plugins`; neither is enabled by default, and a Godot repository opts in by adding `gdformat@4.5.0` and `gdlint@4.5.0` to its own `lint.enabled`.

A consumer that drops the source must write this plugin into `plugins.sources` in the same edit that pins the runtime.
`trunk plugins add` needs a configuration it can already resolve, so it cannot bootstrap a profile whose runtime only this plugin defines.

## Universal Baseline

The plugin enables:

- `actionlint`
- `checkov`
- `cspell`
- `git-diff-check`
- `grype`
- `markdownlint`
- `osv-scanner`
- `pinact`
- `prettier`
- `trufflehog`
- `yamllint`

It exports shared configuration for Markdownlint, CSpell, Prettier, SVGO, and yamllint.
SVGO is exported but is only enabled by the Next profile.

### Shared CSpell Vocabulary

[`configs/cspell.config.yaml`](./configs/cspell.config.yaml) contains the shared technical allowlist.
A term enters this list only when the configured CSpell dictionaries still reject it and source files in at least three personal repositories use it.
Project names, personal identifiers, secrets, generated identifiers, and one-off exceptions remain consumer-local.

Consumers without a local CSpell config receive the allowlist through the exported config.
A consumer with a local config must import the released shared config explicitly because its local config takes precedence over the exported config:

```yaml
version: "0.2"
import:
  - https://raw.githubusercontent.com/AndrewDongminYoo/quality-configs/<release-tag-or-sha>/configs/cspell.config.yaml
```

Use an immutable release tag or commit SHA in the URL.
Do not reference `main`.

[`configs/cspell/vgv.config.yaml`](./configs/cspell/vgv.config.yaml) is an optional Very Good Dictionaries policy layer.
It pins the upstream allowed and forbidden dictionaries to a commit and keeps `deeplinking` and `meta-data` forbidden except in `AndroidManifest.xml`.
Import it after the shared config only when the consumer has chosen that spelling policy:

```yaml
version: "0.2"
import:
  - https://raw.githubusercontent.com/AndrewDongminYoo/quality-configs/<release-tag-or-sha>/configs/cspell.config.yaml
  - https://raw.githubusercontent.com/AndrewDongminYoo/quality-configs/<release-tag-or-sha>/configs/cspell/vgv.config.yaml
```

The plugin enables the non-formatting `trunk-check-pre-push` gate and update notifications.
It deliberately does not enable `trunk-fmt-pre-commit`; preview formatter changes before opting into automatic mutation in a consumer repository.

It also enables [`security-review-findings`](./actions/security-review-findings/plugin.yaml), a pre-commit action that prints any finding Claude Code's automatic security-review sessions produced for a session opened at the repository root in the last two days.
The action is a thin adapter: it calls the `--print` mode of the `security-review-findings` hook in the [guard-hooks](https://github.com/AndrewDongminYoo/cc-agents-kit) Claude Code plugin, which owns the lookup, and stays silent on a machine without Claude Code, that plugin, or `jq`.
It warns and never blocks.
The action is enabled from `plugin.yaml` rather than from the profiles, because a profile is merged before this plugin is added and `trunk plugins add` rejects a configuration that enables an action no source yet defines.
It is the one entry in the root baseline that names a specific tool rather than a language stack, and that is deliberate: the baseline is stack-agnostic so that every owned repository can consume it, and Claude Code is the tooling those repositories share regardless of stack, so the action belongs with the baseline rather than with a profile.
A consumer that does not want it disables it locally under `actions.disabled`, the same way the baseline itself withholds `trunk-fmt-pre-commit`.

### Outdated Action Pins

The baseline pins GitHub Actions to commit SHAs through `pinact`, and a pin only stays current if something watches upstream releases.
The watching is done as notifications, never as pull requests, because one Dependabot pull request per action per repository was the volume the operator turned Dependabot off to avoid.

[`pinact-outdated`](./actions/pinact-outdated/plugin.yaml) is a trunk action that once a day copies the repository's workflow and action files aside, runs `pinact run --update` on the copy, and reports each `uses:` whose upstream has a newer release as a `notification_v1` message.
It edits nothing; re-pinning stays a local `pinact run` from the repository root after editing the version comment to the tag you want, and the notification carries that command with the path of the pinact binary the scan used, because trunk's `github-actions` file type reaches only `.github/actions/**` while the scan covers every `action.yml` in the tree.
The plugin defines it but does not enable it, since it calls the GitHub API from the daemon; a consumer opts in with `trunk actions enable pinact-outdated`, and the action is silent when pinact is unavailable.

A weekly sweep across every owned repository ran here once, on 2026-09-16, and was removed the same day: its tracking issue in this public repository read as a defect report against the plugin, which it was not.
`docs/notes/2026-09-16-action-pin-sweep.md` keeps the design, the measurements and the reason for the removal; the sweep belongs in a place whose issues are not this plugin's.

## Local Evaluation

To evaluate a local checkout before a release, add it to an initialized test repository by absolute local path:

```bash
trunk init
# Merge profiles/baseline/trunk.yaml into .trunk/trunk.yaml.
trunk plugins add <absolute-path-to-this-checkout> --id=quality-configs
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
The profile leaves ESLint entirely to the consumer, which keeps whatever version it already pins.
SVGO, oxipng, and dotenv-linter remain disabled because they can rewrite mobile assets or Xcode environment files.

### Next.js

Merge [`profiles/next/trunk.yaml`](./profiles/next/trunk.yaml).
The profile leaves ESLint to the consumer and enables SVGO without enabling automatic formatting hooks.
Review `trunk fmt --no-fix --diff=full --filter=svgo` before accepting SVG rewrites.
For Tailwind projects, copy [`profiles/next/prettier.config.mjs`](./profiles/next/prettier.config.mjs) to the consumer root and set `tailwindStylesheet` when using Tailwind CSS v4.
The profile supplies `prettier-plugin-tailwindcss` to Trunk; install the same package in the consumer when editor integration or project-owned Prettier scripts also need it.

## Existing Repositories

Do not overwrite an existing root CSpell, Prettier, Markdownlint, yamllint, or SVGO configuration.
Trunk's exported configs act as defaults; a consumer-local config with the same supported name takes precedence.
Keep project-specific custom dictionaries in the consumer repository.

Roll out one repository at a time:

1. Run `trunk init` if the repository is not initialized.
2. Merge the selected profile overlay, replacing any generated Node, Python, and conflicting action entries it finds.
3. Add the shared plugin at a tag or SHA.
4. Run `trunk fmt --no-fix --diff=full`.
5. Run each newly enabled linter with `trunk check --all --no-fix --filter=<linter>`.
6. Review findings before enabling any mutating hook.

Work in the repository's own checkout.
Trunk treats a linked worktree as a separate repository but writes `core.hooksPath` into the shared `.git/config`, so applying a profile from a worktree changes which hooks the primary checkout runs.

The adoption evidence from the first consumer is recorded in [`docs/notes/2026-08-29-first-consumer-adoption.md`](./docs/notes/2026-08-29-first-consumer-adoption.md).

## Sources

- [Trunk initialization](https://docs.trunk.io/code-quality/overview/initialize-trunk)
- [External plugin repositories](https://docs.trunk.io/code-quality/overview/getting-started/configuration/plugins/external-repositories)
- [Exported configs](https://docs.trunk.io/code-quality/overview/getting-started/configuration/plugins/exported-configs)
- [Trunk shared configs](https://docs.trunk.io/code-quality/overview/linters/shared-configs)
- [`trunk-io/configs`](https://github.com/trunk-io/configs)
- [`pinact`](https://github.com/suzuki-shunsuke/pinact)
- [`grype`](https://github.com/anchore/grype)
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

The script creates repositories only under a validated temporary directory.
It commits test fixtures so Trunk has a real Git baseline and adds this checkout as a local plugin.
The standalone scenario removes `trunk-io/plugins` and exercises failure and success fixtures for each bundled linter.
The script removes the temporary directory on exit.
It needs `trunk`, `git`, `ruby`, `jq`, and `dart` on `PATH`; the Dart SDK serves the Flutter profile's `prettier-plugin-markdown-dart`, while the bundled `dart` linter downloads its own.

[`.github/workflows/ci.yaml`](./.github/workflows/ci.yaml) runs the same script in GitHub Actions, installing the Trunk CLI and a stable Dart SDK on a runner image that already provides the rest.
