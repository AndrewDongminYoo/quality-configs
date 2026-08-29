# Trunk Reuse Findings

## Scope

These findings came from implementing and releasing `quality-configs` `v0.1.0` on 2026-08-19.
They describe failure modes that materially affect whether a shared Trunk plugin reports trustworthy results in consumer repositories.

## Initialization Is Not Distribution

`trunk init` detects a consumer repository and writes consumer-local runtimes, actions, and linters.
It does not select an external plugin or a named profile.
Because consumer-local `.trunk/trunk.yaml` values override the external plugin, remote defaults alone cannot enforce the runtime and action contract after initialization.

Use two explicit layers:

1. The external `plugin.yaml` distributes universal linters and exported configs.
2. Exactly one consumer-local profile overlay replaces generated runtime and action values and adds stack-specific tools.

This is simpler and more observable than introducing a custom YAML merger before the profile contract has been proven across consumers.

## A Tool Failure Can Look Clean

CSpell 10.0.1 rejected the surveyed `node@22.16.0` runtime because it requires Node 22.18.0 or newer.
The process exited with code 1, which the Trunk CSpell integration also accepts for ordinary spelling findings.
The engine-error output did not produce a parsed spelling issue, so Trunk displayed a false clean result.

The baseline therefore uses `node@22.22.3`, but the reusable rule is broader: never trust a clean wrapper result until a deliberate violation has been rejected.
Every shared linter needs a negative canary followed by a clean positive rerun, especially when a tool uses the same exit code for findings and operational failures.

## Test the Consumer, Not Only the Plugin File

A reliable external-plugin test needs a real temporary Git repository with committed fixtures because `trunk init` cannot analyze a repository without committed files.
Local plugin resolution can also reuse an older cached snapshot when the same source identity is repeated during development.
The verification script therefore copies the plugin into a unique temporary path, assigns a unique plugin ID, commits a unique marker, and exercises the resolved configuration from isolated baseline and profile consumers.

The proof must include:

- All expected runtimes, linters, and exported configs in `trunk config print`.
- Intentional failures and clean reruns for CSpell, Markdownlint, Prettier, and yamllint.
- A consumer-local CSpell config overriding the exported default.
- A Dart code-fence canary proving `prettier-plugin-markdown-dart` runs in the Flutter profile.
- Tailwind class ordering and SVGO canaries proving the Next.js profile packages are active.

## Keep Ecosystem Plugins in Profiles

The universal Prettier config stays plugin-free so every consumer can load it without installing Dart or Tailwind packages.
The Flutter profile supplies `prettier-plugin-markdown-dart`, while the Next.js profile supplies `prettier-plugin-tailwindcss`.
Each profile uses an ESM `prettier.config.mjs`, and Trunk supplies the matching package version for its sandbox.
Editor integration and project-owned Prettier scripts still need the package in the consumer dependency graph, and the Markdown Dart plugin still needs `dart` on `PATH`.

Plugin-specific Prettier configs also affect repository self-validation because Prettier discovers the nearest config before formatting nearby profile files.
The root Trunk config excludes those profile directories from its generic Prettier run, while isolated profile consumers remain responsible for exercising them.

## Shared Defaults Must Not Add Silent Mutation

The shared plugin enables the non-formatting pre-push check and update notifications but leaves `trunk-fmt-pre-commit` disabled.
Each local profile repeats that action contract because values written by `trunk init` can otherwise win during config merging.
Consumers may opt into automatic formatting after reviewing their real diff, but installing a shared policy must not silently widen mutation.

## Durable Verification

The release gate is:

```bash
trunk fmt --no-fix --diff=full README.md AGENTS.md plugin.yaml cspell.config.yaml configs profiles docs scripts tests .trunk
trunk check --all --no-fix
./scripts/test-plugin.sh
```

The first two commands validate the repository itself.
The last command proves the external-plugin and profile behavior from isolated consumers, including failure canaries and local override precedence.
