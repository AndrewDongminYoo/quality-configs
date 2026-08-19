# Repository Guidelines

## Scope

This repository publishes reusable quality configuration for repositories owned by `AndrewDongminYoo`.
Keep the root Trunk plugin ecosystem-agnostic and place stack-specific behavior under `profiles/`.

## Editing Rules

Prefer small policy changes backed by either the owned-repository inventory in `docs/notes/` or a primary upstream source.
Do not add project names, secrets, generated identifiers, or one-off spelling exceptions to the shared CSpell configuration.
Do not enable a mutating formatter action by default.
Keep mobile asset optimizers disabled unless a profile explicitly opts into them.
Treat linter versions as an upgrade snapshot, not as permanent compatibility pins.

## Documentation

Write durable plans in `docs/plans/`, specifications in `docs/specs/`, and investigation notes in `docs/notes/`.
Use sentence-level line breaks, do not hard-wrap prose, and add a language identifier to every fenced code block.

## Verification

Run the following checks before proposing a release:

```bash
trunk fmt --no-fix --diff=full README.md AGENTS.md plugin.yaml configs profiles docs scripts tests .trunk
trunk check --all --no-fix
git diff --check
```

Also run the isolated consumer proof documented in `README.md` whenever `plugin.yaml`, an exported config, or a profile changes.
