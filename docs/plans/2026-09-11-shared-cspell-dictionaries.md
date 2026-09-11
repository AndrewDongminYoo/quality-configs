# Shared CSpell Dictionaries Implementation Plan

<!-- cspell:words mispellled -->

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:subagent-driven-development` or `superpowers:executing-plans` to implement this plan task by task.

**Goal:** Add a versioned shared technical allowlist and an optional pinned Very Good Dictionaries policy with Android manifest exceptions.

**Architecture:** The universal exported CSpell config contains one repository-owned allowlist.
An optional configuration layer enables the pinned external allowed and forbidden dictionaries with file-scoped syntax exceptions.
Existing local consumer configurations retain final precedence.

**Tech Stack:** CSpell 10.2.0, Trunk 1.25.0, YAML, and shell verification scripts.

**Spec:** `docs/specs/2026-09-11-shared-cspell-dictionaries.md`

## Global Constraints

- Keep `plugin.yaml` ecosystem-agnostic.
- Set `addWords: false` for each external dictionary definition.
- Keep the shared inline allowlist sorted case-insensitively.
- Keep product names, personal identifiers, secrets, generated identifiers, and one-off exceptions out of the shared list.
- Pin Very Good Dictionaries to `ce6df4f628bbf130b3d6d8ed9637553653fce7db`.
- Restrict `deeplinking` and `meta-data` exceptions to `**/AndroidManifest.xml`.
- Do not modify `prism_defense` in this implementation.
- Do not commit, push, publish, or migrate consumers without a separate request.

---

### Task 1: Prove the missing shared-dictionary behavior

**Files:**

- Create: `tests/fixtures/clean/cspell-shared.md`
- Modify: `scripts/test-plugin.sh`

**Interfaces:**

- Consumes: The existing `expect_failure` and `expect_success` helpers.
- Produces: A baseline-consumer assertion that requires `jvmargs`, `pbxproj`, `flutterfire`, and `worktree` to resolve through the exported config.

- [x] Add a fixture that contains `jvmargs`, `pbxproj`, `flutterfire`, and `worktree` in ordinary Markdown prose.
- [x] Add an `expect_success cspell` check for the fixture after the existing intentional misspelling check.
- [x] Run `./scripts/test-plugin.sh` with external `TMPDIR` and `TRUNK_CACHE` locations.
- [x] Confirm that CSpell fails on at least one shared term because the dictionary does not exist yet.

### Task 2: Add the shared allowlist

**Files:**

- Modify: `configs/cspell.config.yaml`
- Modify: `.cspell/custom-dictionary.txt`

**Interfaces:**

- Consumes: The admitted word set in `docs/notes/2026-09-11-cspell-dictionary-inventory.md`.
- Produces: The universal shared `words` list in the exported config.

- [x] Add the admitted technical terms to `configs/cspell.config.yaml` with source spelling and case-insensitive sort order.
- [x] Retain `dotenv`, `gradlew`, `oxipng`, `Podfile`, `shellcheck`, and `shfmt` in the expanded shared `words` list.
- [x] Move `lockfiles`, `pbxproj`, and `worktree` out of the repository-local custom dictionary because the shared allowlist now owns them.
- [x] Run the isolated test again and confirm that the shared fixture passes while `mispellled` still fails.

### Task 3: Centralize optional forbidden-word exceptions

**Files:**

- Create: `configs/cspell/vgv.config.yaml`
- Create: `tests/fixtures/clean/AndroidManifest.xml`
- Create: `tests/fixtures/violations/cspell-vgv.md`
- Modify: `scripts/test-plugin.sh`

**Interfaces:**

- Consumes: Very Good Dictionaries commit `ce6df4f628bbf130b3d6d8ed9637553653fce7db`.
- Produces: An opt-in CSpell config named `configs/cspell/vgv.config.yaml`.

- [x] Add pinned `vgv_allowed` and `vgv_forbidden` dictionary definitions.
- [x] Add an `**/AndroidManifest.xml` override for `deeplinking` and `meta-data`.
- [x] Add a Markdown violation fixture that contains `meta-data`.
- [x] Add an Android manifest clean fixture that contains `deeplinking` and `meta-data`.
- [x] Configure an isolated consumer to import `configs/cspell/vgv.config.yaml`.
- [x] Confirm that the Markdown fixture fails for `meta-data`.
- [x] Confirm that the Android manifest fixture passes.
- [x] Confirm that no Very Good Dictionaries URL contains `/main/`.
- [x] Disable Trunk result caching in the failure and success canary helpers.

### Task 4: Document consumption and verify the repository

**Files:**

- Modify: `README.md`
- Modify: `docs/plans/2026-09-11-shared-cspell-dictionaries.md`

**Interfaces:**

- Consumes: The proven exported and optional configuration behavior.
- Produces: Consumer instructions and a completed verification record.

- [x] Document the shared allowlist, the admission boundary, and the optional VGV policy.
- [x] Document that local configs must import the desired layer through an immutable `quality-configs` tag or SHA.
- [x] Run `trunk fmt --no-fix --diff=full README.md AGENTS.md plugin.yaml configs profiles docs scripts tests .trunk`.
- [x] Run `trunk check --all --no-fix`.
- [x] Run `./scripts/test-plugin.sh` with external `TMPDIR` and `TRUNK_CACHE` locations.
- [x] Run `git diff --check`.
- [x] Review staged, unstaged, and untracked paths without staging or committing them.
