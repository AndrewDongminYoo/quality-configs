# Shared CSpell Dictionaries Specification

## Status

Approved for implementation on 2026-09-11.

## Problem

Personal repositories repeat technical terms in repository-local CSpell dictionaries because the enabled bundled dictionaries do not recognize the terms in all checked file types.
Copied local dictionaries hide ownership, retain unused terms, and require the same correction in multiple repositories.

The optional Very Good Dictionaries forbidden list also rejects syntax that is valid in a constrained context.
For example, Android uses `meta-data` in `AndroidManifest.xml`.
Each consumer currently has to recreate the same exception.

## Goals

- Give recurring personal technical vocabulary one versioned source in `quality-configs`.
- Keep project-specific vocabulary in each consumer repository.
- Apply external forbidden-word policy only when a consumer opts in.
- Centralize file-scoped exceptions for valid syntax such as Android manifest elements.
- Preserve CSpell support for repositories without `package.json`.
- Preserve consumer-local override precedence.
- Make an unreachable dictionary or configuration fail visibly.

## Non-Goals

- Do not create or publish an npm dictionary package.
- Do not move product names, personal identifiers, secrets, generated identifiers, or one-off exceptions into the shared list.
- Do not enable the Very Good Dictionaries policy for every consumer through the universal baseline.
- Do not migrate any consumer repository in this change.
- Do not modify the existing author-unknown changes in `prism_defense`.

## Architecture

`configs/cspell.config.yaml` contains the single allowlist for recurring personal technical vocabulary in its `words` list.
The entries must use their source spelling and must sort case-insensitively.
The list must not contain category comments.
An inline list is required because the isolated consumer proved that Trunk's copied CSpell sandbox does not make a relative text dictionary available, even when the text file appears in `lint.exported_configs`.
The exported configuration remains the universal baseline for consumers that do not have a local CSpell configuration.

`configs/cspell/vgv.config.yaml` is an optional policy layer.
It defines `vgv_allowed` and `vgv_forbidden` with raw URLs pinned to Very Good Dictionaries commit `ce6df4f628bbf130b3d6d8ed9637553653fce7db`.
It enables both dictionaries and adds file-scoped exceptions.
The initial override applies only to `**/AndroidManifest.xml` and ignores `deeplinking` and `meta-data` there.

Consumers that have a local CSpell configuration continue to own scan paths, project vocabulary, and local exceptions.
Those consumers must import or define the selected shared layers explicitly because a local root configuration takes precedence over a Trunk exported configuration.
Published consumers must reference a `quality-configs` release tag or commit SHA and must not reference mutable `main`.

## Word Admission Policy

A new shared allowed term must satisfy all of these requirements:

- The actual CSpell gate reports the term after relevant bundled dictionaries are enabled.
- `cspell trace` or an equivalent CSpell 10.2.0 probe confirms that the selected bundled dictionaries do not own the term for the checked context.
- Source files in at least three independent personal repositories contain the term.
- The reviewer can state the technical meaning of the term.
- A file-scoped override, pattern, path exclusion, or source correction is not more precise.

A term must stay consumer-local when it is a product name, repository name, personal identifier, team identifier, secret, generated identifier, or one-off domain term.
A forbidden spelling that is valid only in one file type must use a scoped `overrides` entry instead of a global `ignoreWords` entry.

## Consumer Contract

The universal exported config must accept the shared allowlist terms without a consumer-local dictionary.
An existing local CSpell config must retain final precedence.
The optional VGV policy layer must not load unless the consumer explicitly imports it.

The external Very Good Dictionaries URLs must use the pinned upstream commit.
The configuration must not fall back to mutable `main` after a fetch failure.
CSpell must report a dictionary error and return a nonzero status if an external dictionary is unavailable.

## Verification Requirements

The isolated baseline consumer must prove this sequence:

1. A selected shared technical term fails before the shared allowlist is present.
2. The same fixture passes after the exported shared allowlist is present.
3. The existing misspelling fixture still fails.
4. A consumer-local CSpell config still overrides the exported config.

The optional VGV policy test must prove this sequence:

1. `meta-data` fails in Markdown.
2. `meta-data` passes in `AndroidManifest.xml`.
3. `deeplinking` passes in `AndroidManifest.xml`.
4. The VGV URLs contain the exact upstream commit.

The repository must also pass the declared formatting, Trunk, isolated consumer, and Git diff checks.
The isolated failure and success canaries must disable Trunk result caching so environment changes cannot reuse stale linter output.

## Rollout

Release the shared source before changing consumers.
Migrate one consumer repository at a time.
For each consumer, add the immutable shared reference first, verify its actual CSpell gate, and then delete duplicate local entries.
`prism_defense` is the first intended consumer, but its migration is outside this implementation.
