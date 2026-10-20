#!/usr/bin/env bash
# Compare each flake.lock input's locked rev against the upstream default branch
# and report staleness. Reads the flake.lock on GitHub's main, which is what the
# hosts' auto-updates apply, and says when the local checkout's lock differs.
# Uses raw.githubusercontent.com for that lock and the GitHub commits API for
# upstream (no auth required for public repos; rate-limited).
#
# Usage: agents/scripts/flake-input-freshness.sh [--local] [input-name]
#   With no input name, scans every input.
#   With an input name, scans only that one.
#   --local reads the checkout's flake.lock instead, for unpushed edits.

set -euo pipefail

usage() {
  echo "usage: $0 [--local] [input-name]" >&2
  exit 2
}

use_local=0
target=""
while [ "$#" -gt 0 ]; do
  case "$1" in
    --local) use_local=1 ;;
    -*) usage ;;
    *)
      [ -n "$target" ] && usage
      target="$1"
      ;;
  esac
  shift
done

repo_root=$(git -C "$(dirname "$0")" rev-parse --show-toplevel)
local_json=$(cat "$repo_root/flake.lock")

main_lock_url="https://raw.githubusercontent.com/patatepartie/nix-config/main/flake.lock"
if [ "$use_local" = 1 ]; then
  lock_json="$local_json"
  other_json=""
  printf 'flake.lock: local checkout (--local)\n'
else
  main_json=$(curl -fsS --max-time 20 "$main_lock_url") || {
    echo "could not fetch flake.lock from $main_lock_url (--local reads the checkout's)" >&2
    exit 1
  }
  if ! jq -e '.nodes' >/dev/null 2>&1 <<<"$main_json"; then
    echo "$main_lock_url is not a flake.lock" >&2
    exit 1
  fi
  lock_json="$main_json"
  other_json="$local_json"
  printf 'flake.lock: main on GitHub\n'

  differing=$(jq -r --argjson local "$local_json" '
    def revs: .nodes | del(.root) | map_values(.locked.rev // "-");
    (revs) as $main | ($local | revs) as $loc
    | [($main + $loc) | keys[] | select($main[.] != $loc[.])] | join(",")
  ' <<<"$main_json")
  if [ -n "$differing" ]; then
    printf 'local checkout differs from main for: %s (pull, or use --local for unpushed edits)\n' "$differing"
  fi
fi

check_one() {
  local name="$1"
  local node owner repo locked_rev upstream_rev ahead behind

  node=$(jq -c --arg n "$name" '.nodes[$n] // empty' <<<"$lock_json")
  if [ -z "$node" ]; then
    if [ -n "$other_json" ] && [ -n "$(jq -c --arg n "$name" '.nodes[$n] // empty' <<<"$other_json")" ]; then
      printf '%s: not found in main'"'"'s flake.lock, only in the checkout; try --local\n' "$name" >&2
    else
      printf '%s: not found in flake.lock\n' "$name" >&2
    fi
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

if [ -n "$target" ]; then
  check_one "$target"
  exit
fi

names=$(jq -r '.nodes | keys[] | select(. != "root")' <<<"$lock_json")
for n in $names; do
  check_one "$n" || true
done
