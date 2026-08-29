# Stack Profile Rollout Findings

## Scope

These findings came from applying the plugin to five public consumers on 2026-08-29, starting with one per profile that had never run outside `scripts/test-plugin.sh`.
The first four took `v0.1.0` and `piggon` took `v0.2.0`.

| Consumer                       | Profile        | Stack                 |
| ------------------------------ | -------------- | --------------------- |
| `toml-tidy`                    | `baseline`     | Python                |
| `rn-typed-assets`              | `react-native` | React Native, JS only |
| `order-espresso-website`       | `next`         | Next.js               |
| `react-native-receipt-scanner` | `react-native` | React Native, Kotlin  |
| `piggon`                       | `next`         | Next.js, ESM, SVG     |

`merry-setup` already covered `baseline` on Shell, so the Python consumer measures a second language against the same overlay rather than the profile itself.
The two stack profiles had no evidence outside the isolated test script before this run.
The last two consumers were added to close what the first three left unmeasured.
`react-native-receipt-scanner` covers `ktlint`, `shellcheck`, and `shfmt`: seven public React Native repositories carry both Kotlin and shell files, so targets are not scarce, and this one holds the largest set of each at 23 Kotlin and 9 shell files.
`piggon` covers `svgo`, being the only Next-profile candidate with SVG files.

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

`piggon` repeated the `order-espresso-website` shape a second time, having enabled `cspell@10.0.1` under `node@22.16.0` on its own:

```log
node@22.16.0  ->  Checked 180 files, No issues
node@22.22.3  ->  Checked 180 files, 448 lint issues
```

Counting `merry-setup`, the engine error now has five consumers behind it, two of which reached the false clean without any involvement from this plugin.
A consumer that adds the plugin without merging the overlay's runtime keeps its own Node and stays in the false clean, so the runtime line is the part of the overlay that carries the measurement.

## Trunk Commands Do Not Rewrite the Consumer Config

Each command was bracketed by a checksum of `.trunk/trunk.yaml`.

- `trunk plugins add <uri> <tag> --id=…` adds only the `plugins.sources` entry.
- `trunk config print` leaves the file byte-identical.
- `trunk check --all --no-fix --filter=…` leaves the file byte-identical.

A `toml-tidy` diff that also carried `oxipng@9.1.5`, `isort@9.0.1`, `checkov@3.3.15`, and `ruff@0.16.5` was the operator's own parallel work in that checkout, not a side effect of the rollout.
The bracketing checksums are what separated the two.

## The Overlay Fails the Baseline It Ships With

The exported `configs/cspell.config.yaml` shipped an empty `words` list, so every linter name a profile writes into the consumer's `.trunk/trunk.yaml` was an unknown word.
Merging a profile therefore made that file fail the CSpell run the same plugin enables.

`rn-typed-assets` is the only surveyed consumer with no CSpell configuration of its own, which makes it the only one that reads the exported dictionary unmodified.
Checking its merged `.trunk/trunk.yaml` named the full set:

```log
dotenv  gradlew  oxipng  Podfile  shellcheck  shfmt
```

Six words, not the one that first surfaced.
Consumers with their own dictionary each hid a different subset: `order-espresso-website` reported only `dotenv`, `piggon` reported only `oxipng`, and `react-native-receipt-scanner` reported nothing at all because its `.cspell/custom-dictionary.txt` covers them.
That is what made the defect hard to size from any single consumer.

This repository could not have caught it either.
Its root `cspell.config.yaml` carried those words among the project's own, so self-validation read the profiles through a dictionary no consumer inherits.
The fix moves all six into the exported config, where the profiles that need them live, and deletes them from the root file so each word has one owner.
Verified by pointing `rn-typed-assets` at a local plugin source: eight findings before, none after apart from `dongminyu` in the temporary local path itself.

The shell-vocabulary proposal in [`2026-08-29-first-consumer-adoption.md`](./2026-08-29-first-consumer-adoption.md) remains open and is a different problem: those words come from the consumer's own shell code, not from the overlay.

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

`svgo` was measured last, in `piggon`, which takes the same Next profile and carries five SVG files.
It failed on every one of them, before the plugin was involved at all:

```log
ReferenceError: module is not defined in ES module scope
  at .trunk/configs/svgo.config.js:1:1
```

`trunk init` writes `.trunk/configs/svgo.config.js` using `module.exports`, and `piggon` sets `"type": "module"` in `package.json`, so Node reads that `.js` file as ESM and SVGO exits 1 on every file.
Moving the consumer's copy aside let the plugin's exported config answer instead, and the same five files passed:

```log
consumer .trunk/configs/svgo.config.js  ->  Checked 5 files, 5 failures
exported configs/svgo.config.mjs        ->  Checked 5 files, No issues
```

The `.mjs` extension is what fixes it: it declares the module system in the filename, so `"type"` in the consumer's `package.json` cannot reinterpret it.
This is the first measured case of an exported config being better than what `trunk init` generates rather than merely equivalent to it, and it is invisible until a consumer sets `"type": "module"`.

The consumer's own file still wins by precedence, so adopting the plugin does not repair this on its own.
`README.md` tells consumers not to overwrite an existing config, which is right for a config someone wrote and wrong for a generated one that cannot load; deleting `.trunk/configs/svgo.config.js` is the step an ESM consumer needs.

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

## The Python Pin Was Blocking a Linter, and Raising It Cost Two Things

`linters/toml-tidy/plugin.yaml` declares `runtime: python`, and the package requires Python 3.12 or newer, so under the baseline's `python@3.10.8` pip found no installable distribution at all:

```log
ERROR: Ignored the following versions that require a different python version:
       0.1.0 ... 0.4.1 Requires-Python >=3.12
ERROR: No matching distribution found for toml-tidy==0.4.1
```

The pin moved to `python@3.14.4`, which is what every surveyed consumer already runs.
`toml-tidy` then installed and rejected an unsorted TOML fixture, and `checkov` and `yamllint` both stayed clean across 18 files on the new runtime.
`yamllint` has a canary pair in `scripts/test-plugin.sh` that proves it still rejects a violation; `checkov` does not, so its clean result is unproven in the sense [`2026-08-19-trunk-reuse-findings.md`](./2026-08-19-trunk-reuse-findings.md) means.

The first cost is that `trunk-io/plugins` is now mandatory rather than merely advisable.
`python@3.14.4` is not in the CLI's built-in runtime definitions, and a configuration naming a runtime no source defines is rejected before any linter runs:

```log
✖ plugin operations require a valid trunk config
```

The same file with `python@3.10.8` was accepted, so the version alone decides it.

The second cost surfaced a latent defect in `scripts/test-plugin.sh`.
It applied a profile with `cp`, which discards the `plugins.sources` block a real consumer keeps, then tried to add the sources back afterwards.
Under `3.10.8` the built-in definitions covered the gap and the script passed; under `3.14.4` the very command meant to restore the source is the one that fails, because the config is already invalid when it runs.
The script now merges the sources into the profile instead, which is what `README.md` describes a consumer doing.
A test that copies where the procedure merges is a lookalike, and it took a runtime the built-in set does not carry to tell the two apart.

## A Bundled Definition Loses a Name Collision

`linters/<name>/plugin.yaml` needs no declaration in `plugin.yaml`; Trunk discovers the directory and registers what it finds as `autogenerated_definition_path: linters/<name>`.

What it does not do is win against another source using the same name.
With this plugin listed ahead of `trunk-io/plugins` in `plugins.sources`, a consumer merging the Flutter profile resolved the upstream `dart` definition, not the bundled one:

```log
run: dart analyze --no-fatal-warnings ${target}     # upstream
run_from: ${parent}
```

Renaming the bundled copy made both resolve side by side, so the collision is on the name rather than on the content.
Both names this repository bundles, `dart` and `toml-tidy`, already exist in `trunk-io/plugins` v1.11.0, and each local copy differs from upstream in one respect: `dart` carries the JSON analyzer path from an open upstream PR, and `toml-tidy` raises `known_good_version` from `0.3.1` to `0.4.1`.
Until those land upstream, both bundled files are inert.

This also means `scripts/test-plugin.sh` cannot assert that its staged plugin carries `linters/`.
Any name it could check resolves from `trunk-io/plugins` whether or not the staged copy has it, so the copy is there to keep the test reading the same artifact a consumer does, with no assertion behind it yet.
A bundled name that upstream does not define could be checked, and adding one is the moment to add that check.

## The Tag This Run Started From, and the One It Requires

The ten commits between `v0.1.0` and the start of this run were documentation only.

```bash
git diff --stat v0.1.0..HEAD -- plugin.yaml configs profiles   # empty
```

`v0.1.0` therefore still described the plugin payload exactly, and it is on `origin` at `6a147be`, so the first four consumers resolved the published artifact rather than a working tree.

The two fixes this run produced differ in how far they reach, and the difference is worth keeping straight.

`v0.2.0` removed `eslint@SYSTEM` from the two stack profiles.
A tag pins only what `trunk plugins add` resolves, which is `plugin.yaml` and `configs/`, so a consumer sitting at `v0.1.0` was never affected by it; what changed is the overlay a human copies by hand, and the tag exists so "adopted `v0.1.0`" still identifies which overlay a consumer holds.

The dictionary fix is the opposite case.
`configs/` is exactly what a consumer resolves, so every consumer picks it up on its next run once it moves to the tag that carries it, with no file to copy.
