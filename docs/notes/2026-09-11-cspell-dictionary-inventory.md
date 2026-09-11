# Shared CSpell Dictionary Inventory

<!-- cspell:words arpeggiating burstiest counterable GAID Instantitation monetizable seedable unsymbolicated -->

## Purpose

This note records the evidence used to select the first shared personal CSpell terms.
The source is the current `prism_defense` dictionary split and the personal repository inventory under `/Users/dongminyu/Development/01_personal`.
The `prism_defense` files had author-unknown working-tree changes during this investigation.
This repository does not claim ownership of those changes.

## Scan Method

The scan included top-level directories that had a `.git` entry.
The scan excluded `.git`, `.cspell`, `node_modules`, `.dart_tool`, `build`, `coverage`, nested `worktrees`, and lockfiles.
The scan matched complete alphanumeric tokens without case sensitivity.

A term qualified for the first shared list only when all of these conditions were true:

- The term came from one of the domain dictionaries in the current `prism_defense` working tree.
- The term occurred in source files from at least three top-level repositories.
- CSpell 10.2.0 still reported the term when the relevant bundled dictionaries were enabled.
- The term was not a project name, personal identifier, secret, generated identifier, or one-off spelling exception.

The CSpell probe enabled `bash`, `dart`, `en-gb`, `filetypes`, `flutter`, `fonts`, `fullstack`, `game-development`, `gaming-terms`, `git`, `google`, `java`, `kotlin`, `shellscript`, `softwareTerms`, `sql`, and `swift`.
The probe used Markdown input so each dictionary applied to prose and configuration documentation rather than only to its native file type.

## Results

The evidence supports one shared allowlist instead of eight small permanent dictionaries.
The initial list contains terms from Android, Apple platforms, Flutter tooling, advertising, graphics, game development, and general developer tooling.
Examples with strong recurrence include `oxipng` in 48 repositories, `worktree` in 38 repositories, `IPHONEOS` in 25 repositories, `pbxproj` in 24 repositories, `INFOPLIST` and `xcuserdata` in 23 repositories, and `jvmargs` in 19 repositories.
The implementation also admitted `gsub` after a separate scan found it in five repositories.
It admitted `deeplinking` as the name of the centrally managed forbidden-word exception.
The optional VGV layer still forbids that term outside the Android manifest override.

The scan rejected terms that appeared only in copied dictionaries or in fewer than three source repositories.
Examples include `arpeggiating`, `burstiest`, `counterable`, `GAID`, `Instantitation`, `monetizable`, `seedable`, and `unsymbolicated`.
These terms remain consumer-local until new evidence qualifies them.

`dedupe` occurred in 14 repositories but CSpell 10.2.0 already recognized it through a bundled dictionary.
It is not part of the shared list.

## Very Good Dictionaries Policy

The upstream Very Good Dictionaries repository publishes one allowlist and one forbidden list.
Its README references both files through mutable `main` URLs.
This repository must not copy that delivery contract.

The first implementation keeps the external policy optional and pins it to commit `ce6df4f628bbf130b3d6d8ed9637553653fce7db`.
It centralizes syntax exceptions for forbidden spellings that are valid in a constrained file type.
The initial Android manifest exceptions are `deeplinking` and `meta-data`.
The same spellings must remain forbidden outside `AndroidManifest.xml`.

## Limitations

The scan establishes current recurrence, not permanent vocabulary ownership.
Future CSpell releases can add these terms to bundled dictionaries.
Each dependency update must re-run the overlap check and remove terms that CSpell now owns.

The isolated-consumer test proved that Trunk copied the exported CSpell config without making a relative text dictionary available to the CSpell sandbox.
Adding the text file to `lint.exported_configs` did not make the relative path work.
The implementation therefore keeps the admitted words in the exported config's `words` list.

The repeated test run also showed that a cached Pinact result could survive a change to `PINACT_DISABLE_GH_AUTH`.
The isolated canary helpers now disable Trunk result caching so each failure and clean rerun executes the linter under the current environment.
