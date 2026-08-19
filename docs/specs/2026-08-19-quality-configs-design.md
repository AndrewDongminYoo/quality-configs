# Quality Configs Design

## Status

Approved for an initial local implementation on 2026-08-19.
The implementation is prepared for the initial `v0.1.0` release.
Consumer-repository migration remains out of scope.

## Goal

Create one reusable repository that supplies a conservative universal Trunk baseline plus explicit Flutter, React Native, and Next.js profiles.
Preserve consumer-local exceptions and make adoption incremental.

## Constraints

- `trunk init` initializes the consumer repository but does not accept an external plugin or named profile.
- A public external plugin can export linter config files and merge linter, runtime, and action settings into the consumer configuration.
- Consumer-local `.trunk/trunk.yaml` settings override remote plugin settings.
- Generated consumer runtime and action entries must therefore be replaced by the selected local profile rather than trusted to inherit from the root plugin.
- Multiple profile `plugin.yaml` files in one remote repository are not a profile-selection mechanism.
- Existing project-specific dictionaries and formatter rules must not be replaced automatically.
- Private remote plugin repositories are not part of the initial distribution model.

## Architecture

The repository has three policy layers:

1. `plugin.yaml` defines the universal baseline, safe generic ignores, runtimes, exported configs, and non-formatting actions.
2. `configs/` contains linter defaults that consumers may override locally.
3. `profiles/` contains one generic and three stack-specific consumer overlays for authoritative runtimes, actions, tools, and safety exclusions.

This architecture uses Trunk's native plugin merge model and plain YAML.
A custom installer or configuration merger is intentionally deferred because it would add code before the profile contract is proven across real repositories.

## Baseline Decisions

The universal linter set is `actionlint`, `checkov`, `cspell`, `git-diff-check`, `markdownlint`, `osv-scanner`, `prettier`, `trufflehog`, and `yamllint`.
Five linters appeared in all 66 surveyed owned repositories with Trunk, while Checkov appeared in 64 and OSV Scanner in 54.
CSpell appeared as a repository config in 43 owned repositories but was enabled through Trunk in only 12, so the shared plugin closes an existing integration gap.

The default actions are `trunk-announce`, `trunk-check-pre-push`, and `trunk-upgrade-available`.
The mutating `trunk-fmt-pre-commit` action is excluded even though it appeared in 60 surveyed repositories, because adding a shared plugin should not silently broaden formatter mutation.
Each local profile repeats this action contract so `trunk init` cannot override it with generated local values.

Linter versions are an initial compatibility snapshot based on the modal or current working versions in the owned repositories.
They are not a promise to hold back `trunk upgrade`; upgrades must update the shared plugin and any ecosystem-owned tool together.
Although `python@3.14.4` appeared in all surveyed Trunk configs, a fresh `trunk init` consumer could not resolve that runtime on the current macOS/CPU combination.
The baseline therefore uses the broadly supported `python@3.10.8` runtime used by the official `trunk-io/configs` plugin.
The observed `node@22.16.0` runtime was also rejected by CSpell 10.0.1, which requires Node 22.18.0 or newer.
The baseline uses the verified Node 22 LTS release `22.22.3` so CSpell reports findings instead of producing a false clean result.

## Exported Config Decisions

Markdownlint enables only low-noise fenced-code structure rules.
Prettier uses an ESM `prettier.config.mjs` with the common explicit values `printWidth: 100`, `tabWidth: 2`, `useTabs: false`, `trailingComma: es5`, `proseWrap: preserve`, and `endOfLine: lf` while leaving the split `singleQuote` preference local.
The universal config does not load ecosystem-specific plugins.
The Flutter profile supplies the explicitly requested `prettier-plugin-markdown-dart` and a JavaScript config template, while requiring the consumer's Dart SDK on `PATH`.
The Next profile supplies the only Prettier plugin found in the owned repository inventory, `prettier-plugin-tailwindcss`, together with a consumer-local JavaScript config template.
CSpell relies on Trunk's Git-aware target selection and excludes generated lock and mobile project files, but it does not centralize project-specific words.
Yamllint starts from the focused official Trunk config rather than imposing a new repository-wide style policy.
SVGO preserves `viewBox` and is exported for the Next profile only.

## Profile Decisions

The Flutter profile adds Kotlin and shell checks, disables Trunk's Dart linter and mobile asset optimizers, supplies `prettier-plugin-markdown-dart`, and provides a minimal `very_good_analysis` template.
The Flutter analyzer template carries only the settings common enough to centralize: `public_member_api_docs: false` and preserved trailing commas.

The React Native profile uses consumer-owned ESLint, adds Kotlin and shell checks, and disables destructive mobile formatters.
The Next.js profile uses consumer-owned ESLint and enables SVGO while leaving automatic formatting disabled.

## Deferred Work

- Prove `v0.1.0` against selected canary repositories before any bulk rollout.
- Decide whether a dedicated Dart analysis package is justified after the copied Flutter template has stabilized.
- Review custom dictionaries for genuinely cross-project terms before introducing a shared dictionary file.
- Add automation for dependency updates only after the first release workflow is defined.

## Acceptance Criteria

- The new path is an independent Git top-level on branch `main`.
- `plugin.yaml` parses and resolves through `trunk config print` from an isolated consumer.
- Every exported config is used by its intended linter in an isolated no-fix check.
- A consumer-local config overrides the exported default without modifying the plugin repository.
- Flutter, React Native, and Next.js overlays parse as Trunk configuration fragments.
- No existing repository is modified.
