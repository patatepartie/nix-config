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
| gascity / `gc`, duplicated tmux sessions, CPU spike after `gc start` | "gascity" (below) + "tmux session save/restore"                    |
| `just switch` / bundler error, formula unreadable, DSL keyword | `agents/instructions/troubleshooting.md` — bump the pin, never remove it |
| ssh / home-server commands, host unreachable, `.local` not resolving | "SSH to home-server.local" (below)                          |
| auto-update finished but changes missing, brew not applied  | `agents/instructions/troubleshooting.md`                           |
| server suspended / unreachable, GNOME session killed by update | `agents/instructions/troubleshooting.md`                        |
| Touch ID not offered for sudo, password modal instead        | `agents/instructions/troubleshooting.md` — unsigned PAM module; no fix, two dead ends already tested |
| `als` missing an alias, alias not found in a running shell  | `agents/instructions/troubleshooting.md` — stale shell, or it's a function |
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

**A run that looks successful may have applied only half the config.** On the MacBooks, exit status 0 does not mean the run finished — the daemon can be killed mid-activation, silently skipping the Homebrew phase and home-manager. Check the log ends with `Update complete`, not `reloading service org.nixos.nix-auto-update`. See `agents/instructions/troubleshooting.md`.

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
- **A second tmux server becomes a second saver.** tmux sources `~/.tmux.conf` for EVERY server, whatever its socket — socket isolation is not config isolation. Any tool that runs `tmux -L <name>` (gascity does, per `[session].socket`) therefore gets its own resurrect + continuum, restores every real session onto its socket as duplicates, and auto-saves over the shared `~/.tmux/resurrect/`. Two savers, one state dir: whichever writes last wins, and the other server's sessions are gone at the next restore. Happened for real on 2026-08-09 — `gc start` spawned one agent and 24 duplicate sessions plus ~200 stray shells appeared.

  The config now guards this three ways (see the `resurrectRestoreTrigger` / `continuumSaveGuarded` / `continuumDisableOffDefault` helpers in `home.nix`): the restore trigger and the continuum save interpolation both exit unless the socket basename is `default`, and the save interval is zeroed off-default because continuum re-asserts its own `status-right` during plugin load and can win over `extraConfig`.

  **Never set `@continuum-restore 'on'` in the continuum plugin block.** Continuum reads that option as its own `.tmux` loads on the very next line, so it schedules an auto-restore on every socket before `extraConfig` can turn it off. That single line — not the save path — is what actually re-duplicated the sessions in testing. `extraConfig` sets it `off`; restore is driven only by the socket-guarded trigger.

**Always run `agents/scripts/test-tmux-resurrect.sh` after touching any of this.** It exercises the real save → restore → hook cycle on a throwaway server and asserts the post-restore hook actually fired — the check that catches the first mode above, which layout-only checks pass right through. It is heavily isolated (separate socket, sandboxed `HOME`, PATH shim, `-f /dev/null`, faked `TMUX`); during development it leaked a session onto the live server twice, so do not weaken any of those layers. Read the header comment before editing it.

**The harness does NOT cover the socket guard.** It runs every tmux invocation with `-f /dev/null`, which is exactly what keeps it off production state — but it also means `~/.tmux.conf` is never loaded, so a regression in the socket guard passes all 11 tests. Verify that mode by hand instead: start a server on a non-default socket **with** the real config and confirm only the session you asked for exists.

```sh
command tmux -L probe new-session -d -s probe 'sleep 60'
sleep 10
command tmux -L probe ls                     # expect ONLY `probe`
command tmux -L probe show-options -g | grep -iE 'continuum-restore|continuum-save-interval'
                                             # expect: restore off, save-interval 0
command tmux -L probe kill-server
```

Wait ~10s before asserting. The restore fires a second or two after server start, so an immediate check passes even when the guard is broken — that false pass happened during development.

**Recovering lost sessions.** Transcripts live in `~/.claude/projects/<slug>/<session-id>.jsonl` and survive independently of tmux — a lost pane is almost never lost work. `~/.tmux/resurrect/assistant-sessions.json` maps panes to session IDs. Sessions started from Agent View are forks whose own IDs may have no transcript; their history is under the parent session in `~/.claude/jobs/<short-id>/` (`state.json` has `sessionId`, `intent`, and `cwd`). Check there before concluding a session is unrecoverable.

## gascity

`gc` is the gascity CLI (Homebrew brew from the `gastownhall/gascity` tap). The city lives at `~/Tech/pata-city`; its one rig is `~/Tech/Perso/cash22`. Not managed by this repo — but two things here exist because of it.

**The `gc` name collides with oh-my-zsh.** The git plugin aliases `gc` to `git commit -v`, shadowing the binary. gascity cannot yield the name: it bakes `gc` into the hook commands it injects into agent panes, and its completion registers as `#compdef gc`. `dotfiles/oh-my-zsh/plugins/gascity/` drops the alias and adds `gci` for git commit. **That plugin must stay LAST in the `oh-my-zsh.plugins` list** — plugins are sourced in array order, so listing it alphabetically (before `git`) lets the git plugin recreate the alias immediately afterwards. This is documented at <https://docs.gascity.com/getting-started/troubleshooting#oh-my-zsh-git-plugin-hides-gc>, though the doc's `$ZSH_CUSTOM`-loads-last claim holds for loose `.zsh` files, not for a named custom plugin.

**It starts tmux servers on its own socket.** See the second-saver failure mode under "tmux session save/restore" — this is the reason the socket guards exist. `gc start` spawns agents (e.g. `bd.dog`) on the socket named by `[session].socket` in `city.toml`. Before running it after any tmux config change, verify the guard by hand using the recipe in that section.

Interaction is **not** via tmux any more, despite what older setups suggest. As of 1.3 the Mayor is a *skill* loadable from any agent (invoke as `@mayor` from Claude Code in a rig folder), not a session you attach to; 1.4 moved observation to `gc dashboard`, a web UI served by the supervisor. `gc session attach <name>` exists and is preferable to raw `tmux attach` (it resumes or restarts a dead session), but you should not need a terminal attached to gascity's socket at all.

**Beads and backup.** Issue data lives in Dolt databases under `~/Tech/pata-city/.beads/dolt/` — `hq` (the city's own beads) and `cash22` (the rig's 34 issues). Adopting the rig into the city on 2026-05-11 moved that data out of the cash22 git repo and added `.beads/*` to its `.gitignore`, which silently ended the GitHub backup that had been working. Dolt supports git remotes natively, so `cash22` pushes to its existing repo — but **`dolt push` is manual**; nothing automates it, and `export.auto` / `backup.enabled` are both `false`. `hq` has no remote at all. A `dolt remote -v` URL rendered as `git+ssh://git@github.com/./owner/repo.git` is Dolt's own normalization of `git@github.com:owner/repo.git`, not corruption.

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

## New files must be `git add`ed before `just switch`

This flake is a git repo, so nix copies only **tracked** files into the store. A new file — a dotfile, an oh-my-zsh plugin, a script — that is still untracked (`??` in `git status`) is invisible to the build: `just switch` reports success and deploys nothing, and the symptom is a stale store path with the old contents. `git add` the new path first, then switch. Cost a confusing debugging detour on 2026-08-09 when a new plugin appeared not to load.

## Interpreting the write sandbox

Bash tool calls are sandboxed to a write allowlist that covers this repo and a few tool dirs; the Edit/Write tools are not bound by it. So in a directory outside the allowlist (e.g. `~/Tech/pata-city`) editing a file can succeed while `rm` on the same path fails with `Operation not permitted`. That asymmetry is the sandbox, not a permissions bug on disk — don't go hunting for one.

`~/.gc` is on the allowlist; the city directory itself deliberately is not, so gascity operations that write there prompt.

## Remote machines

Cannot run `sudo` over SSH to remote machines. When an operation needs sudo on the home server, tell the user what command to run rather than attempting it.

## SSH to home-server.local

Two independent mechanisms govern these commands, with different symptoms. Do not confuse them: **quoting** affects approval prompts; **flags** affect sandboxing and therefore DNS resolution.

### Quoting → approval prompts (`permissions.allow`)

Use unquoted form for read-only SSH commands so auto-approval rules match:
```
ssh home-server.local journalctl -u foo --no-pager     # auto-approved
ssh home-server.local "journalctl -u foo --no-pager"   # prompts (quoted form breaks prefix match)
```
For commands requiring shell metacharacters on the remote side (`*`, `|`, `>`, `;`), quoted form is fine — the resulting prompt is intentional.

### Flags → sandbox, and hence name resolution (`sandbox.excludedCommands`)

**Use the hostname, not an IP.** `home-server.local` resolves via mDNS and works. Do not "fix" a resolution failure by switching to a raw IP — see the next paragraph for the actual cause.

**Never add flags to an `ssh home-server.local` invocation.** Keep it plain. Persistent options belong in `~/.ssh/config` under the existing `Host home-server.local` block, where the plain command picks them up.

Why: `.claude/settings.json` lists `ssh home-server.local *` in `sandbox.excludedCommands`, so matching commands run **outside** the sandbox, where mDNS works. A flag between `ssh` and the hostname (`ssh -o ConnectTimeout=10 home-server.local uptime`) no longer matches that glob, so the command runs *inside* the sandbox — where `.local` cannot resolve, because mDNSResponder is reachable only over a Unix socket and the sandbox permits only the Nix daemon socket. The result is `Could not resolve hostname home-server.local`.

This is a **sandbox** boundary, not a permissions one. The `Bash(ssh home-server.local ...)` entries under `permissions.allow` only suppress approval prompts and have no effect on resolution — adding more of them cannot fix this.

Two consequences worth internalising:
- `Could not resolve hostname home-server.local` from a Bash call is almost always this, not a network or server fault. Verify with `dangerouslyDisableSandbox: true` before drawing any conclusion about the machine.
- Do not "work around" it by switching to `192.168.0.17`. That treats a sandbox artifact as a network fact. On 2026-08-14/15 a self-inflicted `-o ConnectTimeout=10` produced a resolution failure that was then read as evidence the server was down, sending the session into a subnet scan and two successive wrong diagnoses.

**Do not conclude "the machine is off" from an unreachable host.** A genuinely unreachable box may simply be suspended — indistinguishable from absent over the network. Rule out the sandbox first (above), then check the previous boot's journal for `PM: suspend entry`. See `agents/instructions/troubleshooting.md` → "Home server unreachable after an auto-update".
