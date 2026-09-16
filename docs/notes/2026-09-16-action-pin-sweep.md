# Action Pin Sweep

## Scope

This note records why outdated GitHub Actions pins are reported as notifications rather than pull requests, and the measurements taken on 2026-09-16 that sized the sweep.

## Decision

The operator keeps `pinact` enabled and actions SHA-pinned, and wants a watcher for newer releases that never opens a pull request.
Dependabot version updates cannot do that: the options reference offers `groups`, `cooldown`, and `open-pull-requests-limit`, but setting the limit to zero disables the ecosystem rather than switching to alerts, and no notification-only mode exists.
Dependabot was withheld because one pull request per action per repository, each with its own CI run, was more volume than the pins were worth.

The watcher is therefore pinact itself, run against a copy of the files so nothing is edited:

- `actions/pinact-outdated/pinact-outdated.sh` copies `.github/`, every `action.yml` and `action.yaml` outside `.github` at its relative path, and any `.pinact.yml` or `.pinact.yaml` to a temporary directory, dereferencing symlinks so the copy holds regular files only, runs `pinact run --update` there, and prints one line per changed `uses:` value.
- `actions/pinact-outdated/notify.sh` wraps that as a trunk action on a 24-hour schedule with `notification_v1` output, opt-in per consumer.
- `.github/workflows/action-pin-sweep.yaml` runs the same script weekly across every owned repository that enables `pinact`, and keeps one tracking issue current, commenting only when the set of outdated pins changes.

The trunk `pinact` linter already ships an `upgrade` command that runs `pinact run --update` and reports the result as SARIF; it is disabled in the definition and a consumer can enable it with `commands: [lint, upgrade]`.
It was not used for this because `hold_the_line` is off for pinact, so an enabled `upgrade` turns every newer upstream release into a pre-commit finding that blocks the commit, which is a gate rather than a notification.

## Measurements

One repository, `lucide_icons`, with four workflow files and eight distinct pinned actions, scanned locally with pinact 4.1.1 and an authenticated token:

| Measurement                       | Value                                     |
| --------------------------------- | ----------------------------------------- |
| Wall time                         | 3 seconds                                 |
| GitHub API requests               | 7                                         |
| Outdated pins found               | 1 (`pnpm/action-setup` v6.0.10 to v6.1.0) |
| Owned repositories, not archived  | 116, of which 39 private                  |
| Local checkouts enabling `pinact` | 25 on this machine                        |

At that cost the weekly sweep stays well inside the authenticated limit of 5000 requests per hour even if every owned repository were in scope.
Without a token pinact shares the anonymous budget of 60 requests per hour for the machine's address, and a scan of `lucide_icons` failed on the first request when that budget was already spent, which is why the script fills `GITHUB_TOKEN` from `gh auth token` when nothing is exported.

## Partial Scans

A first full run over the owner's repositories on 2026-09-16 scanned 33 repositories in 202 seconds with 278 API requests and found outdated pins in 23 of them.
One repository, `face_photo_classification`, made pinact exit nonzero: its `desktop-release.yml` keeps a Rust toolchain action on its `stable` branch and the Tauri action on its `dev` branch on purpose, as floating references excluded from the trunk `pinact` linter through `lint.ignore` rather than through pinact's own configuration.
pinact still updated the three pins it could resolve in that repository before reporting `action can't be pinned` on the branch reference.
The core script therefore diffs the copy regardless of pinact's exit code, prints the resolved lines, and exits 3 for a partial scan; the sweep lists such repositories under "Partially scanned" with pinact's reason instead of dropping their findings.
The durable fix belongs to the repository: an `ignore` rule in `.pinact.yaml` (pinact config version 3 uses `rules` with `ignore: true` and an `expr` condition) is honoured by the trunk linter and by this scan alike, while a trunk `lint.ignore` path is invisible to pinact.

## Scope Rule

Only repositories whose `.trunk/trunk.yaml` lists `pinact` under `lint.enabled` and not under `lint.disabled` are scanned.
A repository that disabled `pinact` chose floating tags, and reporting a newer release there would ask it to reverse a policy the sweep does not own.
The `disabled` entry wins because trunk uses it to switch off a linter that a plugin or profile enables.

## Hosted Review Round

CodeRabbit's first round on PR #4 added five corrections, all applied: a symlinked workflow copied with `cp -R` stays a link into the real repository and pinact would write through it, so every copy now dereferences (`cp -L`); a partial scan's notification now says it was partial; `gh repo list --limit` succeeds silently at its cap, so a listing that reaches the limit fails the sweep as truncated; the tracking-issue comment is posted before the body edit, so a failed comment fails the step before the body records the new state and the next run retries; and the note's description of the copied files was corrected.
Codex's first round found that the notification's repair command targeted `.github` only while the scan covers every `action.yml` in the tree; the command is now `pinact run` from the repository root by the binary's absolute path, because trunk's `github-actions` file type matches only `.github/actions/**`.

Codex's second round, on the fixed head, found two more: a consumer that inherits `pinact` from this plugin without repeating it locally (one landing-page repository did so on 2026-09-16, and the corrected filter brought six more repositories into scope, 39 instead of 33) was classified as not enforcing it, so the scope filter now also accepts a `plugins.sources` entry for quality-configs, still overridden by a local `lint.disabled`; and two private sets with equal counts produced identical public reports, so the private section now carries a 16-character sha256 digest of the sorted private lines, which the reporter includes in the outdated set.
A third Codex round noted that sorting the extracted lines let a pin that moved from one repository to another read as no change; the comparison now keeps the report's own order, which the sweep makes deterministic by sorting the listing by name (`gh repo list` orders by last push).
A fourth round returned four findings in the same area, and they were answered at the cause rather than one by one: the core no longer parses diff headers (GNU diff quotes a path with a space) but diffs each copied file by its known path; the private digest is a keyed SHA-256 hash (openssl's message authentication code mode) keyed by the token the sweep runs under, over records that pair each finding with its repository, so a guessed private name cannot be confirmed against the public digest and a pin moving between private repositories still changes it; and the private scanned total sits on a line the reporter ignores.
If the private state draws further findings, the next step is to keep that state outside the public issue rather than to refine what the public body carries.

## What the Public Report May Say

A local Codex review of the branch on 2026-09-16 found that the first draft printed private repositories' names, workflow paths and pinned actions into this public repository's Actions log and tracking issue.
The report now names only public repositories; private ones are scanned and appear as counts of repositories, outdated pins and incomplete scans, with a pointer to `--show-private` for a local run that lists them.

The same review found two ways the first draft could report "every pin is current" without having looked: a failed `gh repo list` inside a process substitution did not stop the loop, and any API failure while reading a repository's trunk configuration was counted as "no trunk configuration".
The listing now runs first and its failure, or an empty result, exits nonzero; only an HTTP 404 counts as a missing configuration, and every other read failure is listed under "Not scanned".

A second local round found four more ways a failure could pass as a clean result, all fixed and covered by the unit test:

- The workflow piped the sweep through `tee`, and the default Actions shell has no `pipefail`, so a failed sweep would have handed an empty report to the issue step; the sweep now writes the file directly under `shell: bash`.
- The notification adapter cleared a standing notification on any empty report; it now clears one only after a complete scan, since a partial scan that resolved nothing says nothing about the pins it last reported.
- The sweep counted a repository as scanned before pinact ran, so a run in which every pinact call failed still printed "Every pin is at its latest release"; completed scans are now counted separately, that sentence appears only when every scan completed, and a run with no completed scan exits nonzero.
- The issue comment fired on any body change, including the "Skipped N" statistics; the comment now fires only when the outdated set (repository headings, pin and problem bullets, private counts) changes, while the body is still refreshed.

A third round found that the copy left out composite actions outside `.github` (`actions/<name>/action.yml`), which pinact scans from the repository root, and that a private repository's failed scan did not stop the "every pin current" sentence; the copy now carries every `action.yml` at its relative path, and the sentence requires zero incomplete scans on both sides.
That copy made this repository's own `tests/fixtures/*/action.yaml`, deliberately stale, show up as outdated pins; a `.pinact.yaml` whose `files` list names only the workflow files excludes them, because a `files` list replaces pinact's default patterns rather than extending them (measured with pinact 4.1.1: the fixture stayed untouched while a listed path was updated).

## Token

The sweep runs under the repository secret `GH_TOKEN`, a personal access token that can list and read the owner's repositories including private ones.
The workflow scopes every listing to the owner by name, so the token's reach beyond that owner is never exercised.
The tracking issue is written with the workflow's own `GITHUB_TOKEN`, scoped to `issues: write`, so the personal token is never used for a write.
