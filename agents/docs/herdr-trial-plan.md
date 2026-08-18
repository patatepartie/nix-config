# herdr trial plan

Written 2026-08-16, revised after three independent reviews. Executed by a separate
session — this document is the spec and should be followed without needing the
conversation that produced it.

Goal: run **herdr** instead of tmux for ~1 week on the 2023 MacBook Pro, to decide whether
it replaces tmux. The motivation is agent visibility: a single place showing every Claude
session and which are blocked waiting for input. tmux gives no such view today.

Out of scope: the 2018 MacBook Pro (its tmux config is known-divergent and partly broken;
ignored until the 2023 machine decides). Also out of scope: the home-server — see §11.

---

## 0. Verified facts

Checked against the binary and the live system on 2026-08-15/16. Do not re-derive.

- **herdr is in official nixpkgs**: `pkgs/by-name/he/herdr/package.nix`, version **0.8.0**,
  Apache-2.0, maintainers `kevinpita` + `faukah`. Use `pkgs.herdr`; the third-party
  `numtide/llm-agents.nix` flake is NOT needed.
- **It is a source build, not a prebuilt binary.** The derivation is
  `rustPlatform.buildRustPackage` with `src = fetchFromGitHub`, a `cargoHash`, and a
  **`zig_0_15`** dependency compiling `vendor/libghostty-vt`. As of 2026-08-16 the exact
  output `/nix/store/24jh6wfc6wlgcwnrm4ynq93j2ad5v98j-herdr-0.8.0` **is** present on
  `cache.nixos.org`, so `just switch` should fetch it (~6 MiB) rather than compile. But if
  the binary cache misses (e.g. after a `flake.lock` bump moves the derivation hash),
  expect a real Rust + Zig compile taking minutes, not seconds. Budget for that.
- `meta.platforms` is `lib.platforms.unix`, which includes `aarch64-darwin` and excludes
  `x86_64-darwin` — relevant only if the 2018 machine ever comes into scope.
- **Session model**: client/server like tmux. `herdr --session <name>` creates-or-attaches a
  named persistent session — the direct analogue of `tmux new-session -As main`.
- **Agent resume is native**: `[session] resume_agents_on_restore = true` — "Resume supported
  AI-agent panes into their native conversation sessions after a Herdr server restart."
- **Desktop notifications exist**: `[ui.toast] delivery` accepts `off`|`herdr`|`terminal`|
  `system`. Plus `[ui.sound]` with separate `request_path` (needs-attention) and `done_path`.
- **Scrollback/copy is covered**: `edit_scrollback = "prefix+e"`, `copy_on_select = true`,
  `mouse_capture = true`, `mouse_scroll_lines = 3`, and
  `[advanced] scrollback_limit_bytes = 10000000` (matches Ghostty's default).
- **Catppuccin is a built-in theme** (`[theme] name = "catppuccin"`), with `auto_switch`.
- **Claude integration not yet installed**: `herdr integration status` reports
  `claude: not installed (/Users/cyrilledru/.claude/hooks/herdr-agent-state.sh)`.
- **Issue #803 ("misses nix-wrapped Claude Code") likely does not apply**: `which claude` →
  `/opt/homebrew/bin/claude`, the Homebrew cask, not a nix wrapper.
- **Claude state detection is screen-scraped**, per herdr's docs — the hook reports session
  *identity* for resume, not live state. OpenCode/Kimi report state directly; Claude does
  not. This is the feature most likely to be flaky and is the main thing the trial judges.
- **Maturity**: v0.8.0 released 2026-08-03, pre-1.0, near-weekly releases, config stability
  explicitly not guaranteed. Star/issue counts cited in earlier drafts were not
  independently re-verified and are informational only — do not treat as load-bearing.

### Corrections — do not act on these retracted claims

- The resurrect state is **NOT degraded**. An earlier 7.6k reading was a transient `ls`
  during an in-progress write. Both recent saves are 16K / ~182 lines covering all 23
  sessions. Nothing to fix.
- The `@continuum-save-interval` live `5` vs configured `15` is **not actionable drift**.
  `home.nix:343` and the deployed `~/.config/tmux/tmux.conf:57` both say `15`. The running
  server predates that edit and self-corrects on next server restart; saving more often is
  harmless. (The server started **Wed 2026-08-05 21:24:46**, PID 36688 — an earlier claim of
  "21 Jul" was wrong.)
- `settings.json` is **entirely hand-authored** — `env`, `permissions`, `autoMode`, `hooks`,
  `statusLine`, `enabledPlugins`, `sandbox`, `effortLevel`, `theme`, `additionalDirectories`.
  No machine-generated churn. Version it directly; the earlier "snapshot instead of symlink"
  idea is withdrawn.
- `ta` is **not** user-defined — it ships with the oh-my-zsh `tmux` plugin (`ta`/`ts`/`tl`)
  and is not in `home.nix`. (Why `als` does not list it is unexplained; not worth chasing.)

---

## 1. Current tmux setup — what must be preserved

Source of truth: `hosts/2023-macbook-pro/home.nix`, deployed to `~/.config/tmux/tmux.conf`
(no legacy `~/.tmux.conf` exists).

**Scale**: 23 live sessions, one per project, named after the project directory basename.

**Custom bindings** (`home.nix:420–450`; the other ~90 prefix bindings are tmux stock):

| Binding | Action |
|---|---|
| `prefix r` | reload config |
| `prefix h/j/k/l` | vim pane nav, **auto-unzoom then re-zoom** if window was zoomed |
| `prefix H/J/K/L` | resize pane by 5 (repeatable) |
| `prefix Tab` | `switch-client -l` (last session) |
| `prefix s` | fzf popup over existing sessions → `switch-client` |
| `prefix S` | fzf popup over `fd`-discovered dirs under `~` → create session named after basename (dots→underscores) at that cwd, then switch |
| `v` / `C-v` (copy-mode-vi) | begin-selection / rectangle-toggle |

`prefix S` is how all 23 sessions came to exist. No tmuxinator/tmuxp.

**Options**: prefix default `C-b`; `mouse on`, `base-index 1`, `pane-base-index 1`,
`history-limit 100000`, `mode-keys vi`, `status-keys emacs` (deliberate), `aggressive-resize
on`, `set-clipboard on`, `focus-events on`, `escape-time 0`, `allow-rename off`,
`automatic-rename off`, `default-terminal tmux-256color`.

**Theme**: Catppuccin Mocha (tmux, Ghostty, bat, delta).

**Save/restore chain** (what herdr must replace): continuum (autosave via a `status-right`
interpolation, re-appended after the catppuccin block) → resurrect (layout + pane contents)
→ tmux-assistant-resurrect (walks each pane's process tree for `claude`/`opencode`/`codex`,
writes `~/.tmux/resurrect/assistant-sessions.json` mapping `session:window.pane` →
`{tool, session_id, cwd, pid, …}`, and on restore rebuilds `claude --resume <id>` per pane).
Socket guards no-op everything unless the socket basename is `default`.

**Ghostty attach mechanism** (`home.nix:57–59`, referenced at `:461`):
```nix
ghosttyTabInitScript = pkgs.writeShellScript "ghostty-tab-init" ''
  exec zsh -l -c "/opt/homebrew/bin/tmux new-session -As main"
'';
```
Every new Ghostty window/tab runs this. `-A` makes it idempotent, so all tabs converge on
one server (`default` socket), session `main`.

---

## 2. Decisions already made — do not relitigate

1. **Remove `ghosttyTabInitScript` entirely** rather than adding a second entry point (a
   Ghostty keybinding was already tried and did not work). New tabs get a plain login shell;
   tmux and herdr become peers reached by aliases.
2. **Aliases** `tm` (tmux) and `hd` (herdr). Not `ta` — that is the oh-my-zsh plugin's bare
   `tmux attach` and does not create-or-attach.
3. **One `agent-config` repo at `~/Tech/agent-config`**, covering personal and work use.
4. **Symlink style**: directory symlinks for `hooks/`, `instructions/`, `scripts/`,
   `commands/`, `agents/`; file symlinks for `CLAUDE.md` and `settings.json`.
5. **`skills/` at repo root**, not under `claude/` — skills are portable across harnesses.
6. **Move `personal-skills` with history** via `git subtree`.
7. **Steps 1–2 run before step 4**, so the herdr installer's edits to `settings.json` appear
   as a reviewable diff. (A reviewer argued for decoupling; rejected — the user asked for the
   consolidated repo, steps 1–2 are reversible and touch nothing tmux-related, and splitting
   means doing the migration twice. But see the step-1 verification gate in §3.)
8. **No git remote for now.** Private GitHub remotes are possible but complicate workflows
   (conditional pushing). Deferred as a separate decision; the repo works fine local-only,
   matching `personal-skills` and `agent-sidecar` today.

---

## 3. Step 1 — create `~/Tech/agent-config`

### Target layout

```
~/Tech/agent-config/
├── README.md
├── install.sh
├── claude/
│   ├── CLAUDE.md      → ~/.claude/CLAUDE.md          (file symlink, mode 644)
│   ├── settings.json  → ~/.claude/settings.json      (file symlink, mode 600)
│   ├── hooks/         → ~/.claude/hooks              (dir symlink)
│   ├── instructions/  → ~/.claude/instructions       (dir symlink)
│   ├── scripts/       → ~/.claude/scripts            (dir symlink)
│   ├── commands/      → ~/.claude/commands           (dir symlink; empty today)
│   └── agents/        → ~/.claude/agents             (dir symlink; empty today)
└── skills/            (added in step 2)
```

### What moves

- `~/.claude/CLAUDE.md` (7.1k, mode 644)
- `~/.claude/settings.json` (6.7k, **mode 600 — preserve this**)
- `~/.claude/hooks/` — `bash-guard.sh`, `gh-api-guard.sh`, `git-transport-guard.sh`,
  `notify.sh`, `validate-commit.sh`, `anthropic-icon.ico`, `claude-icon.png`
- `~/.claude/instructions/` — `git-commits.md`, `skills.md`
- `~/.claude/scripts/` — `statusline.sh`
- `~/.claude/commands/`, `~/.claude/agents/` — empty; create in repo for future use

### What must NOT move

Machine state: `projects/`, `history.jsonl` (3.4M), `sessions/`, `cache/`, `file-history/`,
`shell-snapshots/`, `session-env/`, `paste-cache/`, `stats-cache.json`, `telemetry/`,
`plugins/`, `backups/`, `jobs/`, `tasks/`, `debug/`, `daemon/`, `daemon.log`, `security/`,
`ide/`, `plans/`, `.cc-writes/`, `.last-cleanup`, `gsd-file-manifest.json`,
`security_warnings_state_*.json`, `.anthropic/`.

Note: `~/.claude/.credentials.json` does **not** exist — credentials live in the macOS
Keychain (service "Claude Code-credentials"). Nothing to protect there.

`~/.claude/settings.json.bak` (3.9k, dated 20 Mar) is a stale hand-made backup. Leave it in
place; do not version it. Optionally delete after the migration is verified.

Already managed, leave alone:
- `~/.claude/skills/` — per-skill symlinks (re-pointed in step 2)
- `~/.claude/tmux-resurrect-hooks` — symlink into the nix store, owned by `home.nix:153–154`.
  **Do not bring into `agent-config`**; `settings.json` references it by the stable
  `~/.claude/...` path and a moving store path would 404 after a GC.

### Why symlinks are safe

Every path inside `settings.json` is `~/.claude/…`-relative — no absolute nix-store paths.
Verified, the full set is: `hooks/{bash-guard,gh-api-guard,git-transport-guard,notify,
validate-commit}.sh`, `scripts/statusline.sh`, and `tmux-resurrect-hooks/
{claude-session-track,claude-session-cleanup}.sh`. Redirecting `~/.claude/hooks` to the repo
is therefore invisible to Claude Code.

### Procedure — literal commands

```sh
# 0. Back up. Delete only after §3 verification passes.
cp -a ~/.claude ~/.claude.bak-pre-agent-config

# 1. Create the repo.
mkdir -p ~/Tech/agent-config/claude
cd ~/Tech/agent-config
git init

# 2. Copy content in, preserving mode/timestamps (-a is required: settings.json is 0600).
cp -a ~/.claude/CLAUDE.md      claude/CLAUDE.md
cp -a ~/.claude/settings.json  claude/settings.json
cp -a ~/.claude/hooks          claude/hooks
cp -a ~/.claude/instructions   claude/instructions
cp -a ~/.claude/scripts        claude/scripts
mkdir -p claude/commands claude/agents

# 3. Confirm the mode survived the copy before going further.
stat -f '%Sp %N' claude/settings.json claude/CLAUDE.md
#   expect: -rw-------  claude/settings.json
#           -rw-r--r--  claude/CLAUDE.md

# 4. Commit the baseline BEFORE deleting the originals. Step 2 requires a commit to exist.
#    (.gitkeep so the empty dirs survive; git does not track empty directories.)
touch claude/commands/.gitkeep claude/agents/.gitkeep
git add -A
git commit -m "Import Claude global config from ~/.claude"

# 5. Replace originals with symlinks.
rm    ~/.claude/CLAUDE.md ~/.claude/settings.json
rm -rf ~/.claude/hooks ~/.claude/instructions ~/.claude/scripts
rmdir ~/.claude/commands ~/.claude/agents        # both are empty; fails loudly if not
ln -s ~/Tech/agent-config/claude/CLAUDE.md     ~/.claude/CLAUDE.md
ln -s ~/Tech/agent-config/claude/settings.json ~/.claude/settings.json
ln -s ~/Tech/agent-config/claude/hooks         ~/.claude/hooks
ln -s ~/Tech/agent-config/claude/instructions  ~/.claude/instructions
ln -s ~/Tech/agent-config/claude/scripts       ~/.claude/scripts
ln -s ~/Tech/agent-config/claude/commands      ~/.claude/commands
ln -s ~/Tech/agent-config/claude/agents        ~/.claude/agents
```

`.gitignore` — the repo holds only hand-authored content, so this is minimal:
```
.DS_Store
*.log
```

`README.md` — short: what the repo is (global agent/Claude config, symlinked into
`~/.claude`), how to install on a new machine (`./install.sh`), and the rule that generated
state stays in `~/.claude` and is never added here.

`install.sh` — extend the idiom already used by `personal-skills/install.sh` (it resolves
`SCRIPT_DIR`, `mkdir -p` the target, then for each item removes any existing symlink or
directory and `ln -s`). Two loops: one linking each `claude/<item>` to `~/.claude/<item>`,
one linking each `skills/<dir>` containing a `SKILL.md` to `~/.claude/skills/<name>`. Must be
idempotent (safe to re-run) and must refuse to clobber a **real** file that is not a symlink
without an explicit `--force`, so a re-run on a fresh machine cannot silently destroy
existing config.

### Verification gate — all four must pass before step 2

1. `ls -la ~/.claude/settings.json ~/.claude/hooks` — both show as symlinks into
   `~/Tech/agent-config/`.
2. `stat -f '%Sp' ~/.claude/settings.json` resolves through the link to `-rw-------`.
3. Start a **fresh** Claude Code session and confirm the statusline renders (proves
   `statusLine.command` → `~/.claude/scripts/statusline.sh` resolves through the symlink).
4. Confirm a `PreToolUse` hook still fires. **Read `~/Tech/agent-config/claude/hooks/
   bash-guard.sh` first** to find a pattern it actually rejects, then issue a matching Bash
   call and confirm the block. Do not guess a test command — a non-triggering guess looks
   identical to a broken hook.

If any fail: `rm` the symlinks and `cp -a ~/.claude.bak-pre-agent-config/<item> ~/.claude/`
to restore, then diagnose before proceeding.

---

## 4. Step 2 — move `personal-skills` into `agent-config/skills`

`~/Tech/Bespoke/personal-skills` is a local-only git repo (**no remote**, branch **`master`**,
31 commits) holding: `beall-compose`, `bespoke-sidecar`, `create-pr`, `grill-me`, `handoff`,
`refactoring-claude-md`, `rewrite-branch-commits`, `ubiquitous-language`, `wrap-up`, plus
`install.sh` and `.gitignore`. Only **7 of 9** are symlinked into `~/.claude/skills/`
(`refactoring-claude-md` and `ubiquitous-language` are not).

**Prerequisite**: step 1 must have produced at least one commit — `git subtree add` merges
into HEAD and fails on an unborn branch.

```sh
cd ~/Tech/agent-config
# Direct-path form: the repository argument may be a filesystem path.
# No `git remote add` is needed — an earlier draft said otherwise and was wrong.
git subtree add --prefix=skills /Users/cyrilledru/Tech/Bespoke/personal-skills master
```

Then:
1. Re-point the 7 existing symlinks in `~/.claude/skills/` to
   `~/Tech/agent-config/skills/<name>` (or just run the new `install.sh`).
2. Fold `personal-skills/install.sh` logic into the top-level `install.sh`; delete the
   subtree's copy.
3. Update the **3** references to `~/Tech/Bespoke/personal-skills/` in
   `agent-config/claude/instructions/skills.md` (lines 5, 7, 13) to
   `~/Tech/agent-config/skills/`. **`~/.claude/CLAUDE.md` contains no such reference** —
   verified, nothing to change there.
4. **Leave `~/Tech/Bespoke/personal-skills` in place, untouched**, until symlinks are
   verified. Retire it in a later commit.

Verify: `/help` in a fresh session lists the same skills as before.

**Note**: `~/Tech/Bespoke/agent-sidecar` is a different thing — per-work-repo content keyed
by Bespoke repo name, also remote-less. Out of scope; do not touch.

---

## 5. Step 3 — remove the Ghostty init script, add aliases

### Edits to `hosts/2023-macbook-pro/home.nix`

1. Delete the `ghosttyTabInitScript` binding (lines **57–59**) and its comment block
   (lines **49–56**). Preserve the rationale in the commit message, not the file.
2. Remove `command = "${ghosttyTabInitScript}";` (line **461**).
3. Add to `shellAliases` (opens at line **478**):
   ```nix
   tm = "tmux new-session -As main";
   hd = "herdr --session main";
   ```
   Both `tm` and `hd` are verified unused today.
4. Add `herdr` to `home.packages`.

Then `just switch`. **Report all warnings.** Note §0: if the binary cache misses, this
triggers a Rust+Zig compile — allow time.

### Ghostty reload behaviour

`just switch` rewrites `~/.config/ghostty/config` (a symlink into the nix store; the target
path changes). Ghostty reads `command` when launching a new surface and re-reads config on
`Cmd+Shift+,` or restart. **Expect a Ghostty restart to be needed.** Try reload-config first;
open a new tab and check whether it lands in a plain login shell (`echo $TMUX` empty) or
still inside tmux. If still tmux, quit and relaunch Ghostty. This is a genuine
verify-by-observation point, not scripted.

### The 23 tmux sessions are safe

The tmux **server** is a long-lived background process independent of how clients attach
(PID 36688, running since 2026-08-05). Removing the init script only stops new tabs from
*auto-attaching*; it does not signal or stop the server. Afterwards `tm` reattaches to all 23
sessions.

**One real consequence**: after a reboot, nothing auto-starts tmux. Today the first Ghostty
tab starts the server, firing the socket-guarded restore trigger. Now you must run `tm`
yourself. The snapshot is not at risk (`~/.tmux/resurrect/last` persists on disk), but
continuum cannot autosave a server that is not running. Claude transcripts live in
`~/.claude/projects/<slug>/<session-id>.jsonl` and survive regardless.

**Revert**: restore the two `home.nix` hunks, `just switch`. One-line change either way.

---

## 6. Step 4 — install and configure herdr

### 6a. Install

Via `pkgs.herdr` in `home.packages` (step 3). Confirm `herdr --version` → 0.8.0.

Do **not** use `brew services start herdr` — the server starts on demand, and a brew service
would conflict with the nix-installed binary. Do **not** run `herdr update` — it would fight
nix; version is pinned by `flake.lock`.

### 6b. Claude integration — the one risky moment

```sh
cd ~/Tech/agent-config && git status --short   # confirm clean before
herdr integration install claude
```

This writes `~/.claude/hooks/herdr-agent-state.sh` and edits `~/.claude/settings.json` —
both now symlinks into `agent-config`.

**Immediately afterwards, in this order:**

```sh
ls -la ~/.claude/settings.json          # 1. still a symlink?
stat -f '%Sp' ~/.claude/settings.json   # 2. still -rw-------?
python3 -m json.tool ~/.claude/settings.json >/dev/null && echo "valid JSON"
cd ~/Tech/agent-config && git diff       # 3. what did it inject?
```

3. Confirm the pre-existing `tmux-resurrect-hooks` `SessionStart`/`SessionEnd` entries are
   **still present** — both hook sets must coexist so tmux restore keeps working during the
   trial.

**If the symlink was replaced by a regular file** (installer used rename-replace):
```sh
cp -a ~/.claude/settings.json /tmp/settings-herdr-modified.json  # keep herdr's edit!
diff /tmp/settings-herdr-modified.json ~/Tech/agent-config/claude/settings.json
cp -a /tmp/settings-herdr-modified.json ~/Tech/agent-config/claude/settings.json
rm ~/.claude/settings.json
ln -s ~/Tech/agent-config/claude/settings.json ~/.claude/settings.json
stat -f '%Sp' ~/.claude/settings.json   # confirm -rw------- survived
```
Order matters: capture herdr's version *first*, or the edit you wanted to inspect is lost.
Do not leave `~/.claude/settings.json` missing at any point — a concurrent Claude Code
session reads it.

**Then decide** on `settings.json` vs `settings.local.json` — only after seeing the diff:
- If herdr added a **static** hook entry (most likely; the hook reports session identity for
  resume), keep it tracked in `settings.json`.
- If herdr writes **mutable state**, move those keys to `~/.claude/settings.local.json`
  (Claude Code reads it; it overrides `settings.json`) and gitignore it. Note herdr's
  installer targets `settings.json` specifically and shows no awareness of `.local`, so any
  split is applied manually after the fact.

### 6c. Config file

```sh
mkdir -p ~/.config/herdr
herdr --default-config > ~/.config/herdr/config.toml
```
Then set:
```toml
[theme]
name = "catppuccin"

[ui.toast]
delivery = "system"      # Ghostty already has desktop-notifications = true; "terminal" also viable

[ui.sound]
enabled = true

[session]
resume_agents_on_restore = true

[update]
channel = "stable"       # never "preview"; version is pinned by flake.lock
```
Leave `manifest_check` at its default — disabling it also stops agent-detection manifest
updates, which matters because Claude state detection is screen-scraped.

Once the config stops changing daily, move it into `agent-config` as `herdr/config.toml`
with a symlink. Not before — it will churn during the trial.

---

## 7. Binding mapping

herdr's prefix is **`ctrl+b`**, same as tmux today. Defaults match more closely than expected.

| tmux (current) | herdr default | Action |
|---|---|---|
| `prefix h/j/k/l` pane nav | `focus_pane_left/down/up/right` = `prefix+h/j/k/l` | none — already matches |
| `prefix z` zoom | `zoom = "prefix+z"` | none |
| `prefix c` new window | `new_tab = "prefix+c"` | none |
| `prefix Tab` last session | `cycle_pane_next = "prefix+tab"`; `last_pane` unset | map `last_pane`, or `previous_workspace`/`next_workspace` (both unset by default) |
| `prefix s` session picker | `workspace_picker = "prefix+w"`; **`prefix+s` = `settings`** | learn `prefix+w`. Consider moving `settings` off `prefix+s` to avoid a costly mis-key |
| `prefix S` project→session | `new_workspace = "prefix+shift+n"` (name prompt only) | **rebuild** — see below |
| `prefix H/J/K/L` resize | `resize_mode = "prefix+r"` (a mode, not per-key resize) | different model; learn `resize_mode` |
| `prefix r` reload | `reload_config = "prefix+shift+r"` | **do NOT rebind to `prefix+r`** — that is `resize_mode`'s default and would silently collide |
| `%` / `"` split | `split_vertical = "prefix+v"`, `split_horizontal = "prefix+minus"` | learn new keys |
| copy-mode `v`/`C-v` | `edit_scrollback = "prefix+e"`, `copy_on_select = true` | different model — evaluate during trial |
| `history-limit 100000` | `[advanced] scrollback_limit_bytes = 10000000` | byte-based, not line-based; likely comparable |

Other keys worth knowing: `close_pane = "prefix+x"`, `close_tab = "prefix+shift+x"`,
`toggle_sidebar = "prefix+b"`, `rename_pane = "prefix+shift+p"`, `switch_tab = "prefix+1..9"`.

### The zoom-toggle question

tmux auto-unzooms, moves, re-zooms:
```
bind -r h if -F "#{window_zoomed_flag}" "select-pane -L ; resize-pane -Z" "select-pane -L"
```
**This is not reproducible declaratively in herdr** — `focus_pane_*` and `zoom` are
independent actions, and TOML maps one key to one action with no conditional primitive.

Options, in order:
1. **Test whether it is still needed.** The tmux workaround exists because tmux zoom *hides*
   sibling panes. If herdr's model differs, the problem may not arise. Try `prefix+h` while
   zoomed and observe. **Do this on day 0** — it determines whether 2/3 are needed.
2. `[[keys.command]]` with `type = "shell"` driving the socket API (`herdr pane …`) to
   unzoom→focus→zoom. Plausible but unverified, and a shell round-trip per keypress may lag.
3. Accept the loss; use `prefix+z` manually.

### Rebuilding `prefix S` — feasible, needs writing

`herdr workspace create --cwd <PATH> --label <TEXT> --focus [--env KEY=VALUE]` exists, and
`[[keys.command]]` supports `type = "popup"` ("session-modal terminal without changing the
tab layout") with `width`/`height` in cells or percentages.

Write a script (e.g. `agent-config/herdr/new-workspace.sh`) translating the existing tmux
binding line-by-line: `fd -t d --no-ignore-vcs --max-depth 5 --exclude '.*' --exclude
node_modules . ~ | fzf --reverse`, derive the label via `basename` with dots→underscores,
then `herdr workspace create --cwd "$dir" --label "$name" --focus`. Bind it:
```toml
[[keys.command]]
key = "prefix+shift+s"
type = "popup"
command = "~/Tech/agent-config/herdr/new-workspace.sh"
width = "80%"
height = "80%"
```
This script is **not yet written** — writing it is part of day 0.

Also: `[terminal] new_cwd` controls default cwd for new panes/tabs/workspaces when no `--cwd`
is given — `"follow"` (inherit, the default), `"home"`, `"current"`, or a fixed path. And
herdr has native git worktree support (`herdr worktree`, `new_worktree = "prefix+shift+g"`,
`[worktrees] directory = "~/.herdr/worktrees"`) with no tmux equivalent.

---

## 8. Trial schedule

A reviewer raised the central flaw in the original schedule: **the goal only exists at scale.**
A blocked-state sidebar that works with 3 agents proves nothing about finding what is waiting
among 23. The schedule below fixes that by scaling *before* the make-or-break gate.

**Day 0 — setup.** Steps 1–4. Port bindings, write the `prefix S` script, answer the
zoom question (§7 option 1). Ends with herdr configured and tmux still fully working via `tm`.

**Days 1–2 — pilot, 3 projects.** Move `nix-config`, `pata-vault`, `personal-skills`.
Purpose is shaking out setup bugs, not judging the dashboard. Judge: do bindings feel right,
does `prefix S` equivalent work, do notifications fire at all.

**Day 3 — scale up to 10+ projects.** This is the earliest point the actual goal can be
tested. Judge blocked-state accuracy across enough concurrent agents that the sidebar has to
earn its keep.

**Day 4 — reboot test at scale.** Reboot with 10+ agents live in herdr and verify
`resume_agents_on_restore` reattaches conversations. Do this **after** scaling, not before —
a failure mode that only appears at n=10 must not pass a gate set at n=3. herdr's own docs
concede a snapshot alone restores layout but "processes don't resume"; resume depends on the
integration working.

**Days 5–7 — full weight.** If days 3–4 pass, move the rest. Keep tmux reachable (`tm`) but
unused.

### Migrating a live session (needed from day 1, heavily on day 5)

Per project, this is not automatic — write it down before starting:
1. In the tmux pane, note the Claude session id (`~/.tmux/resurrect/assistant-sessions.json`
   maps `session:window.pane` → `session_id` and `cwd`).
2. Create the herdr workspace at the same cwd (`prefix+shift+s`, or `herdr workspace create
   --cwd … --label … --focus`).
3. In the new pane: `claude --resume <session-id>`.
4. Leave the tmux session alone — do not kill it. It costs nothing and is the fallback.

The tmux server keeps autosaving in the background throughout; that is harmless and means
tmux stays a working fallback for anything not yet moved.

### Decision criteria — measurable, fed by the log

Adopt only if all of:
1. **Blocked-state false negatives** (agent waiting, sidebar did not show it) — the metric
   that matters most, since a missed prompt is exactly the failure the trial exists to
   prevent. Target: **zero** over days 3–7 at 10+ sessions. Even one or two is disqualifying
   for the stated goal unless the cause is understood and fixable.
2. **Blocked-state false positives** — tolerable if rare; note the rate.
3. **Reboot resume**: at least **2** reboot cycles at 10+ sessions, **100%** of agent panes
   resumed into the right conversation and cwd. Anything less is worse than tmux today.
4. **`prefix S` equivalent** rebuilt and comfortable.
5. **No unrecovered crash** of the herdr server (see §9.6 for what to do if one happens).

### Trial log

`agents/docs/herdr-trial-log.md`, dated entries. Record specifically: every blocked-state
miss or false alarm (with session count at the time), every reboot cycle and its resume
result, anything the installer changed in `settings.json`, and any herdr crash. Without these
counts, criteria 1–3 cannot be evaluated at the end of the week.

---

## 9. Risks

1. **`settings.json` symlink replacement** by the herdr installer — check immediately (§6b).
2. **Pre-1.0 churn**: ~weekly releases, config stability not guaranteed. Version is pinned by
   `flake.lock`; never run `herdr update` or set `channel = "preview"`.
3. **Claude state detection is screen-scraped**, unlike OpenCode/Kimi. This is the weakest
   link and criterion 1 exists to measure it.
4. **Coexistence with tmux is inferred, not documented.** No vendor statement found.
   Architecturally independent (separate sockets and config dirs; herdr never touches
   `~/.tmux/resurrect/`), but watch for both fighting over terminal title escape sequences.
5. **No auto-start after reboot** for either tool once `ghosttyTabInitScript` is gone.
6. **herdr server crash mid-trial.** Recovery: restart with `hd`; if agents do not come back,
   fall back to `claude --resume <session-id>` by hand in a plain shell — session ids are in
   `~/.claude/projects/<slug>/` and, for anything not yet migrated,
   `~/.tmux/resurrect/assistant-sessions.json`. **Conversation history is never lost**;
   transcripts are files independent of any multiplexer. Only process continuity is at risk.
7. **Do not nest** herdr inside a tmux pane or vice versa — `[experimental] allow_nested`
   defaults to `false` deliberately.
8. **A cache miss on `pkgs.herdr`** turns `just switch` into a multi-minute Rust+Zig build.

---

## 10. Repo conventions

- **`git fetch` and check against `origin/main` before editing** — the daily Action pushes
  "Upgrade flake" commits most days. (At writing, local `main` was 1 ahead, tree clean.)
- **New files must be `git add`ed before `just switch`** — nix copies only tracked files;
  untracked files silently deploy nothing.
- **Never run mutating brew commands.** herdr comes from nixpkgs.
- **Commit prefix `MBP2023`** for changes touching only the 2023 MacBook.
- **Report all warnings** from `just switch`.
- `agents/scripts/test-tmux-resurrect.sh` does **not** cover this work (it runs with
  `-f /dev/null` and never loads the real config). Step 3 changes only how tmux is attached
  to, not the tmux config itself, so the existing chain is not at risk. If any tmux config is
  touched, use the manual socket-guard recipe in
  `agents/instructions/working-in-this-repo.md`.

---

## 11. Open question for the user — framing

herdr has `herdr --remote <ssh-target>` and manages its own SSH config
(`[remote] manage_ssh_config`), so remote attach exists. But the home-server currently has no
`programs.tmux` block at all and is reached by plain `ssh home-server.local`.

If tmux must stay on the home-server regardless of how this trial goes, then the honest
target state is **"herdr for local agent work, tmux still present"** rather than "replace
tmux". That is still a win for the stated goal — the goal is agent visibility, not removing
tmux — but it changes what "success" means and whether the tmux config in `home.nix` ever
actually gets deleted.

**Worth settling before day 5**, when the decision to move everything is made. It does not
block days 0–4.
