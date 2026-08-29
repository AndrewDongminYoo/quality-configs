# Stack Profile Rollout Findings

## Scope

These findings came from applying `v0.1.0` to three public consumers on 2026-08-29, one per profile that had never run outside `scripts/test-plugin.sh`.

| Consumer                       | Profile        | Stack                 |
| ------------------------------ | -------------- | --------------------- |
| `toml-tidy`                    | `baseline`     | Python                |
| `rn-typed-assets`              | `react-native` | React Native, JS only |
| `order-espresso-website`       | `next`         | Next.js               |
| `react-native-receipt-scanner` | `react-native` | React Native, Kotlin  |

`merry-setup` already covered `baseline` on Shell, so the Python consumer measures a second language against the same overlay rather than the profile itself.
The two stack profiles had no evidence outside the isolated test script before this run.
The fourth consumer was added after the first three left `ktlint`, `shellcheck`, and `shfmt` unmeasured.
Seven public React Native repositories carry both Kotlin and shell files, so targets are not scarce; `react-native-receipt-scanner` was chosen for holding the largest set of each, 23 Kotlin and 9 shell files.

## `eslint@SYSTEM` Does Not Resolve a Project-Local ESLint

Both stack profiles replace the consumer's pinned ESLint with `eslint@SYSTEM`, and in both consumers that made the linter stop running.

```log
Binary not found. Next check run may repair installation
  message: Unable to find binary in PATH
  binary: eslint
```

Trunk searches the process `PATH`, which does not contain `node_modules/.bin`.
Both consumers install ESLint as a dev dependency, so `npx eslint --version` answers while the linter itself never starts.
A precondition check through `npx` therefore passes and still predicts nothing.

The failure is not pre-existing.
Restoring the consumer's own pin in `order-espresso-website` and changing nothing else produced a working run:

```log
eslint@10.9.1  ->  Checked 32 files, No issues
eslint@SYSTEM  ->  Checked 0 files, 1 failure
```

The run itself is loud: a `FAILURES` block, a non-zero exit, and a details file per batch.
What it loses is coverage, and coverage is not what the summary counts.
`trunk check` reports a failed tool separately from lint issues, so the same run that checked zero files still contributes zero findings to the issue total, and a reader watching the issue count sees no change.

Both profiles dropped the entry on the strength of this, so ESLint is now entirely the consumer's to pin.
The distinction to carry forward is where a tool installs: `@SYSTEM` is the right shape for something the environment puts on `PATH`, such as the Dart SDK in [`2026-08-29-dart-linter-evaluation.md`](./2026-08-29-dart-linter-evaluation.md), and the wrong shape for anything a package manager puts in `node_modules/.bin`.

## The False Clean Reproduced on Two More Stacks

`order-espresso-website` is the strongest case because it was already in the false-clean state before the plugin was added.
It had enabled `cspell@10.1.1` under `node@22.16.0` on its own, and only the runtime changed between these two runs:

```log
node@22.16.0  ->  Checked 62 files, No issues
node@22.22.3  ->  Checked 62 files, 3 lint issues
```

`toml-tidy` showed the same shape when CSpell arrived with the plugin:

```log
node@22.16.0  ->  Checked 26 files, No issues
node@22.22.3  ->  Checked 26 files, 76 lint issues
```

Cite `order-espresso-website` in preference to this pair.
The operator was editing the `toml-tidy` checkout in parallel during both runs, and although the file count matched and CSpell's behavior here is runtime-bound, nothing else was moving in the Next consumer.

Counting `merry-setup`, the engine error now has three consumers and three stacks behind it.
A consumer that adds the plugin without merging the overlay's runtime keeps its own Node and stays in the false clean, so the runtime line is the part of the overlay that carries the measurement.

## Trunk Commands Do Not Rewrite the Consumer Config

Each command was bracketed by a checksum of `.trunk/trunk.yaml`.

- `trunk plugins add <uri> <tag> --id=…` adds only the `plugins.sources` entry.
- `trunk config print` leaves the file byte-identical.
- `trunk check --all --no-fix --filter=…` leaves the file byte-identical.

A `toml-tidy` diff that also carried `oxipng@9.1.5`, `isort@9.0.1`, `checkov@3.3.15`, and `ruff@0.16.5` was the operator's own parallel work in that checkout, not a side effect of the rollout.
The bracketing checksums are what separated the two.

## The Overlay Fails the Baseline It Ships With

Both stack profiles list `dotenv-linter` under `lint.disabled`, and `dotenv` is absent from `configs/cspell.config.yaml`.
Merging either profile therefore makes the consumer's own `.trunk/trunk.yaml` fail the CSpell run that the same plugin enables:

```log
.trunk/trunk.yaml:23:7  high  Unknown word (dotenv)  cspell/error
```

It reproduced in both consumers, and neither has a local CSpell dictionary that could have hidden it.
`react-native-receipt-scanner` merged the same profile and reported nothing, because its `.cspell/custom-dictionary.txt` already carries the word, which is what makes the defect easy to miss: it surfaces only in a consumer without one.
This repository could not have caught it either.
Its root `cspell.config.yaml` already lists `dotenv` among the project's own words, so self-validation reads the profile through a dictionary no consumer inherits.
Adding `dotenv` to the exported dictionary is the fix, and it is a plugin change rather than a rollout step, so it is recorded here and has not been applied.
It joins the shell-vocabulary proposal in [`2026-08-29-first-consumer-adoption.md`](./2026-08-29-first-consumer-adoption.md) as pending dictionary work.

## Merging the Overlay by Hand Has Two Collision Points

Neither is documented in `README.md`, and both produce an invalid or wrong configuration if missed.

1. `trunk-fmt-pre-commit` already sits under `actions.enabled` in every surveyed consumer.
   Adding the overlay's `actions.disabled` block leaves the action listed twice, so the enabled entry has to be deleted in the same edit.
2. A linter the profile disables may already be pinned under `lint.enabled`.
   `order-espresso-website` carried `oxipng@10.2.0` while the Next profile disables `oxipng`, so the enabled entry has to be removed rather than merely shadowed.

Both consumers also kept linter pins newer than the plugin's (`checkov@3.3.13`, `osv-scanner@2.5.1`, `trufflehog@3.97.1`), which matches the precedence recorded in [`2026-08-29-first-consumer-adoption.md`](./2026-08-29-first-consumer-adoption.md).
Read a resolved version from `trunk config print`, never from `plugin.yaml`.

## A Stale `core.hooksPath` Is Repaired Silently

`toml-tidy` pointed `core.hooksPath` at a directory that no longer existed, so its Git hooks had been dead for an unknown period:

```log
before:  <repo>/.toml-tidy-pr.c1w0Z7/trunk-cache/repos/75660bcd…/git-hooks   (missing)
after:   ~/.cache/trunk/repos/75660bcd…/git-hooks
```

Adding the plugin repaired it as a side effect, without reporting anything.
This is the same shared-`.git/config` mechanism recorded for a linked worktree in the first-consumer note, seen from the other direction: a path that once pointed into a temporary directory survives that directory's deletion, and nothing surfaces the broken state until Trunk runs again.

## What the Full Gate Reported

Both consumers were then run without a filter, because a linter that is enabled but never exercised proves nothing.

```log
rn-typed-assets          Checked 32 files, 105 lint issues, 1 unformatted file, 2 failures (eslint, grype)
order-espresso-website   Checked 63 files, 3 lint issues, 4 failures (eslint x3, grype)
```

The `grype` failures belong to each consumer's own pin rather than to the overlay, which neither enables nor disables that linter.

`svgo` remains unmeasured, because `order-espresso-website` holds no SVG files and a pass on an empty target set is not evidence that the linter launches.
`piggon` is the next target: it takes the same Next profile, carries five SVG files, and its tree was clean at the time of this survey.

The other three were measured in `react-native-receipt-scanner`, which already pinned them at the same versions the profile enables, so the overlay changed only the runtime around them:

```log
node@22.16.0, own runtimes   ->  Checked 24 files, 1 unformatted file (shfmt)
node@22.22.3, overlay        ->  Checked 24 files, 1 unformatted file (shfmt)
```

`ktlint` needs the `java@13.0.11` the profile supplies and started without complaint under it.
Neither it nor `shellcheck` reported anything, and the single `shfmt` finding is the consumer's own.
So all three launch, which is what `eslint@SYSTEM` did not.

The same consumer confirms the ESLint removal.
Its full gate reported 193 files and 1745 lint issues with an empty `FAILURES` block, and ESLint itself checked 26 files cleanly at the consumer's own `eslint@10.9.1`.

## The Tag This Run Started From, and the One It Requires

The ten commits between `v0.1.0` and the start of this run were documentation only.

```bash
git diff --stat v0.1.0..HEAD -- plugin.yaml configs profiles   # empty
```

`v0.1.0` therefore still described the plugin payload exactly, and it is on `origin` at `6a147be`, so all three consumers resolved the published artifact rather than a working tree.

Removing `eslint@SYSTEM` changes what that provenance means rather than breaking anything.
A tag pins only what `trunk plugins add` resolves, which is `plugin.yaml` and `configs/`, and both are untouched, so no consumer pinned at `v0.1.0` is affected.
What changed is the overlay a human copies by hand, and "adopted `v0.1.0`" no longer identifies which version of that overlay a consumer holds.
A tag covering the profile edit is worth cutting for that reason alone.
