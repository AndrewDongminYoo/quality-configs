#!/usr/bin/env bash
# Pre-commit action: print any finding Claude Code's automatic security-review
# sessions produced for a session opened at this repository's root in the
# last two days.
#
# This is a thin adapter, not the lookup. The lookup lives in the guard-hooks
# Claude Code plugin (github.com/AndrewDongminYoo/cc-agents-kit, hook
# `security-review-findings.sh`), which owns the transcript format, the slug
# derivation, and the nested-verdict unwrapping. Keeping one copy of that logic
# is the point: this script finds the installed plugin and calls its --print
# mode, so a consumer repository gets the same output at the terminal that a
# Claude Code session gets after `git commit`.
#
# Warns only, never blocks — the findings describe work that is already
# committed or already discarded, and some are false positives. Silent when
# Claude Code, its plugin manifest, the guard-hooks plugin, or jq is absent: a
# machine without Claude Code has no findings to show, and a consumer must be
# able to enable this action without installing anything.

set -euo pipefail

CONFIG_DIR="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
MANIFEST="$CONFIG_DIR/plugins/installed_plugins.json"
[[ -f "$MANIFEST" ]] || exit 0
command -v jq >/dev/null 2>&1 || exit 0

INSTALL_PATH=$(jq -r '.plugins["guard-hooks@cc-agents-kit"][0].installPath // empty' "$MANIFEST" 2>/dev/null || true)
[[ -n "$INSTALL_PATH" ]] || exit 0

HOOK="$INSTALL_PATH/hooks/security-review-findings.sh"
[[ -f "$HOOK" ]] || exit 0

# The hook keys its lookup by the Claude Code SESSION's cwd, which a terminal
# commit does not have. The repository root stands in for it: every automatic
# review observed so far belonged to a session opened there, and a session
# opened in a subdirectory is the one case this adapter cannot see.
REPO_ROOT=$(git rev-parse --show-toplevel 2>/dev/null) || exit 0
exec bash "$HOOK" --print "$REPO_ROOT"
