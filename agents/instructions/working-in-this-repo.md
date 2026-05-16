# Working in nix-config

## Before you act

Read the relevant section below before answering or running commands. The repo's mechanics are not obvious from the file tree.

| If the user mentions…                                       | Read this first                                                    |
|-------------------------------------------------------------|--------------------------------------------------------------------|
| auto-update, daily update, update lag, scheduled rebuild    | "How auto-updates work" (below)                                    |
| update / upgrade the system, refresh `flake.lock`           | "How auto-updates work" + `justfile` (`just upgrade` exists)       |
| brew / cask / homebrew                                      | "Homebrew" (below) — never run mutating brew commands              |
| claude-code banner ("Update available")                     | `agents/instructions/troubleshooting.md`                           |
| ssh / home-server commands                                  | "SSH to home-server.local" (below)                                 |
| commit message format / prefix                              | "Commit prefixes" (below)                                          |

`just --list` shows every recipe. `just upgrade` = `nix flake update && just switch`; it only updates the machine you run it on — other hosts won't pick up the new `flake.lock` until you commit and push.

## How auto-updates work

There are two independent mechanisms.

**1. `flake.lock` updates (GitHub Actions).** `.github/workflows/flake-update.yml` runs `nix flake update` daily at `0 22 * * *` UTC and pushes an "Upgrade flake" commit if anything changed. This advances the locked revs of `nixpkgs`, `nix-darwin`, `home-manager`, `homebrew-cask`, `homebrew-core`, etc. It does NOT touch inputs that are hardcoded to a specific tag in `flake.nix` (e.g. `nix-homebrew.inputs.brew-src.url` is pinned to `github:Homebrew/brew/<tag>`; the manual `nixpkgs` pin if one is in effect).

**2. System rebuild (launchd / systemd, per host).** Defined in:
- `hosts/2023-macbook-pro/modules/auto-update.nix`
- `hosts/2018-macbook-pro/modules/auto-update.nix`
- `hosts/home-server/auto-update.nix` (note: no `modules/` segment — the home-server tree is flatter)

| Host           | Schedule (in module)                                | Action                                                    |
|----------------|-----------------------------------------------------|-----------------------------------------------------------|
| MBP 2023, 2018 | launchd `StartCalendarInterval { Hour=7; Minute=30; }` (machine-local time) | `git fetch && git reset --hard origin/main && darwin-rebuild switch` |
| home-server    | systemd `OnCalendar = "*-*-* 22:30:00 UTC"`         | `git fetch && git reset --hard origin/main && nixos-rebuild switch` (falls back to `boot` if `switchInhibitors` blocks) |

**The auto-update script does NOT run `nix flake update`.** It only applies whatever `flake.lock` is committed in the repo. Tap revisions are therefore at most as fresh as the most recent GitHub-Action commit; if the Action ran at 22:00 UTC and a `homebrew-cask` rev was tagged 23:00 UTC, no host will see it until the next Action run.

**To force an immediate update on every host:** run `just upgrade` locally, then commit and push `flake.lock`. Each host's daemon will pick the new commit up on its next scheduled run. To skip the wait, also run `just switch` (or the underlying `darwin-rebuild` / `nixos-rebuild switch`) on each host. `just upgrade` alone only fixes the machine you ran it on.

**Pinned inputs to watch for in `flake.nix`:** these are temporary workarounds, not established patterns — each one tracks a specific upstream issue and should be removed when it's resolved.
- `nixpkgs.url` is currently pinned to a specific commit (not `nixos-unstable`) to work around an upstream regression. Check the comment immediately above the line for context and the unpin trigger.
- `nix-homebrew.inputs.brew-src.url` is currently overridden to a specific Homebrew CLI tag (e.g. `github:Homebrew/brew/5.1.11`) to front-run a delayed nix-homebrew bump. Tracked by an upstream issue (currently nix-homebrew#140 for 5.1.11); drop the override once nix-homebrew bumps past the pinned version. The override is independent of `flake update` and must be bumped manually.

To check whether either pin can be removed, see `agents/scripts/flake-input-freshness.sh`.

## Diagnostic scripts

Under `agents/scripts/`. Run from the repo root.

- `agents/scripts/cask-version-gap.sh <cask-name>` — prints the cask version locked by `flake.lock`, the version `formulae.brew.sh` is currently advertising (this is the source claude-code's banner compares against), and the locally-installed version. Used to diagnose "Update available" banners and similar version-skew symptoms without manually curling raw.githubusercontent.com.
- `agents/scripts/flake-input-freshness.sh [input-name]` — reports each `flake.lock` input's staleness against its upstream default branch via the GitHub commits API. With no argument scans every input; with an input name scans only that one. Useful to verify whether `nixpkgs` / `nix-homebrew` pins can be dropped, and to gauge how far behind `flake.lock` is overall.

Both scripts use only the GitHub commits API and `formulae.brew.sh` — read-only public endpoints, no auth required. Prefer running them over ad-hoc `curl`s to `raw.githubusercontent.com` or similar.

## Homebrew

Never run `brew tap`, `brew install`, `brew uninstall`, `brew bundle`, or `brew cleanup`. All Homebrew config (taps, brews, casks) is managed declaratively through nix-darwin. To add a package, modify the appropriate nix file (`brews.nix`, `casks.nix`) and apply via `just switch`. Read-only commands (`brew list`, `brew info`, `brew outdated`) are fine.

Casks declared with `greedy = true` (see `hosts/2023-macbook-pro/modules/apps/casks.nix`) tell `brew upgrade` not to skip casks that have `auto_updates true` or `version :latest` in their cask file — i.e. casks Homebrew would normally leave alone because the app handles updates itself. For a cask with a pinned `version "X.Y.Z"` (no `auto_updates`), `greedy` is effectively a no-op: the cask is upgraded whenever the locked `homebrew-cask` rev in `flake.lock` advances past the pinned version. `claude-code` falls in this category — `greedy = true` is set defensively but doesn't change behavior today.

## Commit prefixes

Prefix commit titles based on which hosts are affected:
- **MBP2018** — 2018 MacBook Pro only
- **MBP2023** — 2023 MacBook Pro only
- **MBPs** — both MacBook Pros
- **HomeServer** — home server only
- No prefix — all hosts or host-agnostic changes

## tmux

Always use `command tmux` instead of bare `tmux`. The oh-my-zsh tmux plugin intercepts bare `tmux` and fails in non-interactive shells.

## Nix rebuild output

After any `just switch` or nix eval, report all warnings to the user — don't silently ignore them.

## Remote machines

Cannot run `sudo` over SSH to remote machines. When an operation needs sudo on the home server, tell the user what command to run rather than attempting it.

## SSH to home-server.local

Use unquoted form for read-only SSH commands so auto-approval rules match:
```
ssh home-server.local journalctl -u foo --no-pager     # auto-approved
ssh home-server.local "journalctl -u foo --no-pager"   # prompts (quoted form breaks prefix match)
```
For commands requiring shell metacharacters on the remote side (`*`, `|`, `>`, `;`), quoted form is fine — the resulting prompt is intentional.
