#!/usr/bin/env bash
# Report the version gap for a Homebrew cask between:
#   - the cask file at the homebrew-cask rev locked in flake.lock
#   - what formulae.brew.sh (Homebrew's metadata API) reports — this is the
#     source that drives the "Update available" banner inside claude-code
#   - what brew has actually installed locally
#
# Usage: agents/scripts/cask-version-gap.sh <cask-name>
# Example: agents/scripts/cask-version-gap.sh claude-code

set -euo pipefail

cask="${1:-}"
if [ -z "$cask" ]; then
  echo "usage: $0 <cask-name>" >&2
  exit 2
fi

repo_root=$(git -C "$(dirname "$0")" rev-parse --show-toplevel)
lock="$repo_root/flake.lock"

locked_rev=$(jq -r '.nodes."homebrew-cask".locked.rev' "$lock")
if [ "$locked_rev" = "null" ] || [ -z "$locked_rev" ]; then
  echo "could not read homebrew-cask rev from $lock" >&2
  exit 1
fi

first_letter=$(printf '%s' "$cask" | cut -c1)
locked_url="https://raw.githubusercontent.com/Homebrew/homebrew-cask/${locked_rev}/Casks/${first_letter}/${cask}.rb"
locked_cask=$(curl -fsSL "$locked_url" 2>/dev/null || true)
if [ -z "$locked_cask" ]; then
  echo "could not fetch cask file at locked rev: $locked_url" >&2
  echo "(cask may not exist, or the rev may have been GC'd)" >&2
  exit 1
fi
# Match the first `version "X"` at any indent — some casks pin version per-OS inside `on_*` blocks.
locked_version=$(printf '%s\n' "$locked_cask" | awk -F'"' '/^[[:space:]]*version "/{print $2; exit}')

upstream_version=$(curl -fsSL "https://formulae.brew.sh/api/cask/${cask}.json" 2>/dev/null | jq -r '.version')

installed_version="(not installed)"
brew_prefix=$(command -v brew >/dev/null 2>&1 && brew --prefix 2>/dev/null || true)
if [ -n "$brew_prefix" ] && [ -d "$brew_prefix/Caskroom/$cask" ]; then
  # Take the highest-versioned directory in the Caskroom (skip dotfiles like .metadata).
  installed_version=$(ls -1 "$brew_prefix/Caskroom/$cask" 2>/dev/null | grep -v '^\.' | sort -V | tail -1)
  [ -z "$installed_version" ] && installed_version="(installed, version unknown)"
fi

printf 'cask:              %s\n' "$cask"
printf 'flake.lock rev:    %s\n' "$locked_rev"
printf 'locked version:    %s\n' "${locked_version:-(failed to fetch)}"
printf 'formulae.brew.sh:  %s\n' "${upstream_version:-(failed to fetch)}"
printf 'installed:         %s\n' "$installed_version"

if [ -n "$locked_version" ] && [ -n "$upstream_version" ] && [ "$locked_version" != "$upstream_version" ]; then
  printf '\nGAP: flake.lock is behind formulae.brew.sh by %s -> %s. The "Update available" banner is expected until flake.lock advances.\n' "$locked_version" "$upstream_version"
fi
