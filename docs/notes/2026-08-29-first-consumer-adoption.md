# First Consumer Adoption Findings

## Scope

These findings came from applying `v0.1.0` to `merry-setup`, a Shell repository, on 2026-08-29.
It is the first consumer outside this repository's own self-validation, so it measures the documented rollout rather than the plugin file.

## The Overlay Displaces Values, It Does Not Supply Them

The same repository resolved the plugin twice, with only the consumer file differing.

With no `runtimes` block and only `trunk-check-pre-push` under `actions.enabled`, adding the plugin alone resolved the full contract:

```log
runtimes:         node@22.22.3, python@3.10.8
actions.enabled:  trunk-announce, trunk-check-pre-push, trunk-upgrade-available
```

After a local Trunk configuration commit wrote `node@22.16.0`, `python@3.14.4`, and `trunk-fmt-pre-commit` into the consumer file, the same plugin at the same tag resolved those local values instead.

So the overlay's job is to replace entries a consumer already has, not to deliver values the plugin could not.
A consumer whose `.trunk/trunk.yaml` carries no runtime or action entries inherits the contract correctly without it.
Consumer-local linter pins survive either way: `actionlint@1.7.8` stayed at the consumer's version against the plugin's `1.7.12`.

## Absent Is Not Disabled

In the inherited case `actions.disabled` resolved empty, so `trunk-fmt-pre-commit` was merely not enabled.
Nothing then prevents a later `trunk init`, an accepted upgrade prompt, or another contributor from adding it back, which is exactly what the local configuration commit did.
The overlay's explicit `disabled` entry is what makes the exclusion durable, and that is the reason to merge it even when the resolved contract already looks correct.

## The False Clean Reproduced Outside This Repository

The engine-error shape recorded in [`2026-08-19-trunk-reuse-findings.md`](./2026-08-19-trunk-reuse-findings.md) reproduced in a real consumer.
Holding the same 25 files and the same exported CSpell config, only the runtime differed:

```log
node@22.22.3  ->  69 lint issues
node@22.16.0  ->  No issues
```

The consumer reached `node@22.16.0` through its own Trunk configuration commit, after the plugin had already been added.
Adoption therefore does not retire the risk: a consumer can walk back into the false clean at any later runtime change, and the failure still presents as a passing check.

## CSpell Does Not Reach Shell Embedded in YAML or Markdown

The consumer produced 69 CSpell findings, and the shell keywords among them (`elif`, `esac`, `mktemp`, `pipefail`, `cntrl`) appeared only in `action.yml` and in Markdown documents, never in the repository's `.sh` files.
CSpell selects its dictionaries by file type, so shell written inside a workflow `run:` block or a fenced Markdown block gets no shell vocabulary.

This is not a project-specific exception of the kind `AGENTS.md` excludes, because every consumer with shell in CI or in documentation hits it.
Adding an explicit shell dictionary to `configs/cspell.config.yaml` is a candidate for the next revision; it is recorded here as a proposal and has not been applied.

## Applying From a Linked Worktree Rewrites Shared Git Config

Trunk keys its repository cache on the working-tree path, so a linked worktree is a separate repository to it and receives its own hooks directory.
`core.hooksPath` lives in `.git/config`, which every worktree of a repository shares.
Running Trunk from a worktree therefore changes the hook path for the primary checkout as well, and because the baseline enables two more actions than the surveyed consumer had, the primary checkout resolves `post-checkout`, `post-merge`, and `pre-rebase` hooks it never installed.

Apply a profile in the repository's own checkout.
A worktree is still useful for reading a resolved configuration, but treat any Trunk invocation there as a write to shared repository state.

## Consumer Findings

The adopted baseline reported 69 CSpell findings and 3 Prettier-unformatted files.
Checkov, OSV Scanner, TruffleHog, actionlint, markdownlint, yamllint, shellcheck, and git-diff-check were clean.
The consumer's root `.markdownlint.yaml` took precedence over the exported default, proven by a canary using MD012, which the consumer config enables and the exported config leaves off.
