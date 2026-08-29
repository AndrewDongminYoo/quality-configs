# Trunk Dart Linter Evaluation

## Scope

This note records why [`profiles/flutter/trunk.yaml`](../../profiles/flutter/trunk.yaml) disables Trunk's `dart` linter, measured on 2026-08-29 against Trunk CLI 1.25.0 and `trunk-io/plugins` v1.11.0.
The design specification states the decision; this note holds the evidence behind it.

## The Rejection Is Unanimous

Every owned repository whose Trunk configuration mentions `dart` disables it:

```log
disabled: 19
enabled:   0
```

That is not a preference expressed in a few projects.
It is the outcome the linter produces in every Flutter project it has been offered to.

## The Formatter Version Resolves From the Environment

The linter definition downloads a standalone Dart SDK pinned by `known_good_version: 3.10.8`, and orders its search path as `["${env.PATH}", "${linter}/bin"]`.
The system Dart therefore wins whenever one is present, and the downloaded SDK is a silent fallback.
This machine runs Dart 3.13.1 from the Flutter SDK, three minor versions above the pin.

A formatter rewrites files, so its version cannot be ambient.
The same repository formatted on a developer machine and in a container without Dart is formatted by two different Dart releases, and the difference surfaces as diff churn rather than as an error.

The PATH ordering and the removal of the shim that shadowed the project SDK both came from `trunk-io/plugins` PR #1114, opened 2026-02-04 and merged 2026-04-28, together with the `run_from` batching that fixed the per-file traversal cost.
Those changes were correct.
They moved the problem rather than closing it: before the change the downloaded SDK could shadow the project's Dart, and after it the project's Dart is preferred but nothing declares that preference or enforces it.

## `dart@SYSTEM` Closes the Formatter Half

Pinning the version to `SYSTEM` removes the fallback rather than reordering it.
Measured in an isolated fixture:

```log
dart on PATH     ->  dart reports the formatting issue; Trunk's SDK cache stays at 0 B
dart absent      ->  Checked 0 files, 3 failures, "Some tools failed to run"
```

No download happens, the project's own SDK does the work, and a missing SDK fails loudly instead of substituting a different version.
This is the same shape the React Native and Next profiles already use for `eslint@SYSTEM`.

## `dart analyze` Degrades Without Saying So

The analyzer half does not have an equivalent fix.
With `analysis_options.yaml` set to `include: package:very_good_analysis/analysis_options.yaml` and the package not resolved, the analyzer neither fails nor warns:

```log
$ dart analyze --no-fatal-warnings quotes.dart
Analyzing quotes.dart...
No issues found!
```

The file contains a double-quoted string, which `prefer_single_quotes` would report.
That rule belongs to the included package, so its absence from the output shows the project's rule set was never loaded.
A checkout that has not run `flutter pub get` therefore reports a clean analysis against rules that never applied, which is the same false-clean shape recorded for CSpell in [`2026-08-19-trunk-reuse-findings.md`](./2026-08-19-trunk-reuse-findings.md).

A plugin definition cannot repair this, because `dart analyze` does not detect its own degradation.

## The Analyzer Runs Once Per Directory

The `analyze` command declares `batch: true`, but `run_from: ${parent}` splits every batch along directory boundaries, so a project pays one Dart analyzer startup per directory.
`format` does not share the problem because PR #1114 already runs it from the package root.

Measured over 161 Dart files in 40 directories, with each round rewriting every file so the lint cache could not serve a previous result, and invocations counted by a shim placed ahead of `dart` on `PATH`:

```log
                       wall clock (median)   dart invocations
run_from: ${parent}    6.14s                 43
run_from: root         2.17s                  6
```

Running the same tree directly costs 0.85s for `dart analyze lib` and 0.26s for `dart format lib`.

Three routes to batching were tried, and the third works.

Moving `run_from` to the project root while keeping the default output format reports the wrong location as soon as a repository holds more than one `analysis_options.yaml`.
Trunk resolves the parsed path against the target's own parent directory rather than against `run_from`, so a package with an `example/` directory reports `example/bad.dart` where the correct location is `example/lib/bad.dart`.
The comment on the current setting describes exactly this constraint, and the linter's own snapshot fixture carries its own `analysis_options.yaml`, so the stored snapshots resolve identically under both settings and cannot detect the defect.

`dart analyze --format=machine` reports absolute paths, which does fix the location under the same batching, but it renames every rule:

```log
default format  ->  dart/prefer_single_quotes
machine format  ->  dart/PREFER_SINGLE_QUOTES
```

Existing suppressions stop working, and Trunk says so itself: `trunk-ignore(dart/prefer_single_quotes) is not suppressing a lint issue`.
The change would silently disarm every `trunk-ignore(dart/…)` comment already written in consumer repositories, break `issue_url_format`, and drop the correction sentence from each message.

`--format=json` does work, and it is consumable from a plugin definition after all.
An earlier revision of this note claimed otherwise on the reasoning that Trunk's named output parsers are built into the CLI and that the single-line JSON document defeats a line-oriented regex.
Neither holds: an `output: regex` definition matches every diagnostic within the one line, and the JSON carries lowercase codes, absolute paths, and uppercase severities that map to the same levels.

Validated against four owned repositories with their packages already resolved, using a local `lint.definitions` override so the consumer configuration replaces the plugin's `analyze` command:

```log
repository        analysis_options  dart dirs   before      after     invocations
mirae                            8        137   101.60s    14.70s    119 -> 16
bubble_shooter                   1         34    38.97s     4.12s     35 -> 4
ttush_push                       2         24    14.66s     4.31s     21 -> 2
custom_linters                   4         16    13.65s     9.99s     23 -> 11
```

`mirae` checked 419 files under both definitions and reported no issues under either, so the 87 seconds it saves are spent on analyzer startup rather than on analysis.

The Flutter app reports 167 issues from its own `very_good_analysis` rules, and the two definitions produce the same 167 with identical files, lines, columns, levels, and rule codes.
The gain tracks the number of `analysis_options.yaml` files, because that is what still bounds a batch.
The only user-visible change is that each message loses its trailing correction sentence, since the JSON keeps `correctionMessage` in a separate field that a single capture group cannot reach.
The upstream linter's own snapshot test confirms the same boundary: regenerating it changes four `message` lines and nothing else, with `code`, `level`, `line`, `column`, `file`, and `issueUrl` byte-identical.

## Decision

The Flutter profile keeps `dart` under `lint.disabled`.
Enabling `dart@SYSTEM` would fix the formatter and import the analyzer's silent degradation in the same move, and Flutter projects already run analysis through their own pinned toolchain.

Enabling the format command alone would be worth revisiting, but whether a consumer can disable a single command of a linter without redeclaring the whole definition was not established: `--filter=dart/format` was accepted and produced the same output as `--filter=dart`, which does not distinguish command-level filtering from linter-level filtering.

Revisit the decision when the JSON change lands upstream, since the cost argument disappears at that point and the analyzer's package-resolution requirement becomes the only remaining objection.
A consumer that runs `flutter pub get` before linting, which every repository measured above does, already satisfies it.
