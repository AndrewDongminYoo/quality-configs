# gdtoolkit Linter Evaluation

## Scope

This note records why [`linters/gdtoolkit`](../../linters/gdtoolkit/plugin.yaml) defines `gdformat` and `gdlint` the way it does, measured on 2026-09-26 against Trunk CLI 1.25.0, `trunk-io/plugins` v1.11.0, and gdtoolkit 4.5.0.
The definitions are meant to be tried in owned Godot repositories before they are proposed upstream.

## Upstream Has No GDScript Support

`trunk-io/plugins` v1.11.0 has no `linters/` directory whose name contains `gd` or `godot`, and a GitHub code search for `gdformat` in that repository returned zero results.
The bundled `linters/plugin.yaml` file catalog has no `gdscript` file type either, so the definition file declares one with `hash` comments, which is what `trunk-ignore` needs.
Because no name collides, the definitions take effect whether or not a consumer keeps the upstream source; a scratch consumer listing both sources reported the same `gdlint` findings as one without `trunk-io/plugins`.

## Exit Code 1 Means Two Things

`gdlint` exits 1 when it reports a rule finding and also when it cannot parse a file:

```log
bad.gd:3: Error: Class-scope variable name "BadName" is not valid (class-variable-name)
Failure: 1 problem found                                   -> exit 1
syntax.gd:
<source context>
Unexpected token Token('LPAR', '(') at line 1, column 6.
Failure: 1 problem found                                   -> exit 1
```

A regex over the finding lines would read the second case as clean, which is the same shape CSpell produced in [`2026-08-19-trunk-reuse-findings.md`](./2026-08-19-trunk-reuse-findings.md).
The parse block has three observed forms: `at line L, column C` for an unexpected token, `at line L col C` for an unexpected character, and a dedent error with no position at all.

[`gdlint_to_sarif.py`](../../linters/gdtoolkit/gdlint_to_sarif.py) therefore parses both shapes, reports a parse block as `gdlint/parse-error`, and compares the number of parsed items with the count in gdlint's `Failure:` line.
A mismatch, exit 1 without that line, or any other exit code fails the run instead of reporting fewer issues than gdlint found.
Dropping the finding lines from a sample made the parser exit 1 with `gdlint reported 4 problems but 3 were parsed`, and a bare Python traceback on exit 1 failed the same way.
Inside Trunk, a copy of the parser whose parse-block pattern never matches turned an unparsable file into `Some tools failed to run` with exit 1, not into a clean result.

## Trunk Behavior Measured in a Scratch Consumer

- **Configuration files are honored.** Both tools search for `gdlintrc` and `gdformatrc` upward from the working directory, so both commands use `run_from: ${root_or_parent_with_any_config}` with those names as `direct_configs`. With `max-line-length: 120` and `line_length: 120` placed only in `sub/`, a 117-column line was reported in `long.gd` and accepted in `sub/long.gd` by both tools.
- **Paths stay correct under a nested `run_from`.** Findings in `sub/bad.gd` and `sub/syntax.gd` were reported at those paths.
- **An unparsable file does not block its batch.** `trunk fmt` over one unformatted file and one unparsable file still produced the diff for the first and reported `gdformat` as a tool failure for the second only.
- **`trunk-ignore` works.** `# trunk-ignore(gdlint/class-variable-name)` suppressed the finding on the next line, and replacing that comment with a plain comment brought the finding back.

## First Consumer Measurement

gdtoolkit 4.5.0 with default settings, run directly over the 85 tracked `.gd` files of chef-al-mando (Godot 4.7.2):

```log
gdlint    1400 problems, exit 1
          1373 max-line-length
            14 max-returns
             7 duplicated-load
             4 max-file-lines
             1 class-definitions-order
             1 parse error (tests/capture_m2.gd:50:110)
gdformat  70 files would be reformatted, 15 left unchanged
```

The parser accounted for all 1,400 problems in that output, including the parse error.
Almost every finding comes from the default 100-column limit, so the first adoption step is a project `gdlintrc` and `gdformatrc` with a line length that matches the existing code, and the whole-tree reformat belongs in its own change.
gdtoolkit 4.5.0 cannot parse the `a == not b` expression on that line, and `gdformat` fails on the same file, so that file needs a `lint.ignore` entry or a rewrite before either tool covers it.
Whether Godot itself accepts the expression was not checked.

## Decision

Neither linter is enabled by the root plugin, because it stays ecosystem-agnostic, and a Godot repository enables `gdformat@4.5.0` and `gdlint@4.5.0` itself.
Both use `suggest_if: config_present`, so `trunk init` proposes them only in a repository that already carries a gdtoolkit rc file, rather than proposing a formatter that would rewrite most files of a repository that never chose one.
`scripts/test-plugin.sh` covers a finding, a parse error, a clean file, and the rc-file override in the standalone scenario.
