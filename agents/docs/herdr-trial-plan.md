# herdr trial plan

Written 2026-08-16, revised 2026-08-26 after several independent verification passes.
Executed by separate sessions — this document is the spec and should be followed
without needing the conversation that produced it.

Goal: run **herdr** alongside tmux on the 2023 MacBook Pro for long enough to decide whether
to commit to it. The motivation is agent visibility: a single place showing every Claude
session and which are blocked waiting for input. tmux gives no such view today.

Existing tmux sessions are not migrated — they stay where they are, and tmux remains the
fallback throughout. New work goes into herdr until there is enough there to judge.

Out of scope: the 2018 MacBook Pro (its tmux config is known-divergent and partly broken;
ignored until the 2023 machine decides). Also out of scope: the home-server — see §11.

## How this document is split

Two parts, executed in order.

| Part | What | Why it is where it is |
|---|---|---|
| **Part 1** (§5–§6) | Install and configure herdr; make it reachable from Ghostty | Ends with herdr usable day to day, tmux still working. **Longest part in wall-clock time** — see its sub-boundaries below. |
| **Part 2** (§7–§9) | Use it, and test the hard scenarios — reboots above all | Deferred until herdr is genuinely in use. A reboot test with three sessions proves nothing about a full working set. |

Part 1 is the one likely to span sessions. Its natural stopping points:

| Sub-step | Ends with |
|---|---|
| §5 | herdr installed, aliases live, Ghostty opens a plain shell |
| §6a | Claude integration installed and its `settings.json` diff committed |
| §6b | `~/.config/herdr/config.toml` written |
| §6c | bindings learned, zoom question answered, `new-workspace.sh` written |

**If you are a fresh session picking this up**, start at §1 — it says where to begin. Treat it
as a claim to spot-check, not gospel.
**Before you stop, update §1** so the next session knows where it left off. That is the only
handoff mechanism; nothing else records progress.

### Optional prerequisite — versioning the Claude config

`agents/docs/agent-config-versioning.md` describes moving the hand-authored parts of
`~/.claude` into a git repo. Doing that **first** is preferable, because §6a runs
`herdr integration install claude`, which edits `~/.claude/settings.json` — on a versioned file
that edit lands as a reviewable diff on a committed baseline.

**It is not a blocker.** That work stands on its own and has nothing to do with herdr. If it is
not done, get the same safety property cheaply: copy `~/.claude/settings.json` somewhere before
running the installer, and diff against the copy afterwards. Do not let a repo migration hold
up the decision this document exists to make.

### A note on numbers in this document

Line numbers, file sizes and counts drift. Anything of that kind here is a **navigation hint
as of the date given, not a fact to rely on** — grep for the named anchor before editing, and
re-measure counts at execution time rather than quoting them from this file.

---

## 1. State of play — update this before ending a session

This is a checklist, not a glossary. Every term below is explained in the section it belongs
to; if something here means nothing to you yet, go to the section named beside it.

**Last updated:** _never — nothing has been executed yet._

| Step | Status | Notes |
|---|---|---|
| §5 — install + aliases | **not started** | |
| §6a — Claude integration | **not started** | |
| §6b — config file | **not started** | |
| §6c — bindings + script | **not started** | |
| Part 2 — use and hard scenarios | **not started** | |

Statuses are coarse. If you stop **mid**-sub-step — §6a in particular has an internal
verify-then-commit sequence — say so in that row's Notes, or the next session will assume the
whole sub-step is untouched.

**Findings and decisions** (fill in as you go — later parts depend on these):

- herdr version actually installed: _not yet installed_
- Claude config versioned first (the optional prerequisite above): _no_ — if no, note where
  the pre-install copy of `settings.json` was kept
- Zoom-toggle question (§6c): _unanswered_
- What `herdr integration install claude` injected: _not yet run_
- `new-workspace.sh` written and working: _no_
- Warnings from `just switch`, and anything worked around: _none yet_
- Home-server question (§11) settled: _no_
- **Open question for the user, if any:** _none_ — put anything here that the next session
  must resolve with the user before continuing.

---

## 2. Verified facts

Checked against the binary, the live system, and herdr's source on 2026-08-15/16, re-verified
2026-08-24/26. Do not re-derive.

### Packaging

- **herdr is in official nixpkgs**: `pkgs/by-name/he/herdr/package.nix`, Apache-2.0,
  maintainers `kevinpita` + `faukah`. Use `pkgs.herdr`; the third-party
  `numtide/llm-agents.nix` flake is NOT needed.
- **Version tracks nixpkgs — do not pin.** `flake.lock` is advanced daily by the GitHub
  Action, so `pkgs.herdr` is whatever nixpkgs currently ships, and it will move during the
  trial. nixpkgs also lags upstream releases by design; both are expected and acceptable.
  This drifts fast enough to be worth demonstrating: the lock gave 0.8.0 when this was written
  on 2026-08-16 and 0.8.2 three days later. **Confirm the version at execution time**
  (`nix eval --raw .#darwinConfigurations.Cyrils-MacBook-Pro.pkgs.herdr.version` before
  installing, `herdr --version` after) and record it in §1 — a mid-trial version bump is worth
  noting in the log, since resume behaviour is exactly the kind of thing it could change.
- **It is a source build, not a prebuilt binary.** `rustPlatform.buildRustPackage` with
  `src = fetchFromGitHub`, a `cargoHash`, and a **`zig_0_15`** dependency compiling
  `vendor/libghostty-vt`. The exact store path is normally on `cache.nixos.org`, so
  `just switch` fetches (~6 MiB) rather than compiles. **But any `flake.lock` bump moves the
  derivation hash**, and a cache miss means a real Rust + Zig compile taking minutes. Budget
  for it; do not treat a slow `just switch` as a hang.
- `meta.platforms` is `lib.platforms.unix` — includes `aarch64-darwin`, excludes
  `x86_64-darwin`. Relevant only if the 2018 machine ever comes into scope.

### Behaviour

- **Session model**: client/server like tmux. `herdr --session <name>` creates-or-attaches a
  named persistent session — the direct analogue of `tmux new-session -As main`.
- **Config is merged over defaults.** Verified in source: every config struct is
  `#[serde(default)]`, and `Config::load()` returns `Self::default()` when the file is absent.
  **Write a minimal config containing only your overrides.** Do not dump
  `herdr --default-config` and edit it — that produces a full snapshot of defaults which then
  silently rots as upstream defaults change, and re-running the dump wipes your edits.
  Unknown keys produce a startup warning, not a failure.
- **Agent resume is native**: `[session] resume_agents_on_restore = true` (already the
  default) — "Resume supported AI-agent panes into their native conversation sessions after a
  Herdr server restart."
- **herdr keeps its own pane→session state** at `~/.config/herdr/session.json` (JSON,
  `SNAPSHOT_VERSION = 3`). Each pane entry carries both `cwd` and, when an agent reported one,
  `agent_session.value` = the Claude session id. This is herdr's internal format, not a
  documented stable API — read it defensively (tolerate a missing `agent_session`, check the
  version field). §8 depends on this file.
- **Desktop notifications exist**: `[ui.toast] delivery` accepts `off`|`herdr`|`terminal`|
  `system` (default `off`). Plus `[ui.sound]` with `enabled`, `request_path` (needs-attention)
  and `done_path`.
- **Scrollback/copy is covered**: `edit_scrollback = "prefix+e"` (a `[keys]` binding that opens
  scrollback in `$EDITOR`), and under `[ui]`: `copy_on_select = true`, `mouse_capture = true`,
  `mouse_scroll_lines = 3`. `[advanced] scrollback_limit_bytes` defaults to 10000000. Note
  `copy_mode` (`prefix+[`) is a *separate* binding from `edit_scrollback` — different purposes.
- **Catppuccin is a built-in theme** (`[theme] name = "catppuccin"`), with `auto_switch`.
- **Claude state detection is screen-scraped.** herdr's `agents` doc: it "identifies the
  foreground process and reads the live bottom-buffer screen snapshot," then evaluates TOML
  manifests against it. Agents like OpenCode/Kimi are "lifecycle authority" — their hooks
  author `idle`/`working`/`blocked` directly. Claude is not. This is the feature most likely
  to be flaky and is the main thing the trial judges.
- **Maturity**: pre-1.0, config stability explicitly not guaranteed. Release cadence is
  irregular — same-day doubles (v0.7.2/v0.7.3) through 16-day gaps (v0.8.0→v0.8.2). Earlier
  drafts said "near-weekly"; that overstates the regularity.

### What `herdr integration install claude` actually does

Verified by reading `src/integration/claude_settings.rs` and its unit tests. This defuses
most of the risk earlier drafts attached to this step.

- Writes `~/.claude/hooks/herdr-agent-state.sh` (marked "managed by herdr; reinstalling
  overwrites this file").
- Edits `~/.claude/settings.json` **in place with a CST-based JSONC editor** that preserves
  formatting and comments — not a blind rewrite.
- Registers exactly **one** hook, on `SessionStart`:
  ```json
  { "matcher": "*",
    "hooks": [ { "type": "command",
                 "command": "bash '/Users/cyrilledru/.claude/hooks/herdr-agent-state.sh' session",
                 "timeout": 10 } ] }
  ```
- **It appends; it does not replace.** Unit tests
  (`install_removes_only_owned_commands_from_shared_hook_groups`,
  `install_preserves_canonical_session_start_position_during_migration`) assert that foreign
  entries in shared hook arrays survive untouched. Removal is matched against *herdr's own*
  hook command path, never by clearing an event array.
- It is byte-exact idempotent when the hook is already present, and refuses to touch a
  structurally invalid file rather than guessing.
- **Your `tmux-resurrect-hooks` `SessionStart`/`SessionEnd` entries are therefore safe.**
  Verify anyway (§5) — but expect them to survive.

### Corrections — do not act on these retracted claims

- The resurrect state is **NOT degraded**. An earlier 7.6k reading was a transient `ls` during
  an in-progress write. Nothing to fix.
- The `@continuum-save-interval` live `5` vs configured `15` is **not actionable drift**.
  `home.nix:343` and the deployed `~/.config/tmux/tmux.conf:57` both say `15`. The running
  server predates that edit and self-corrects on next restart. (Server started
  **Wed 2026-08-05 21:24:46**, PID 36688 — an earlier claim of "21 Jul" was wrong.)
- `settings.json` is **entirely hand-authored**. No machine-generated churn. Version it
  directly; the earlier "snapshot instead of symlink" idea is withdrawn.
- `ta` is **not** user-defined — it ships with the oh-my-zsh `tmux` plugin (`ta`/`ts`/`tl`).
- **herdr↔tmux coexistence IS documented** — an earlier draft wrongly said no vendor statement
  existed. herdr's `agents` doc: "Herdr can run inside tmux as the outer terminal environment.
  Agent detection does not inspect tmux sessions launched inside a Herdr pane. If a shell
  framework auto-enters tmux inside Herdr, Herdr sees tmux as the pane process instead of the
  agent behind it." There is also a first-party herdr-vs-tmux comparison page. Consequence:
  **never let a herdr pane auto-enter tmux** — that silently breaks agent detection, which is
  the entire point of the trial. See §10.7.
- `herdr pane …` is **not** "plausible but unverified" — it is a full, stable subcommand family
  (`list`/`get`/`focus`/`resize`/`zoom`/`split`/`send-keys`/`run`/`report-agent`/…). An earlier
  draft hedged unnecessarily; §6 option 2 is more viable than it implied.

---

## 3. Current tmux setup — what must be preserved

Source of truth: `hosts/2023-macbook-pro/home.nix`, deployed to `~/.config/tmux/tmux.conf`
(no legacy `~/.tmux.conf` exists).

**Scale**: roughly one tmux session per project, named after the project directory basename,
with a subset of panes running Claude. The exact counts drift daily — measure rather than
quote: `tmux ls | wc -l` for sessions, and for Claude panes, walk each pane's process
**subtree** (not just its direct children — `claude` often runs under an intermediate
process, and a direct-children check undercounts).

**Custom bindings** (`home.nix:~420–450`, as of 2026-08-26; the other ~90 prefix bindings are
tmux stock):

| Binding | Action |
|---|---|
| `prefix r` | reload config |
| `prefix h/j/k/l` | vim pane nav, **auto-unzoom then re-zoom** if window was zoomed |
| `prefix H/J/K/L` | resize pane by 5 (repeatable) |
| `prefix Tab` | `switch-client -l` (last session) |
| `prefix s` | fzf popup over existing sessions → `switch-client` |
| `prefix S` | fzf popup over `fd`-discovered dirs under `~` → create session named after basename (dots→underscores) at that cwd, then switch |
| `v` / `C-v` (copy-mode-vi) | begin-selection / rectangle-toggle |

`prefix S` is how the existing sessions came to exist. No tmuxinator/tmuxp.

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

**Known gap in that chain**: the hook registry is incomplete. Measured 2026-08-26,
`assistant-sessions.json` held 13 entries while 18–19 panes were actually running Claude —
and two counts taken minutes apart disagreed, so treat the gap as real and variable rather
than a fixed number. §8's backup must not trust this file as its sole source.

**Ghostty attach mechanism** (`home.nix:57–59`, referenced at `:461`):
```nix
ghosttyTabInitScript = pkgs.writeShellScript "ghostty-tab-init" ''
  exec zsh -l -c "/opt/homebrew/bin/tmux new-session -As main"
'';
```
Every new Ghostty window/tab runs this. `-A` makes it idempotent, so all tabs converge on
one server (`default` socket), session `main`.

---

## 4. Decisions already made — do not relitigate

1. **Remove `ghosttyTabInitScript` entirely** rather than adding a second entry point (a
   Ghostty keybinding was already tried and did not work). New tabs get a plain login shell;
   tmux and herdr become peers reached by aliases.
2. **Aliases** `tm` (tmux) and `hd` (herdr). Not `ta` — that is the oh-my-zsh plugin's bare
   `tmux attach` and does not create-or-attach.
3. **herdr is installed by nix, never Homebrew.** A `herdr` formula exists in homebrew-core
   and declares a `brew services` entry with `keep_alive: always` — starting it would create a
   persistent daemon competing with the nix binary for the same config and socket.
4. **Existing tmux sessions are not migrated.** They stay where they are; tmux remains the
   fallback. New work goes into herdr until there is enough there to judge.

Decisions about the `agent-config` repo itself (layout, symlink style, `git subtree`, no
remote) live in `agents/docs/agent-config-versioning.md`.

---

# PART 1 — install and configure herdr

Goal: herdr installed, themed, integrated with Claude, and reachable from a Ghostty tab.
tmux still fully working via `tm` at the end of this part.

## 5. Remove the Ghostty init script, install herdr, add aliases

### Edits to `hosts/2023-macbook-pro/home.nix`

Per repo convention, `git fetch` and check against `origin/main` before editing — the daily
Action pushes "Upgrade flake" commits most days.

**Line numbers below are approximate, as of 2026-08-26.** They drift by a line or two whenever
an upstream commit touches this file — they already have once. Grep for the named anchor to
find the real location before editing; do not `sed -n '<N>p'` on trust.

1. Delete the `ghosttyTabInitScript` binding (~lines **57–59**, anchor:
   `grep -n ghosttyTabInitScript`) and its comment block immediately above (~lines **49–56**).
   Preserve the rationale in the commit message, not the file.
2. Remove the `command = "${ghosttyTabInitScript}";` line in the Ghostty block (~line **462**,
   same grep).
3. Add to `shellAliases` (~line **479**, anchor: `grep -n 'shellAliases'`):
   ```nix
   tm = "tmux new-session -As main";
   hd = "herdr --session main";
   ```
   Both were unused as of 2026-08-26 — `zsh -lic 'type tm; type hd'` reported "not found" in a
   live login shell, and neither appears in `home.nix` or the oh-my-zsh plugins. Re-check the
   same way before adding, since a plugin update could claim either name (this is how the
   earlier `ta` mistake happened — see §2's corrections).
4. Add `herdr` to `home.packages`.

Then `just switch`. **Report all warnings.** If a cache miss triggers a Rust+Zig compile,
allow minutes (§2) — slow is expected here, and is not the same as hung.

**If `just switch` fails**, read `agents/instructions/troubleshooting.md` before improvising;
its section headings are the index of what it covers. The likeliest cause here is your own
edit — a nix eval error points at `home.nix`, and the line numbers above drift, so confirm you
edited the right lines. `just build` reproduces the failure without applying anything.

Afterwards confirm the new layout survived the rebuild:
```sh
ls -l ~/.claude/settings.json ~/.claude/hooks    # still symlinks into agent-config?
herdr --version                                   # note the actual version in §1
```

### Ghostty reload behaviour

`just switch` rewrites `~/.config/ghostty/config` (a symlink into the nix store; the target
path changes). Ghostty reads `command` when launching a new surface and re-reads config on
`Cmd+Shift+,` or restart. **Expect a Ghostty restart to be needed.** Try reload-config first;
open a new tab and check `echo $TMUX` — empty means you got a plain login shell (correct),
non-empty means it is still auto-attaching to tmux. If still tmux, quit and relaunch Ghostty.

A Ghostty quit does not kill the tmux server (PID 36688, `PPID 1`, independent of any client),
so the existing sessions and their Claude processes survive the relaunch.

### The existing tmux sessions are safe — with one caveat

The tmux **server** is a long-lived background process independent of how clients attach —
confirm it with `pgrep -f 'tmux.*server'` rather than trusting the PID cited in §2, which is
from 2026-08-16 and changes on any restart.
Removing the init script only stops new tabs from *auto-attaching*; it does not signal or stop
the server. Afterwards `tm` reattaches to them all.

**The caveat is reboots.** Today the first Ghostty tab starts the server, firing the
socket-guarded restore trigger. After this change nothing auto-starts tmux — you must run `tm`
yourself. This matters most in §8, where a deliberate reboot happens while sessions are still
split across both tools: **after any reboot during the trial, run `tm` to bring the tmux
sessions back.** The snapshot itself is not at risk
(`~/.tmux/resurrect/last` persists on disk), but continuum cannot autosave a server that is
not running, so a long gap before running `tm` means a staler snapshot.

**Revert**: restore all four edits from this section (the `ghosttyTabInitScript` binding, its
`command =` reference, the two aliases, and the `home.packages` entry), then `just switch`.

## 6. Configure herdr

### 6a. Claude integration

Take a baseline first, so you can see what the installer did. Which form depends on whether
the optional prerequisite was done:

```sh
# If ~/.claude/settings.json is a symlink into agent-config (prerequisite done):
cd ~/Tech/agent-config && git status --short   # confirm clean before

# If it is still a plain file (prerequisite skipped — this is the default):
cp -a ~/.claude/settings.json ~/settings.json.pre-herdr
```

Then:

```sh
herdr integration install claude
```

Per §2 this appends a single `SessionStart` hook and preserves foreign entries. Verify rather
than assume:

```sh
stat -f '%Sp %N' ~/.claude/settings.json   # 1. still -rw-------? still the same kind of file?
python3 -m json.tool ~/.claude/settings.json >/dev/null && echo "valid JSON"

# 2. what did it inject? — whichever baseline you took:
cd ~/Tech/agent-config && git diff
diff ~/settings.json.pre-herdr ~/.claude/settings.json
```

Confirm the pre-existing `tmux-resurrect-hooks` `SessionStart`/`SessionEnd` entries are
**still present** — both hook sets must coexist so tmux restore keeps working during the
trial. Record what was injected in §1. If you are using the repo, commit it; if you took a
plain copy, keep it until you have read the diff.

**If `settings.json` was a symlink and the installer replaced it with a regular file**
(contrary to expectation — it edits in place):
Capture into your **home directory, not `/tmp`** — Part 2 reboots this machine deliberately,
and `/tmp` does not survive that. If you are interrupted between the capture and the
re-symlink, the only copy of herdr's edit is this file; losing it means a later session
restores the stale repo version over herdr's work without ever knowing.

```sh
cp -a ~/.claude/settings.json ~/settings-herdr-modified.json  # keep herdr's edit!
python3 -m json.tool ~/settings-herdr-modified.json >/dev/null && echo "valid JSON"
diff ~/settings-herdr-modified.json ~/Tech/agent-config/claude/settings.json
cp -a ~/settings-herdr-modified.json ~/Tech/agent-config/claude/settings.json
rm ~/.claude/settings.json
ln -s ~/Tech/agent-config/claude/settings.json ~/.claude/settings.json
stat -f '%Sp' ~/.claude/settings.json   # confirm -rw------- survived
```
Order matters: capture herdr's version *first*, or the edit you wanted to inspect is lost.
Validate the JSON *before* symlinking it back — every live session reads this file. Do not
leave `~/.claude/settings.json` missing at any point.

Keep the hook tracked in `settings.json`. It is a static command entry, not mutable state, so
there is no reason to split it into `settings.local.json`.

### 6b. Config file

Write **only** the overrides — herdr merges over its defaults (§2). Do not dump
`herdr --default-config`.

```sh
mkdir -p ~/.config/herdr
```

`~/.config/herdr/config.toml`:
```toml
[theme]
name = "catppuccin"

[ui.toast]
delivery = "system"      # Ghostty already has desktop-notifications = true

[ui.sound]
enabled = true
```

`[session] resume_agents_on_restore` already defaults to `true` — no need to set it.
Leave `[update] manifest_check` at its default: disabling it also stops agent-detection
manifest updates, which matters because Claude state detection is screen-scraped.
Do not set `[update] channel = "preview"`, and never run `herdr update` — it is disabled for
Nix-managed installs by herdr's own design anyway.

Once the config stops changing, move it into `agent-config` as `herdr/config.toml` with a
symlink. Not before — it will churn during the trial.

### 6c. Binding mapping

herdr's prefix is **`ctrl+b`**, same as tmux today. Every default below was verified against
herdr's source (`impl Default for KeysConfig`) and is safe to rely on.

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
| copy-mode `v`/`C-v` | `edit_scrollback = "prefix+e"`, `copy_mode = "prefix+["`, `copy_on_select = true` | different model — evaluate during trial |
| `history-limit 100000` | `[advanced] scrollback_limit_bytes = 10000000` | byte-based, not line-based; likely comparable |

Other keys worth knowing: `close_pane = "prefix+x"`, `close_tab = "prefix+shift+x"`,
`toggle_sidebar = "prefix+b"`, `rename_pane = "prefix+shift+p"`, `switch_tab = "prefix+1..9"`,
`new_worktree = "prefix+shift+g"`.

### The zoom-toggle question

tmux auto-unzooms, moves, re-zooms:
```
bind -r h if -F "#{window_zoomed_flag}" "select-pane -L ; resize-pane -Z" "select-pane -L"
```
**This is not reproducible declaratively in herdr** — `focus_pane_*` and `zoom` are
independent actions, and TOML maps one key to one action with no conditional primitive.

Options, in order:
1. **Test whether it is still needed.** The tmux workaround exists because tmux zoom *hides*
   sibling panes. Zoom a herdr pane, press `prefix+h`, and observe: if focus moves to the
   pane you wanted and it is visible, the problem does not arise and options 2–3 are moot.
   **Do this first** and record the answer in §1.
2. `[[keys.command]]` with `type = "shell"` driving `herdr pane` (a full, stable subcommand
   family — `focus`, `zoom`, etc.) to unzoom→focus→zoom. A shell round-trip per keypress may
   lag; measure before committing to it.
3. Accept the loss; use `prefix+z` manually.

### Rebuilding `prefix S`

`herdr workspace create --cwd <PATH> --label <TEXT> --focus [--env KEY=VALUE]` exists, and
`[[keys.command]]` supports `type = "popup"` with `width`/`height` in cells or percentages.

Write `agent-config/herdr/new-workspace.sh`, translating the existing tmux binding — read it
first (`grep -n 'bind S' home.nix`, ~line 446 as of 2026-08-26). It runs `fd -t d
--no-ignore-vcs --max-depth 5 --exclude '.*' --exclude node_modules . ~ | fzf --reverse`,
derives the label via `basename` with dots→underscores, then calls `herdr workspace create
--cwd "$dir" --label "$name" --focus`.

Two cases the tmux binding handles implicitly and the script must handle explicitly:
- **fzf cancelled** (empty selection) — exit without creating anything.
- **label already exists** — decide whether to focus the existing workspace or create a
  second one.

**Run `herdr workspace --help` before writing this.** `herdr workspace list` exists, but this
document does not record its output format, nor the exact invocation for focusing an existing
workspace by label — discover both from the CLI rather than guessing.

Bind it:
```toml
[[keys.command]]
key = "prefix+shift+s"
type = "popup"
command = "~/Tech/agent-config/herdr/new-workspace.sh"
width = "80%"
height = "80%"
```
This script is **not yet written** — writing it is part of this section. Record status in §1.

Also: `[terminal] new_cwd` controls default cwd for new panes/tabs/workspaces when no `--cwd`
is given — `"follow"` (inherit, the default), `"home"`, `"current"`, or a fixed path. And
herdr has native git worktree support (`herdr worktree`, `new_worktree = "prefix+shift+g"`,
`[worktrees] directory = "~/.herdr/worktrees"`) with no tmux equivalent.

---

# PART 2 — use it, and test the hard scenarios

Goal: find out whether herdr does the thing it is for — showing which agents are blocked —
and whether it survives the things that actually cost you work.

**No migration is involved.** Existing tmux sessions stay where they are. Start *new* work in
herdr as it comes up, the same way you would have started it in tmux, until enough real
sessions are running there to judge it. Nothing is scripted for this and nothing needs to be.

Start the reboot testing (§8) only once herdr is carrying a realistic working set — a resume
test with three sessions proves nothing about a full one. There is no fixed threshold; judge
it by whether losing that set would actually hurt.

**Do not run `gc start` during the trial.** gascity spawns agents on its own tmux socket,
which herdr knows nothing about and the §8a backup would miss.

## 7. How to spot a blocked-state miss

This is the measurement the whole trial exists for, so it needs a method rather than
impressions.

**You already have an independent oracle: `notify.sh`.** It fires terminal-notifier per Claude
process, independent of any multiplexer, so it is a genuinely separate signal from herdr's
sidebar.

**Leave it enabled for the whole trial.** It is how you detect herdr's misses:

> A notification fires → look at the herdr sidebar → is that agent shown as blocked?
> If not, that is a **false negative**. Log it (§9) with what you were doing at the time.

The reverse direction gives you the other metric: sidebar says blocked, agent is not → false
positive.

### What the oracle actually covers — verified 2026-08-26

Re-check this against `~/.claude/settings.json` before relying on it; the wiring can change.

| Registered hook | Notification title | Covers |
|---|---|---|
| `Notification`, matcher `permission_prompt` | "Permission Needed" | agent blocked on a permission prompt |
| `PermissionRequest`, matcher `""` | "Permission Needed" | same, via the newer event |
| `Stop`, matcher `""` | "Ready for Input" | turn finished, agent idle awaiting you |

**`notify.sh` also contains a "Waiting for Input" branch for `Notification`/`idle_prompt`, but
no hook registers that matcher — it never fires.** So any blocking state that is neither a
permission prompt nor a turn ending has **no oracle at all**. Do not read silence from
terminal-notifier as evidence herdr is correct.

**This blind spot is not a corner case, and it must be tested deliberately.** "Blocked waiting
for input" covers more than permission prompts — an `AskUserQuestion` choice, a plan-mode
approval, or any interactive tool prompt all block the agent while firing no hook the oracle
watches. Those are exactly the states the trial's goal is about, and the oracle is blind to
every one of them.

So once or twice during the trial, deliberately drive an agent into each of those states and
**look at the sidebar yourself**. Log what herdr showed, marked as eyeball-checked rather than
oracle-backed. Without this, criterion 1's "zero" silently means "zero among permission
prompts and turn endings" — which is a narrower claim than the one the decision rests on.

### Latency vs. failure — do not conflate them

The two signals are different in kind: a notification is a discrete *event*, the sidebar shows
continuous *state*. That mismatch cuts both ways, and neither is a herdr defect:

- **Too soon.** `Stop` fires at the instant the agent goes idle. Checking the sidebar in the
  same second tests nothing — the state change and the notification are simultaneous by
  construction. Give herdr a few seconds to notice before judging.
- **Too late.** If the prompt was already answered before you looked, the agent is legitimately
  no longer blocked and the sidebar is right to say so.

**Wait a few seconds, then check — and log the delay you allowed.** A miss only counts if the
sidebar still shows nothing once herdr has plausibly had time to see it. If you find yourself
unsure whether something was lag or a real miss, log it as uncertain rather than as a miss;
criterion 1's bar is zero, so inflating it with polling lag makes the criterion useless.

### One caveat about the oracle itself

`notify.sh` and its pinned `terminal-notifier` are, per
`agents/instructions/troubleshooting.md`, expected to be **deleted once notifications move to
herdr** — the very outcome this trial might trigger. It is scaffolding kept running as a
cross-check, not permanent infrastructure. Do not act on that cleanup while the trial is
running; it would remove the only ground truth you have.

You do not need a full protocol before starting — you do not yet know how herdr behaves.
Start with the rules above, and tighten them as you learn what its failure modes actually look
like. Record what you change.

## 8. Reboot testing

### 8a. The backup — do this BEFORE every reboot

This is the safety net. Two steps, strictly in this order:

1. **Read `~/claude-session-backups/live-sessions-FINAL-20260805T174156.md`** — the artifact
   from the 2026-08-05 exercise, kept as the format model.
2. **Then delete the old folder contents**, so stale files cannot be mistaken for current
   ones. Do this once, before the first new backup — not before every cycle. Later cycles
   accumulate their own timestamped files, which is intended.

The backup must capture enough to rebuild every session by hand if resume fails:

| Column | Source |
|---|---|
| pane | tmux `list-panes -a`, and herdr's own state |
| session id | see below — **cross-check multiple sources** |
| cwd | same entry as the session id |
| topic | first user message in `~/.claude/projects/<slug>/<id>.jsonl` |
| ✎ unsent draft | pane content shows typed-but-unsent text or an open dialog |

Plus a **Resume commands** section of copy-pasteable
`(cd <cwd> && claude --resume <id>)` lines, grouped by tool.

**Sources, and why you need more than one:**
- `~/.tmux/resurrect/assistant-sessions.json` — `sessions[]` with `pane`, `tool`,
  `session_id`, `cwd`, `pid`. **Incomplete**: on 2026-08-29 it held 13 entries while 21 panes
  were running Claude. It also goes stale — it listed a pane whose Claude process had exited.
- `~/.config/herdr/session.json` — herdr's own snapshot; per-pane `cwd` plus
  `agent_session.value` (the Claude session id) when reported. Read defensively; the schema is
  internal (`SNAPSHOT_VERSION = 3`) and may change between releases.
- **Live probe** — walk each pane's process **subtree** (not just direct children; `claude`
  often runs under an intermediate process) to find panes the registries missed.
- `~/.claude/projects/<slug>/*.jsonl` — gives the topic line once you know the session id.

**Mapping a live-probe pane to its session id is the hard part — do not guess it.** The probe
gives you a pane and a PID, not a session id. **cwd cannot bridge that gap**: on 2026-08-29,
21 Claude panes shared only 8 distinct cwds — seven panes were open on `pata-vault` alone. So
"newest `.jsonl` under that project" picks the wrong conversation far more often than not, and
a wrong resume id is indistinguishable from a right one until someone tries it.

Resolve it from the process itself, in this order:
1. `ps -o command= -p <pid>` — a pane started with `claude --resume <id>` carries the id on
   its command line. **This covers under half of them**: measured 2026-08-29, 22 Claude
   processes were 8 with a readable id, 3 truncated, and 10 a bare `claude` — a session
   started fresh never had an id to carry. Cheap, so try it first, but do not expect it to
   resolve the set.
2. Ask the session itself — this is where most ids actually come from. The 2026-08-05 model's
   `probe` rows were built this way, reading each session's own `/status` output. It is
   interactive per pane, so budget for that rather than assuming the script does it unattended.
3. Failing both, capture the pane's visible content and record the pane as **unresolved**
   rather than attaching a guessed id.

Unresolved entries are an expected outcome, not a script bug. What matters is that they are
marked, so a failed resume sends you to the transcript rather than to a wrong conversation.

Because unresolved is an accepted outcome, **the correctness check below passes even if you
skip step 2 entirely** — and skipping it is allowed when you are in a hurry. Just know you are
trading coverage for time: step 1 alone leaves most panes unresolved, and the value of the
backup is roughly the fraction of ids it actually resolves.

**The correctness check**: count panes actually running Claude, and assert the backup has an
entry for every one, each with either a resolved session id or an explicit `unresolved` mark.
If the counts differ, or an entry carries a guessed id, the backup is incomplete — fix it
before rebooting. This check is the whole point; a backup that silently drops sessions, or
lists confident wrong ids, is worse than none, because you will trust it.

No such script exists yet — the 2026-08-05 files were produced ad hoc. Writing it is the
first task of Part 2. Put it in `agent-config/herdr/` (or `agents/scripts/` in nix-config if
it stays tmux-aware), and have it write to `~/claude-session-backups/` with a timestamped name.

### 8b. The reboot test

For each cycle:

1. Run the backup script. Verify the count assertion passed.
2. Note how many agent panes are live in herdr, and how many sessions remain in tmux.
3. **Reboot.** — *This ends the session executing these steps.* Before rebooting, write steps
   1–2's results into §1 and the trial log, so the session that resumes at step 4 (a new one,
   necessarily) knows a cycle is in flight. The reboot itself is the user's action.
4. Start herdr (`hd`). Check: did every agent pane come back, in the right cwd, resumed into
   the right conversation?
5. **Run `tm`** to bring back the tmux side — nothing auto-starts it any more (§5).
6. Record in §9: cycle number, agent panes before, how many resumed correctly, and the cause
   of any failure.

herdr's own docs are explicit that a snapshot alone is not enough: "Snapshot restore does not
preserve running shells, servers, tests, or arbitrary processes. Panes that cannot use a
stronger restore path come back as new shells in their saved directories." Resume depends on
the `SessionStart` integration having reported each session id.

### 8c. Other hard scenarios worth testing

- **herdr server crash / restart** without a reboot: `herdr server stop` then `hd`.
- **A pane that auto-enters tmux.** Per §2 this breaks agent detection outright. Confirm no
  shell startup path does this inside a herdr pane.
- **Notification delivery while the machine is locked or Ghostty is backgrounded** — a
  blocked-agent toast you never see is a false negative in practice.

## 9. Trial log and decision

`agents/docs/herdr-trial-log.md`, dated entries. Keep running totals at the top so a later
session does not have to re-tally the whole file:

```markdown
## Totals
- Blocked-state misses: N
- Blocked-state false alarms: N
- Reboot cycles: N attempted, N at 100% resume
- herdr crashes: N

## YYYY-MM-DD
- Sessions live: N (herdr) / N (tmux)
- Blocked-state events: …            # miss or false alarm, how you noticed, session count
                                      # mark each oracle-backed or eyeball-checked (§7)
- Blocking states deliberately exercised: …   # AskUserQuestion, plan approval, tool prompt
- Reboot cycles: …
- settings.json / config changes: …
- Anything herdr got wrong: …
- Changes to the §7 detection method: …
```

### Decision criteria

Adopt only if all of:

1. **Blocked-state false negatives** — agent waiting, sidebar did not show it. Target:
   **zero** once herdr is carrying a realistic working set. **This is a lower bound, not a
   true count**: a miss is by definition something the sidebar failed to surface, so you only
   catch the ones another signal exposes — which is what §7's `notify.sh` oracle is for.
   Treat any confirmed miss as serious, and note how you found it.
   **The oracle only covers permission prompts and turn endings.** Do not call this criterion
   met unless the log also shows the oracle-blind states of §7 were deliberately exercised and
   eyeball-checked — otherwise "zero" is a narrower claim than it looks.
2. **Blocked-state false positives** — tolerable if rare; note the rate. Nothing actively
   surfaces these, so the count is whatever you happened to notice; say so rather than
   reporting it as a measured rate.
3. **Reboot resume**: at least **2** cycles at a realistic session count, **100%** of agent
   panes resumed into the right conversation and cwd. Schedule the second cycle explicitly —
   one reboot is not enough evidence.
4. **`prefix S` equivalent** rebuilt and comfortable.
5. **No unrecovered crash** of the herdr server.

These are the criteria as understood before using herdr. If the trial reveals a failure mode
none of them capture, add it and say so in the log — do not quietly judge against a different
bar than the one written down.

---

## 10. Risks

1. **Pre-1.0 churn**: irregular releases, config stability not guaranteed. The version moves
   with `flake.lock`, which the nightly Action advances — expect it to change mid-trial. Never
   run `herdr update` (disabled for Nix installs) or set `channel = "preview"`.
2. **Claude state detection is screen-scraped**, unlike OpenCode/Kimi. This is the weakest
   link and criterion 1 exists to measure it.
3. **`settings.json` modification** by the herdr installer — expected to be an in-place
   append that preserves foreign entries (§2), but verify per §6a.
4. **A cache miss on `pkgs.herdr`** turns `just switch` into a multi-minute Rust+Zig build.
5. **No auto-start after reboot** for either tool once `ghosttyTabInitScript` is gone. During
   Part 2 this bites twice per cycle — remember `tm` as well as `hd`.
6. **herdr server crash mid-trial.** Recovery: restart with `hd`; if agents do not come back,
   fall back to `claude --resume <session-id>` by hand — ids are in the §8a backup,
   `~/.claude/projects/<slug>/`, and `~/.tmux/resurrect/assistant-sessions.json`.
   **Conversation history is never lost**; transcripts are files independent of any
   multiplexer. Only process continuity is at risk.
7. **Never let a herdr pane auto-enter tmux.** herdr documents that it then "sees tmux as the
   pane process instead of the agent behind it" — agent detection breaks silently, which
   invalidates the trial's entire premise. `[experimental] allow_nested` defaults to `false`;
   leave it.
8. **Never `brew services start herdr`.** The homebrew-core formula declares
   `keep_alive: always`, so it would run a competing daemon against the nix binary.

---

## 11. Open question for the user — framing

herdr has `herdr --remote <ssh-target>` and manages its own SSH config
(`[remote] manage_ssh_config`, default `true`), so remote attach exists. But the home-server
currently has no `programs.tmux` block at all and is reached by plain `ssh home-server.local`.

If tmux must stay on the home-server regardless of how this trial goes, then the honest
target state is **"herdr for local agent work, tmux still present"** rather than "replace
tmux". That is still a win for the stated goal — the goal is agent visibility, not removing
tmux — but it changes what "success" means and whether the tmux config in `home.nix` ever
actually gets deleted.

**Settle this before judging against §9's criteria** — it changes what "adopt" means. It does
not block Parts 1–2. §1 carries a line for it; when you come to evaluate the criteria and that
line still reads "no", raise it with the user then rather than assuming an answer.

---

## 12. Repo conventions

- **`git fetch` and check against `origin/main` before editing** — the daily Action pushes
  "Upgrade flake" commits most days. Re-check at execution time; do not trust a status
  recorded in this document.
- **New files must be `git add`ed before `just switch`** — nix copies only tracked files;
  untracked files silently deploy nothing.
- **Never run mutating brew commands.** herdr comes from nixpkgs (§4.3).
- **Commit prefix `MBP2023`** for nix-config changes touching only the 2023 MacBook. This
  applies to the `home.nix` edits in §5.
- **Report all warnings** from `just switch` — into the trial log if no one is watching.
- `agents/scripts/test-tmux-resurrect.sh` does **not** cover this work (it runs with
  `-f /dev/null` and never loads the real config). §5 changes only how tmux is attached to,
  not the tmux config itself, so the existing chain is not at risk. If any tmux config is
  touched, use the manual socket-guard recipe in
  `agents/instructions/working-in-this-repo.md`.
