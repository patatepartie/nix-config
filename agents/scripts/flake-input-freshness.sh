#!/usr/bin/env bash
# Compare each flake.lock input's locked rev against the upstream default branch
# and report staleness. Uses only the GitHub commits API (no auth required for
# public repos; rate-limited).
#
# Usage: agents/scripts/flake-input-freshness.sh [input-name]
#   With no argument, scans every input.
#   With an input name, scans only that one.

set -euo pipefail

repo_root=$(git -C "$(dirname "$0")" rev-parse --show-toplevel)
lock="$repo_root/flake.lock"

check_one() {
  local name="$1"
  local node owner repo locked_rev upstream_rev ahead behind

  node=$(jq -c --arg n "$name" '.nodes[$n] // empty' "$lock")
  if [ -z "$node" ]; then
    printf '%s: not found in flake.lock\n' "$name" >&2
    return 1
  fi

  local locked_type
  locked_type=$(jq -r '.locked.type // empty' <<<"$node")
  if [ "$locked_type" != "github" ]; then
    printf '%-20s skipped (locked type=%s, not github)\n' "$name" "$locked_type"
    return 0
  fi

  owner=$(jq -r '.locked.owner' <<<"$node")
  repo=$(jq -r '.locked.repo' <<<"$node")
  locked_rev=$(jq -r '.locked.rev' <<<"$node")

  upstream_rev=$(curl -fsSL "https://api.github.com/repos/${owner}/${repo}/commits/HEAD" 2>/dev/null | jq -r '.sha // empty')
  if [ -z "$upstream_rev" ]; then
    printf '%-20s %s/%s — could not fetch upstream HEAD (rate-limited or 404)\n' "$name" "$owner" "$repo"
    return 0
  fi

  if [ "$locked_rev" = "$upstream_rev" ]; then
    printf '%-20s %s/%s — at HEAD\n' "$name" "$owner" "$repo"
    return 0
  fi

  local compare
  compare=$(curl -fsSL "https://api.github.com/repos/${owner}/${repo}/compare/${locked_rev}...${upstream_rev}" 2>/dev/null) || true
  if [ -n "$compare" ]; then
    ahead=$(jq -r '.ahead_by // "?"' <<<"$compare")
    printf '%-20s %s/%s — locked is behind by %s commits\n' \
      "$name" "$owner" "$repo" "$ahead"
  else
    printf '%-20s %s/%s — locked %s, upstream %s (compare failed)\n' \
      "$name" "$owner" "$repo" "${locked_rev:0:8}" "${upstream_rev:0:8}"
  fi
}

if [ "$#" -gt 0 ]; then
  check_one "$1"
  exit
fi

mapfile -t names < <(jq -r '.nodes | to_entries[] | select(.key != "root") | .key' "$lock")
for n in "${names[@]}"; do
  check_one "$n"
done
