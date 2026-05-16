#!/usr/bin/env bash
# UserPromptSubmit hook for the nix-config repo.
# Reads JSON from stdin, inspects the user's prompt for repo-specific keywords,
# and injects authoritative pointers into Claude's context via additionalContext.
# Silent (no output) when no keyword matches.
set -euo pipefail

prompt=$(jq -r '.prompt // empty')
context=""

if echo "$prompt" | grep -qiE 'auto[- ]?update|cron|launchd|systemd timer|scheduled rebuild|update lag'; then
  context="${context}- For auto-update questions: read agents/instructions/working-in-this-repo.md section 'How auto-updates work' before answering. The two mechanisms (GitHub Action for flake.lock at 22:00 UTC, launchd/systemd for darwin-rebuild/nixos-rebuild) live in .github/workflows/flake-update.yml and hosts/<host>/modules/auto-update.nix (or hosts/home-server/auto-update.nix).
"
fi

if echo "$prompt" | grep -qiE 'claude[- ]?code|update available|brew upgrade claude'; then
  context="${context}- The 'Update available! Run: brew upgrade claude-code' banner is emitted by claude-code itself (PackageManagerAutoUpdater), polling https://formulae.brew.sh/api/cask/claude-code.json on startup. brew bundle is bound to the homebrew-cask rev locked in flake.lock; the banner reflects upstream homebrew-cask, not your locked rev. See agents/instructions/troubleshooting.md and commit f78ccbe for the stable/latest channel history.
"
fi

if echo "$prompt" | grep -qiE '\bbrew\b|\bcask\b|homebrew'; then
  context="${context}- Homebrew is declarative via nix-darwin. Never run brew install/uninstall/bundle/cleanup. Read-only commands (brew list/info/outdated) are fine. Edit hosts/<host>/modules/apps/{casks,brews}.nix and run just switch.
"
fi

if echo "$prompt" | grep -qiE '\bupdate\b|\bupgrade\b|\brebuild\b|\bswitch\b|flake\.lock|flake update'; then
  context="${context}- Use just recipes: 'just switch' (apply), 'just build' (no-apply), 'just update' (flake update), 'just upgrade' (update + switch). Run 'just --list' to confirm. just upgrade only updates the local machine; other hosts need the flake.lock to be committed and pushed.
"
fi

if [ -n "$context" ]; then
  jq -nc --arg ctx "Project reminders (auto-injected based on keywords in your prompt):
$context" '{hookSpecificOutput: {hookEventName: "UserPromptSubmit", additionalContext: $ctx}}'
fi
