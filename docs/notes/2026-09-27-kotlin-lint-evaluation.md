# kotlin-lint Evaluation

## Scope

This note records why [`linters/kotlin-lint`](../../linters/kotlin-lint/plugin.yaml) exists and why it is shaped the way it is, measured on 2026-09-27 against Trunk CLI 1.25.0, `trunk-io/plugins` v1.11.0, and ktlint 1.8.0.
The starting point was a consumer-local `lint.definitions` override written in sing_bridge, which added a SARIF `lint` command to `ktlint`.

## Upstream ktlint Only Formats

The upstream `ktlint` definition has one command, `format`, running `ktlint -F` with `success_codes: [0, 1]`.
`ktlint -F` exits 1 when violations remain that it cannot autocorrect, so a rule such as `standard:function-naming` never fails the gate: a file with `fun Bad_Name()` passes `trunk fmt` and `trunk check` alike.

## Exit Code 1 Also Means ktlint Died

The SARIF command in the sing_bridge override accepts exit code 1 for the same reason, because ktlint exits 1 whenever it reports a violation.
It also exits 1 when it dies before reporting:

```log
java -Xmx2m -jar ktlint --reporter=sarif Naming.kt   -> exit 1, 0 bytes on stdout, OutOfMemoryError on stderr
java        -jar ktlint --reporter=sarif Naming.kt   -> exit 1, 1,366 bytes of SARIF on stdout
```

Trunk read the first run as `No issues` for a file with a real violation.
[`sarif_guard.py`](../../linters/kotlin-lint/sarif_guard.py) runs as the parser and fails the run when stdout is not a SARIF log, which turned the same heap failure into `Some tools failed to run`.
Because the SARIF log also reports fixable rules such as `standard:indent`, the guard covers a formatter that dies the same way.

## A Parse Error at the End of a File Reads as Existing

ktlint reports an unparsable file with an empty `ruleId`, and when the file ends inside an unfinished construct it places the error one line past the end:

```log
"fun (\n"                       -> ruleId "", startLine 2 of a one-line file   -> Trunk: 1 existing issue, No new issues
"val x = 1\nfun (\nval y = 2\n" -> ruleId "", startLine 3 of a three-line file -> Trunk: 1 new lint issue
```

The empty rule id is not the cause; the line outside the file is, because Trunk's hold-the-line treats it as outside the change, so a truncated Kotlin file passed a default `trunk check`.
The guard moves such a location to the file's last line and names the empty rule `parse-error`, after which the first case also reported `kotlin-lint/parse-error` as a new issue.

## A Partial Override of ktlint Is Fragile

A plugin definition named `ktlint` that only adds a `lint` command does merge into the upstream definition.
The parser's `${plugin}`, however, resolved to a different source depending on the consumer's layout:

```log
qc listed before trunk-io/plugins   -> this plugin's root; the guard ran
qc as the only source               -> the CLI's built-in catalog root (trunk-io/plugins v1.2.1); "can't open file"
```

A separate linter name that only this plugin defines has one root in every layout.
Under the name `kotlin-lint` it reported the naming violation, reported an unparsable file as an issue, passed a clean file, and failed on the heap failure with `trunk-io/plugins` listed first, listed second, and absent.
Its `download: ktlint` comes from upstream or from the CLI's built-in catalog, both of which define it.

## Decision

`kotlin-lint` is opt-in, and no profile enables it: the Flutter and React Native profiles already enable `ktlint@1.8.0`, and turning the new check on there would fail every consumer that currently hides a non-fixable violation on its next ref bump.
A consumer runs both linters, `ktlint` for formatting and `kotlin-lint` for the report, so a fixable violation appears twice, once as `Incorrect formatting` and once as a `kotlin-lint/standard:` issue.
The command keeps the sing_bridge override's `-Xmx512m`; the reason for that limit was not recorded, and the guard makes a heap failure visible either way.
The override's replacement `format` command is not carried over, because a plugin command named `format` merged differently by source order:

```log
trunk-io/plugins listed first   -> added as a third format command beside upstream's two
qc listed first                 -> only its platforms field merged into upstream's format; the run stayed upstream's
```

A consumer that wants the heap limit on formatting keeps that command in its own `lint.definitions`, which overrides both sources.
