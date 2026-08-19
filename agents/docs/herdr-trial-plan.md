# herdr trial plan

Written 2026-08-16. Executed by a separate session — this document is the spec.

Goal: run **herdr** instead of tmux for ~1 week on the 2023 MacBook Pro, to evaluate
whether it replaces tmux for day-to-day work. The motivation is agent visibility: a
single place showing every Claude session and which ones are blocked waiting for input.
tmux gives no such view today.

Out of scope: the 2018 MacBook Pro. Its tmux/resurrect config is known-divergent and
partly broken; that is deliberately ignored until the 2023 machine decides.

---

## 0. Verified facts (checked against the binary, not the docs)

Do not re-derive these; they were confirmed on 2026-08-15/16.

- **herdr is in official nixpkgs**: `pkgs/by-name/he/herdr/package.nix`, version **0.8.0**,
  Apache-2.0, maintainers `kevinpita` + `faukah`. Fetches prebuilt from `cache.nixos.org`
  (6.0 MiB download) — no local Rust build, no Zig toolchain. Use `pkgs.herdr`; the
  third-party `numtide/llm-agents.nix` flake is NOT needed.
- `meta.platforms` includes `aarch64-darwin` but **not `x86_64-darwin`** — relevant only if
  the 2018 machine is ever in scope.
- **Session model**: client/server, like tmux. `herdr --session <name>` creates-or-attaches
  a named persistent session — the direct analogue of `tmux new-session -As main`.
- **Agent resume is native**: `[session] resume_agents_on_restore = true` — "Resume supported
  AI-agent panes into their native conversation sessions after a Herdr server restart."
  This is the built-in equivalent of the `tmux-assistant-resurrect` chain.
- **Desktop notifications exist**: `[ui.toast] delivery` accepts `off` | `herdr` | `terminal` |
  `system`. Plus `[ui.sound]` with separate `request_path` (needs-attention) and `done_path`.
- **Catppuccin is a built-in theme** (`[theme] name = "catppuccin"`), with `auto_switch` for
  light/dark following the host terminal.
- **Claude integration is not installed yet**: `herdr integration status` reports
  `claude: not installed (/Users/cyrilledru/.claude/hooks/herdr-agent-state.sh)`.
- **Open issue #803 ("misses nix-wrapped Claude Code") likely does not apply**: `which claude`
  → `/opt/homebrew/bin/claude`, the Homebrew cask, not a nix wrapper.
- **Claude Code state detection is screen-scraped**, per herdr docs — the hook reports session
  *identity* for resume, not live state. OpenCode/Kimi report state directly; Claude does not.
  This is the feature most likely to be flaky and is the primary thing the trial must judge.
- **Maturity**: repo created 2026-03-27, v0.8.0 released 2026-08-03, ~29k stars,
  ~140–165 open issues, near-weekly releases, config stability explicitly not guaranteed.

### Corrections to earlier analysis (do not act on the retracted claims)

- The resurrect state is **NOT degraded**. An earlier reading of a 7.6k save file was a
  transient `ls` during an in-progress write. Both recent saves are 16k / 183 lines and
  contain all 23 sessions. Nothing to fix.
- The `@continuum-save-interval` live value of `5` vs configured `15` is **not drift worth
  acting on**. `home.nix:343` and the deployed `~/.config/tmux/tmux.conf:57` both say `15`;
  the running server has been up since 21 Jul and predates that change. It self-corrects on
  the next server restart. Saving every 5 min instead of 15 is harmless.
- `settings.json` is **entirely hand-authored** — every key (`env`, `permissions`, `autoMode`,
  `hooks`, `statusLine`, `enabledPlugins`, `sandbox`, `effortLevel`, `theme`,
  `additionalDirectories`) is deliberate config. There is no machine-generated churn. It
  should be version-controlled directly; the earlier "snapshot instead of symlink" suggestion
  was based on a wrong premise and is withdrawn.
- `ta` is **not** a user-defined alias — it ships with the oh-my-zsh `tmux` plugin
  (`ta`/`ts`/`tl`). It is not in `home.nix`. (Why `als` does not list it while it does list
  git-plugin aliases is unexplained and not worth chasing.)

---

## 1. Current tmux setup — what must be preserved

Source of truth: `hosts/2023-macbook-pro/home.nix`. Deployed to `~/.config/tmux/tmux.conf`
(there is no legacy `~/.tmux.conf`).

**Scale**: 23 live sessions, one per project, named after the project directory basename
(`beall`, `infra`, `beship`, `nix-config`, `terraform-conf`, …).

**Custom bindings** (`home.nix:420–450`) — the rest of the 97 prefix bindings are tmux stock:

| Binding | Action |
|---|---|
| `prefix r` | reload config |
| `prefix h/j/k/l` | vim pane nav, **auto-unzoom then re-zoom** if window was zoomed |
| `prefix H/J/K/L` | resize pane by 5 (repeatable) |
| `prefix Tab` | `switch-client -l` (last session) |
| `prefix s` | fzf popup over existing sessions → `switch-client` |
| `prefix S` | fzf popup over `fd`-discovered dirs under `~` (depth 5, no dotdirs, no `node_modules`) → create session named after basename (dots→underscores) at that cwd, then switch |
| `v` / `C-v` (copy-mode-vi) | begin-selection / rectangle-toggle |

`prefix S` is how all 23 sessions came to exist. There is no tmuxinator/tmuxp.

**Options**: prefix is default `C-b`; `mouse on`, `base-index 1`, `pane-base-index 1`,
`history-limit 100000`, `mode-keys vi`, `status-keys emacs` (deliberate — vi command-prompt
editing is poor), `aggressive-resize on`, `set-clipboard on`, `focus-events on`,
`escape-time 0`, `allow-rename off`, `automatic-rename off`, `default-terminal tmux-256color`.

**Theme**: Catppuccin Mocha (tmux, Ghostty, bat, delta all match).

**Save/restore chain** (the part herdr must replace):
1. **continuum** — no timer; drives autosave via a `#(...)` interpolation embedded in
   `status-right`, which must be re-appended after the catppuccin block or the theme
   silently drops it.
2. **resurrect** — snapshots windows/panes/layout/cwd, `@resurrect-capture-pane-contents on`.
3. **tmux-assistant-resurrect** — `save-assistant-sessions.sh` walks each pane's process
   tree for `claude`/`opencode`/`codex`, resolves the session id via the `SessionStart` hook
   state file (falling back to parsing `--resume <id>` from live args), and writes
   `~/.tmux/resurrect/assistant-sessions.json` mapping `session:window.pane` →
   `{tool, session_id, cwd, pid, model, cli_args, env}`. On restore it rebuilds
   `claude --resume <id>` per pane.
4. **Socket guards** — `resurrectRestoreTrigger` / `continuumSaveGuarded` /
   `continuumDisableOffDefault` all no-op unless the socket basename is `default`, because
   tmux sources the same config for *every* server regardless of socket (gascity spawns one).
   `@continuum-restore` is deliberately never set to `'on'`.

**Ghostty attach mechanism** (`home.nix:57–59`, referenced at `:461`):
```nix
ghosttyTabInitScript = pkgs.writeShellScript "ghostty-tab-init" ''
  exec zsh -l -c "/opt/homebrew/bin/tmux new-session -As main"
'';
```
Every new Ghostty window/tab runs this instead of a plain shell. `-A` makes it idempotent,
so all tabs converge on one server (`default` socket), one session `main`.

---

## 2. Decisions already made

These were agreed in discussion. Do not relitigate them.

1. **Remove `ghosttyTabInitScript` entirely** rather than adding a second entry point.
   A Ghostty keybinding for a second profile was already tried and did not work. New tabs
   get a plain login shell; tmux and herdr are then peers, each reached by an alias.
2. **Add aliases** `tm` (tmux) and `hd` (herdr). Do **not** reuse `ta` — it is the oh-my-zsh
   plugin's bare `tmux attach` and does not recreate the create-or-attach behaviour.
3. **One `agent-config` repo at `~/Tech/agent-config`**, versioned, covering both personal and
   work use. Not per-tool micro-repos.
4. **Symlink style**: directory symlinks for `hooks/`, `instructions/`, `scripts/`;
   individual file symlinks for `CLAUDE.md` and `settings.json`.
5. **`skills/` at the repo root**, not under `claude/` — skills are a portable format read by
   other harnesses (the `handoff` skill is explicitly cross-harness).
6. **Move `personal-skills` with its history** via `git subtree`, not a copy.
7. **Order matters**: version-control `settings.json` *before* installing the herdr
   integration, so the installer's edits show up as a reviewable diff.

---

## 3. Step 1 — create `~/Tech/agent-config`

### Target layout

```
~/Tech/agent-config/
├── README.md          # repo's own doc — NOT CLAUDE.md (that would be repo instructions)
├── install.sh         # creates the symlinks, modelled on personal-skills/install.sh
├── claude/
│   ├── CLAUDE.md      → ~/.claude/CLAUDE.md          (file symlink)
│   ├── settings.json  → ~/.claude/settings.json      (file symlink)
│   ├── hooks/         → ~/.claude/hooks              (dir symlink)
│   ├── instructions/  → ~/.claude/instructions       (dir symlink)
│   ├── scripts/       → ~/.claude/scripts            (dir symlink)
│   ├── commands/      → ~/.claude/commands           (dir symlink; empty today)
│   └── agents/        → ~/.claude/agents             (dir symlink; empty today)
└── skills/            → individual per-skill symlinks into ~/.claude/skills/
```

### What moves

Hand-authored, currently unversioned:
- `~/.claude/CLAUDE.md` (7.1k)
- `~/.claude/hooks/` — `bash-guard.sh`, `gh-api-guard.sh`, `git-transport-guard.sh`,
  `notify.sh`, `validate-commit.sh`, plus `anthropic-icon.ico` and `claude-icon.png`
- `~/.claude/instructions/` — `git-commits.md`, `skills.md`
- `~/.claude/scripts/` — `statusline.sh`
- `~/.claude/settings.json` (6.7k)
- `~/.claude/commands/`, `~/.claude/agents/` — empty, create for future use

### What must NOT move

Machine state: `projects/`, `history.jsonl` (3.4M), `sessions/`, `cache/`, `file-history/`,
`shell-snapshots/`, `session-env/`, `paste-cache/`, `stats-cache.json`, `telemetry/`,
`plugins/`, `backups/`, `jobs/`, `tasks/`, `debug/`, `daemon/`, `.credentials.json`,
`security/`, `ide/`, `plans/`, `.cc-writes/`.

Already managed, leave alone:
- `~/.claude/skills/` — already per-skill symlinks into `personal-skills`
- `~/.claude/tmux-resurrect-hooks` — symlink into the nix store, owned by `home.nix:153–154`.
  **Do not bring this into `agent-config`.** It is deliberately a stable path because
  `settings.json` bakes in `~/.claude/tmux-resurrect-hooks/...` and a moving store path
  would 404 after a GC.

### Why symlinks are safe here

Every path inside `settings.json` is written as `~/.claude/...` — verified, there are no
absolute nix-store paths:
```
~/.claude/hooks/{bash-guard,gh-api-guard,git-transport-guard,notify,validate-commit}.sh
~/.claude/scripts/statusline.sh
~/.claude/tmux-resurrect-hooks/{claude-session-track,claude-session-cleanup}.sh
```
So redirecting `~/.claude/hooks` to the repo is invisible to Claude Code. This is also why
generating these from `home.nix` would be wrong — the repo already documents that
`settings.json` must stay unmanaged at a stable path.

### Procedure

1. `mkdir -p ~/Tech/agent-config`, `git init`, write `README.md` and `.gitignore`.
2. **Back up first**: `cp -a ~/.claude ~/.claude.bak-pre-agent-config` (cheap insurance;
   delete once verified).
3. `git mv`-equivalent: copy the files listed above into `claude/`, commit them **before**
   deleting the originals, so there is a committed baseline.
4. Replace the originals with symlinks (dirs for `hooks`/`instructions`/`scripts`/
   `commands`/`agents`, files for `CLAUDE.md`/`settings.json`).
5. Write `install.sh` so the whole thing is reproducible on another machine.
6. **Verify before moving on**: start a fresh Claude Code session and confirm
   (a) the statusline renders, (b) a `PreToolUse` hook still fires — e.g. `bash-guard.sh`
   rejects a command with `$VAR` in a redirect target, (c) `/help` lists the skills,
   (d) `ls -la ~/.claude/settings.json` still shows a symlink.

---

## 4. Step 2 — move `personal-skills` into `agent-config/skills`

`~/Tech/Bespoke/personal-skills` is a git repo with **no remote** (local-only). It holds:
`beall-compose`, `bespoke-sidecar`, `create-pr`, `grill-me`, `handoff`,
`refactoring-claude-md`, `rewrite-branch-commits`, `ubiquitous-language`, `wrap-up`,
plus `install.sh` and `.gitignore`.

Only 7 of the 9 are currently symlinked into `~/.claude/skills/`
(`refactoring-claude-md` and `ubiquitous-language` are not linked).

1. `git subtree add --prefix=skills <path-to-personal-skills> master` — preserves history.
   Since there is no remote, add the local path as a remote first.
2. Re-point the 7 existing symlinks in `~/.claude/skills/` to
   `~/Tech/agent-config/skills/<name>`.
3. Merge `personal-skills/install.sh` logic into the top-level `install.sh`.
4. Update `~/.claude/instructions/skills.md` — it currently documents
   `~/Tech/Bespoke/personal-skills/` as the global skills home. That path changes.
   Also update the global `~/.claude/CLAUDE.md` if it references the old path.
5. **Leave the old `personal-skills` directory in place, untouched**, until the symlinks are
   verified working. Retire it in a later commit.

**Note**: `~/Tech/Bespoke/agent-sidecar` is a *different* thing — per-work-repo content keyed
by Bespoke repo name (`beall/`, `infra/`, …), also with no remote. It is **not** the home for
global config and is not touched by this plan.

**Consider adding a git remote** to `agent-config`. Neither `personal-skills` nor
`agent-sidecar` has one, so none of this content is currently backed up anywhere.

---

## 5. Step 3 — remove the Ghostty init script, add aliases

### Edits to `hosts/2023-macbook-pro/home.nix`

1. Delete the `ghosttyTabInitScript` binding (lines ~57–59) and its explanatory comment
   block (~49–56). Keep the comment history in the commit message rather than the file.
2. Remove `command = "${ghosttyTabInitScript}";` from `programs.ghostty.settings` (line ~461).
3. Add to `shellAliases` (line ~478):
   ```nix
   tm = "tmux new-session -As main";
   hd = "herdr --session main";
   ```
   `hd` is currently unused. `tm` is chosen over `ta` because the oh-my-zsh `tmux` plugin
   already defines `ta` as a bare `tmux attach`.
4. Add `herdr` to `home.packages`.

Then `just switch`. Report any warnings.

### Answers to the questions raised about this step

**Does a new tab pick up the change, or is a Ghostty restart needed?**
Ghostty reads `command` when it **launches a new surface**, and the config file itself is
re-read on `Cmd+Shift+,` (reload config) or on app restart. Because `home.nix` writes the
config through home-manager, `just switch` rewrites `~/.config/ghostty/config` (a symlink
into the nix store — the store path changes, so the symlink target changes).

The safe expectation: **a Ghostty restart is needed.** A new tab may still use the cached
old `command` until the config is reloaded. Try reload-config first; if a new tab still
auto-attaches to tmux, quit and relaunch Ghostty. This is worth confirming empirically
during execution rather than assuming.

**Will the tmux sessions survive? Can they be reattached?**
**Yes — no sessions are lost.** The tmux *server* is a long-lived background process that is
completely independent of how clients attach to it. It has been running since 21 Jul.
Removing `ghosttyTabInitScript` only stops new tabs from *auto-attaching*; it does not
signal, stop, or otherwise touch the server. After the change, `tm` (or `tmux attach`)
reattaches to the same server with all 23 sessions intact.

**One real consequence**: after a *reboot*, nothing auto-starts tmux any more. Today the
first Ghostty tab starts the server, which fires the socket-guarded restore trigger. With
the script gone, the restore only happens when you manually run `tm`. That is fine, but:
- Do it reasonably promptly after a reboot — continuum cannot autosave a server that is not
  running, so a long gap risks the on-disk snapshot ageing (it does **not** risk losing the
  snapshot; `~/.tmux/resurrect/last` persists).
- Claude transcripts live in `~/.claude/projects/<slug>/<session-id>.jsonl` and survive
  independently of tmux regardless.

**Revert**: restore the two `home.nix` hunks and `just switch`. One-line change either way.

---

## 6. Step 4 — install and configure herdr

### 6a. Install

`pkgs.herdr` via `home.packages` (step 3 above). Confirm with `herdr --version` → 0.8.0.

Do **not** use `brew services start herdr` — the server starts on demand when `herdr` runs,
and a brew service would conflict with the nix-installed binary.

### 6b. Claude integration — the one risky moment

```
herdr integration install claude
```

This writes `~/.claude/hooks/herdr-agent-state.sh` and edits `~/.claude/settings.json`.
Both are now symlinks into `agent-config`.

**Immediately afterwards:**
1. `ls -la ~/.claude/settings.json` — confirm it is **still a symlink**. If the installer
   used rename-replace rather than in-place write, it will have silently replaced the symlink
   with a regular file, detaching it from the repo. If that happened: copy the new content
   into the repo, restore the symlink, and note it in the trial log.
2. `git -C ~/Tech/agent-config diff` — review exactly what was injected.
3. Confirm the existing `tmux-resurrect-hooks` `SessionStart`/`SessionEnd` entries are still
   present. Both hook sets must coexist during the trial: tmux restore must keep working
   while herdr is being evaluated.

**Then decide** on the `settings.json` / `settings.local.json` split — do not decide before
seeing the diff:
- If herdr added a **static** hook entry (most likely — the docs say the hook reports session
  *identity* for resume), that is legitimate config. Keep it tracked in `settings.json`.
- If herdr writes **mutable state** into `settings.json`, move those keys to
  `~/.claude/settings.local.json` (Claude Code reads it and it overrides `settings.json`;
  conventionally gitignored) and add it to `.gitignore`.

Note: herdr's installer targets `settings.json` specifically; there is no evidence it knows
about `settings.local.json`, so any split has to be applied manually after the fact.

### 6c. Config file

`herdr --default-config > ~/.config/herdr/config.toml`, then set:

```toml
[theme]
name = "catppuccin"

[ui.toast]
delivery = "system"      # or "terminal" — Ghostty already has desktop-notifications = true

[ui.sound]
enabled = true

[session]
resume_agents_on_restore = true
```

Consider `[update] channel = "stable"` explicitly, and `version_check = false` /
`manifest_check = false` if background phone-home is unwanted — note that disabling
`manifest_check` also stops agent-detection manifest updates, which may matter given
Claude state detection is screen-scraped.

Once the trial config settles, this file should move into `agent-config` too (as
`herdr/config.toml` with a symlink) — but only after it stops changing daily.

---

## 7. Binding mapping

herdr's defaults already match tmux more closely than expected. **Prefix is `ctrl+b`**,
same as current.

| tmux (current) | herdr default | Action needed |
|---|---|---|
| `prefix h/j/k/l` pane nav | `focus_pane_left/down/up/right` = `prefix+h/j/k/l` | none — already matches |
| `prefix z` zoom (tmux stock) | `zoom = "prefix+z"` (legacy alias `fullscreen`) | none |
| `prefix Tab` last session | — | map `previous_workspace` / `next_workspace` (unset by default) |
| `prefix s` session picker | `workspace_picker = "prefix+w"`; **`prefix+s` is `settings`** | accepted: learn `prefix+w`. Optionally rebind `settings` off `prefix+s` to avoid a mis-key opening settings |
| `prefix S` project→session | `new_workspace = "prefix+shift+n"` (name prompt only) | **rebuild** — see below |
| `prefix H/J/K/L` resize | resize bindings exist separately from `focus_pane_*` | map to match |
| `prefix r` reload | `reload_config = "prefix+shift+r"` | rebind to `prefix+r` if preferred |
| `prefix c` new window | `new_tab = "prefix+c"` | none |
| `prefix v` / `prefix -` split | `split_vertical = "prefix+v"`, `split_horizontal = "prefix+minus"` | none (tmux used `%`/`"`) |
| copy-mode `v`/`C-v` | not investigated | check herdr's copy/selection model |

### The zoom-toggle question — answered

The tmux binding auto-unzooms, moves, then re-zooms:
```
bind -r h if -F "#{window_zoomed_flag}" "select-pane -L ; resize-pane -Z" "select-pane -L"
```

**In herdr this specific behaviour is not reproducible via config**, because there is no
conditional-on-zoom-state binding primitive — `focus_pane_*` and `zoom` are independent
actions and TOML bindings map one key to one action.

Three options, in order of preference:
1. **Test whether it is needed at all.** herdr's pane model may keep the focused pane visible
   differently; the tmux workaround exists because tmux's zoom hides sibling panes entirely.
   Try `prefix+h` while zoomed and observe. This may be a non-problem.
2. **`[[keys.command]]` with `type = "shell"`** running a script that queries state via the
   socket API (`herdr pane ...` / `herdr api ...`) and issues unzoom→focus→zoom. The socket
   API exposes pane control, so this is plausible — but it needs verification, and a
   shell round-trip per keypress may feel sluggish.
3. **Accept the loss** and use `prefix+z` manually.

Decide during the trial; do not block setup on it.

### Rebuilding `prefix S` — confirmed feasible

`herdr workspace create` accepts exactly the needed flags:
```
herdr workspace create --cwd <PATH> --label <TEXT> --focus [--env KEY=VALUE]
```
And `[[keys.command]]` supports `type = "popup"` — "opens a session-modal terminal without
changing the tab layout", with `width`/`height` as cells or percentages.

So the tmux `prefix S` popup translates to roughly:
```toml
[[keys.command]]
key = "prefix+shift+s"
type = "popup"
command = "<script that runs fd | fzf, then herdr workspace create --cwd ... --label ... --focus>"
width = "80%"
height = "80%"
```
The script mirrors the existing tmux one: `fd -t d --no-ignore-vcs --max-depth 5 --exclude '.*'
--exclude node_modules . ~ | fzf --reverse`, then derive the label from `basename` with dots
replaced by underscores.

**Also relevant**: `[terminal] new_cwd` controls the default cwd for new panes/tabs/workspaces
when no `--cwd` is given — `"follow"` (inherit source, the default), `"home"`, `"current"`, or
a fixed path. This answers "where does a new workspace cd to": by default it inherits from
wherever you created it from.

Worth knowing: herdr also has native git worktree support (`herdr worktree`,
`new_worktree = "prefix+shift+g"`, `[worktrees] directory = "~/.herdr/worktrees"`), which has
no tmux equivalent.

---

## 8. Trial schedule

**Day 0** — steps 1–4 above. Ends with herdr installed, configured, integration diffed,
bindings ported, and tmux still fully functional and reattachable via `tm`.

**Days 1–2 — parallel, low stakes.** Run 2–3 low-risk projects in herdr (`nix-config`,
`pata-vault`, `personal-skills`); leave the other ~20 in tmux. Judge specifically:
- Does the sidebar `blocked` state actually light up when Claude asks for permission?
  (This is screen-scraped for Claude — the single most likely thing to be flaky.)
- Do `system` toast notifications and sounds fire reliably?
- Is the agent overview genuinely better than having no view at all?

**Days 3–4 — the reboot test.** This is make-or-break. Reboot with agents running in herdr
and verify `resume_agents_on_restore` reattaches conversations. tmux does this reliably today;
if herdr does not, it is not a replacement. Note that herdr's own docs concede a snapshot
alone restores *layout* but "processes don't resume" — resume depends on the integration
working.

**Days 5–7 — full weight.** If days 1–4 pass, move everything to herdr and use it exclusively.
Keep tmux installed and reachable (`tm`) but do not use it.

### Decision criteria at the end of the week

Adopt only if all of:
1. Blocked-state detection is accurate enough to trust (it is the whole point).
2. Reboot resume works at least as well as the tmux chain.
3. `prefix S` equivalent is rebuilt and comfortable.
4. No daily-friction regressions from pre-1.0 bugs.

If adopting, follow-ups: move `config.toml` into `agent-config`; remove the tmux
resurrect/continuum/assistant chain from `home.nix`; revisit the 2018 MacBook (blocked on
`x86_64-darwin` missing from nixpkgs `meta.platforms`).

If not adopting: revert step 3's `home.nix` hunk. Steps 1–2 (`agent-config`) are worth
keeping regardless — they are independent of the herdr outcome.

### Keep a trial log

`agents/docs/herdr-trial-log.md` — dated entries, one per day. Especially: every case where
blocked-state detection was wrong (missed a prompt, or claimed blocked when it was not), and
anything the installer did to `settings.json`.

---

## 9. Risks

1. **`settings.json` symlink replacement** by the herdr installer — check immediately after
   install (§6b).
2. **Pre-1.0 churn**: ~weekly releases, config stability not guaranteed. Pin the nixpkgs
   version via `flake.lock` rather than using `herdr update` (which would fight nix).
   Do not set `[update] channel = "preview"`.
3. **Claude state detection is screen-scraped**, unlike OpenCode/Kimi which report directly.
   Open issue #1217 reports state sticking on "complete" instead of "in-progress".
4. **Coexistence with tmux is inferred, not documented.** No vendor statement was found
   either way. Architecturally they are independent (separate sockets, separate config dirs,
   herdr never touches `~/.tmux/resurrect/`), but watch for both tools fighting over terminal
   title escape sequences or shell prompt integration.
5. **No auto-start after reboot** once `ghosttyTabInitScript` is gone — for either tool.
   Both need a manual `tm` / `hd`.
6. **Do not run herdr inside a tmux pane or vice versa.** herdr has
   `[experimental] allow_nested = false` by default for a reason.

---

## 10. Repo conventions to respect during execution

- **`git fetch` and check against `origin/main` before editing** — the daily GitHub Action
  pushes "Upgrade flake" commits most days. (At time of writing, local `main` was 1 commit
  ahead of `origin/main` with a clean tree.)
- **New files must be `git add`ed before `just switch`** — nix copies only tracked files into
  the store; an untracked file silently deploys nothing.
- **Never run mutating brew commands.** herdr comes from nixpkgs, not Homebrew.
- **Commit prefix**: `MBP2023` for changes touching only the 2023 MacBook.
- **Report all warnings** from `just switch` / nix eval.
- **Do not run `agents/scripts/test-tmux-resurrect.sh` expecting it to cover this work** — it
  runs with `-f /dev/null` and does not load the real config, so it cannot detect socket-guard
  regressions. Step 3 does not change the tmux config itself, only how it is attached to, so
  the existing chain is not at risk — but if any tmux config is touched, the manual
  socket-guard recipe in `agents/instructions/working-in-this-repo.md` applies.
