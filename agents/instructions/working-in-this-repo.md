# Working in nix-config

## Before you act

Read the relevant section below before answering or running commands. The repo's mechanics are not obvious from the file tree.

| If the user mentions…                                       | Read this first                                                    |
|-------------------------------------------------------------|--------------------------------------------------------------------|
| auto-update, daily update, update lag, scheduled rebuild    | "How auto-updates work" (below)                                    |
| update / upgrade the system, refresh `flake.lock`           | "How auto-updates work" + `justfile` (`just upgrade` exists)       |
| brew / cask / homebrew                                      | "Homebrew" (below) — never run mutating brew commands              |
| claude-code banner ("Update available")                     | `agents/instructions/troubleshooting.md`                           |
| a tap package stuck at an old version, tap not updating     | `agents/instructions/troubleshooting.md` — check for a duplicate tap dir |
| `just switch` / bundler error, formula unreadable, DSL keyword | `agents/instructions/troubleshooting.md` — bump the pin, never remove it |
| ssh / home-server commands                                  | "SSH to home-server.local" (below)                                 |
| commit message format / prefix                              | "Commit prefixes" (below)                                          |
| starting any edit in this repo                               | "Sync before editing" (below)                                      |

`just --list` shows every recipe. `just upgrade` = `nix flake update && just switch`; it only updates the machine you run it on — other hosts won't pick up the new `flake.lock` until you commit and push.

## Sync before editing

Before making any change in this repo, run `git fetch` and check the local branch against `origin/main` (`git status` after fetching, or `git rev-list --count HEAD..@{u}`). If local is behind, pull (fast-forward) before editing.

The daily GitHub Action (see "How auto-updates work" below) pushes an "Upgrade flake" commit most days, often re-locking `flake.lock` inputs unrelated to whatever you're changing. Editing on a stale base and then hand-updating `flake.lock` for your own change can silently drop that commit's updates — there's no merge conflict to flag it, since `flake.lock` edits are usually non-overlapping. Fetching first avoids reconstructing the merge after the fact.

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

**Watch for pinned inputs in `flake.nix`.** One active: `nix-homebrew.inputs.brew-src.url` pins the `brew` CLI to a tag newer than the one `nix-homebrew` ships, because `homebrew-core` formulae keep adopting InstallSteps DSL features that older `brew` cannot parse. It needs a **manual bump** whenever a formula fails to read — the nightly Action advances the taps but can never advance `brew-src`. This is deliberate: tracking brew's latest tag automatically is equivalent to no pin, which is the state that broke `just switch` continuously. See `agents/instructions/troubleshooting.md` → "formula unreadable / unknown DSL keyword" for the bump procedure before touching it.

When upstream regressions force a temporary pin (commit-pinned `nixpkgs.url`, an explicit `inputs.<name>.url` override on a sub-flake, etc.), the pin should carry a comment above the line explaining what it works around and the trigger to drop it. Treat any pin as a workaround that needs removing — not as established configuration. To check whether a pin can now be removed, run `agents/scripts/flake-input-freshness.sh [input-name]` and verify the upstream issue tracked by the pin's comment is resolved.

## Diagnostic scripts

Under `agents/scripts/`. Run from the repo root.

- `agents/scripts/cask-version-gap.sh <cask-name>` — prints the cask version locked by `flake.lock`, the version `formulae.brew.sh` is currently advertising (this is the source claude-code's banner compares against), and the locally-installed version. Used to diagnose "Update available" banners and similar version-skew symptoms without manually curling raw.githubusercontent.com.
- `agents/scripts/flake-input-freshness.sh [input-name]` — reports each `flake.lock` input's staleness against its upstream default branch via the GitHub commits API. With no argument scans every input; with an input name scans only that one. Useful to verify whether `nixpkgs` / `nix-homebrew` pins can be dropped, and to gauge how far behind `flake.lock` is overall.
- `agents/scripts/test-tmux-resurrect.sh [--keep]` — end-to-end test of the tmux save/restore chain (save → kill server → restore → assistant hook) on a throwaway tmux server. **Run this after any change to the tmux/resurrect/continuum config in `home.nix`.** See "tmux session save/restore" below.

Both scripts use only the GitHub commits API and `formulae.brew.sh` — read-only public endpoints, no auth required. Prefer running them over ad-hoc `curl`s to `raw.githubusercontent.com` or similar.

## Homebrew

Never run `brew tap`, `brew install`, `brew uninstall`, `brew bundle`, or `brew cleanup`. All Homebrew config (taps, brews, casks) is managed declaratively through nix-darwin. To add a package, modify the appropriate nix file (`brews.nix`, `casks.nix`) and apply via `just switch`. Read-only commands (`brew list`, `brew info`, `brew outdated`) are fine.

Casks declared with `greedy = true` (see `hosts/2023-macbook-pro/modules/apps/casks.nix`) tell `brew upgrade` not to skip casks that have `auto_updates true` or `version :latest` in their cask file — i.e. casks Homebrew would normally leave alone because the app handles updates itself. For a cask with a pinned `version "X.Y.Z"` (no `auto_updates`), `greedy` is effectively a no-op: the cask is upgraded whenever the locked `homebrew-cask` rev in `flake.lock` advances past the pinned version. `claude-code` falls in this category — `greedy = true` is set defensively but doesn't change behavior today.

## tmux session save/restore

Live Claude sessions are restored on restart by a chain of three pieces, all configured in `hosts/2023-macbook-pro/home.nix`: tmux-continuum (auto-save timer) → tmux-resurrect (windows/panes/layout) → tmux-assistant-resurrect (relaunches `claude --resume <id>` per pane, via resurrect's `post-restore-all` hook).

This chain has broken repeatedly, each time costing a full set of live sessions, and each failure was **silent** — no error, just bare shells after a restart. Known modes, all of which have actually happened:

- **Hook fires before its option is set.** `restore.sh` reads `@resurrect-hook-post-restore-all` at call time. If the restore trigger runs before that `set -g` line, resurrect rebuilds every window and pane correctly and the assistant hook never runs. The layout looks perfect; every session is gone. Keep the `run-shell` restore trigger BELOW the `@resurrect-*` block.
- **Theme clobbers auto-save.** continuum has no timer; it drives saves off a `#(...continuum_save.sh)` interpolation in `status-right`. Catppuccin sets `status-right` wholesale after continuum loads, silently ending auto-save. Re-append it after the theme.
- **GC'd store paths.** A long-lived server keeps the `@resurrect-*` script paths it read at startup. After a rebuild + `nix-gc` those can point at deleted files, so saves fail silently. Re-assert the paths on every config load.

**Always run `agents/scripts/test-tmux-resurrect.sh` after touching any of this.** It exercises the real save → restore → hook cycle on a throwaway server and asserts the post-restore hook actually fired — the check that catches the first mode above, which layout-only checks pass right through. It is heavily isolated (separate socket, sandboxed `HOME`, PATH shim, `-f /dev/null`, faked `TMUX`); during development it leaked a session onto the live server twice, so do not weaken any of those layers. Read the header comment before editing it.

**Recovering lost sessions.** Transcripts live in `~/.claude/projects/<slug>/<session-id>.jsonl` and survive independently of tmux — a lost pane is almost never lost work. `~/.tmux/resurrect/assistant-sessions.json` maps panes to session IDs. Sessions started from Agent View are forks whose own IDs may have no transcript; their history is under the parent session in `~/.claude/jobs/<short-id>/` (`state.json` has `sessionId`, `intent`, and `cwd`). Check there before concluding a session is unrecoverable.

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
