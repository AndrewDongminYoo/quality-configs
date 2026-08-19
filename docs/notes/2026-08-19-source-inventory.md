# Owned Repository Source Inventory

## Scope

The inventory was collected on 2026-08-19 from direct child Git repositories under `/Volumes/dongminyu/Development/01_personal`.
Each repository had to be its own exact Git top-level and have an `origin` matching `github.com/AndrewDongminYoo/`.
Repositories under another owner or inherited parent Git root were excluded.

## Coverage

| Signal                                                            | Count |
| ----------------------------------------------------------------- | ----: |
| Owned repositories surveyed                                       |    73 |
| Repositories with `.trunk/trunk.yaml`                             |    66 |
| Repositories with a CSpell config                                 |    43 |
| CSpell config files, including duplicate root and `.github` files |    45 |
| Repositories with `analysis_options.yaml`                         |    15 |
| Repositories with a Prettier config                               |    22 |
| Repositories with a Markdownlint config                           |     1 |
| Repositories with a yamllint config                               |     0 |
| Repositories with an SVGO config                                  |     0 |

Detected stack subsets were 11 Flutter repositories, 9 React Native repositories, and 13 Next.js repositories.

## Trunk Commonality

All 66 Trunk configurations used CLI version `1.25.0`.
Node `22.16.0` appeared in 65 and Python `3.14.4` appeared in all 66.
The shared plugin does not copy the observed Python version because an isolated fresh consumer failed to resolve it for the current macOS/CPU combination.
It uses the official `trunk-io/configs` compatibility choice `python@3.10.8` instead.
The shared plugin also raises the observed Node `22.16.0` to `22.22.3` because CSpell 10.0.1 requires Node 22.18.0 or newer.
With Node 22.16.0, CSpell returned an engine error with exit code 1 and Trunk displayed a false clean result because that integration accepts exit code 1 for spelling findings.

| Linter           | Repositories |
| ---------------- | -----------: |
| `git-diff-check` |           66 |
| `markdownlint`   |           66 |
| `prettier`       |           66 |
| `trufflehog`     |           66 |
| `yamllint`       |           66 |
| `checkov`        |           64 |
| `osv-scanner`    |           54 |
| `actionlint`     |           40 |
| `cspell`         |           12 |

The action `trunk-upgrade-available` appeared in all 66 configurations.
`trunk-announce` and `trunk-check-pre-push` each appeared in 61, while the mutating `trunk-fmt-pre-commit` appeared in 60.

## Stack Signals

Flutter repositories consistently used the universal baseline.
Shellcheck and shfmt appeared in 10 of 11, ktlint in 8, and SVGO in 9.
SVGO is intentionally disabled in the new Flutter profile because frequency does not establish that asset rewriting is safe.

React Native repositories used the universal baseline in all 9 surveyed repositories.
Ktlint, shellcheck, and shfmt appeared in all 9, while ESLint appeared in 8.
Oxipng also appeared in all 9 but is intentionally disabled because it mutates assets.

Next.js repositories used the universal baseline in all 13 surveyed repositories.
ESLint appeared in 11 and SVGO in 8.
The Next profile enables SVGO but does not enable automatic formatting hooks.

## CSpell Signals

All 43 parsed primary CSpell configs used schema version `0.2`.
Thirty referenced a repository-local `custom-dictionary`, while 10 referenced the Very Good Ventures allowed dictionary and 7 referenced its forbidden dictionary.
The shared baseline does not copy either project-specific word lists or external organization policy.
It provides safe generic defaults and lets a local CSpell config override them.

## Flutter Analyzer Signals

Ten owned Flutter repositories had `analysis_options.yaml` available for stack-specific analysis.
Eight used `very_good_analysis` either alone or with an additional include, and 6 disabled `public_member_api_docs`.
Eight configured `formatter.trailing_commas: preserve`.
Page width was split across 80, 90, and 120, so the shared Flutter template does not set it.

## Prettier Signals

Among the 22 repositories with a Prettier config, `tabWidth: 2` and `useTabs: false` each appeared in 19.
`printWidth: 100` appeared in 10 of the 11 configs that explicitly set a width.
`proseWrap: preserve` appeared in 10 of the 11 configs that explicitly set prose wrapping.
`singleQuote` was split between true and false, so it remains consumer-local.
Across 43 owned repositories with `package.json`, `prettier-plugin-tailwindcss` was the only declared `prettier-plugin-*` package and appeared in 6 repositories.
Those repositories used JavaScript Prettier configs and project-specific Tailwind stylesheet paths, so the shared baseline uses ESM while the path remains consumer-local.
`prettier-plugin-markdown-dart` was not yet present in the surveyed consumer manifests.
It is included in the Flutter profile by explicit operator request and is recorded as a profile decision rather than an observed common setting.

## Source Separation

The shared Markdownlint, yamllint, and SVGO files cannot be described as operator-wide common configs because the owned repositories had at most one direct config for those tools.
Those defaults are adapted from primary Trunk integration sources and the public [`trunk-io/configs`](https://github.com/trunk-io/configs) repository, then constrained by the safety rules in this repository.
