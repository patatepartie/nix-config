# herdr trial log

Running record for the trial specified in `herdr-trial-plan.md`.
Totals first so a later session does not have to re-tally the file.

## Totals

**Trial concluded 2026-09-16: all five decision criteria met.**

- Blocked-state misses: 0 confirmed; settled 2026-09-16, herdr beats `notify.sh` on every axis
- Blocked-state false alarms: 0 noticed
- Reboot cycles: 2 attempted, 2 at 100% resume
- herdr crashes: 0

## 2026-09-16 — reboot cycle 2, 100% resume

Trigger was memory exhaustion rather than a planned test: 10d 22h uptime, 21.6 GB of 22.5 GB
swap consumed, `kernel_task` and `WindowServer` each ~22% CPU as a consequence. A harder
starting state than cycle 1, which was a clean planned restart.

Backup: `~/claude-session-backups/herdr-sessions-20260916T085016.md`, exit 0.

| | before | after |
|---|---|---|
| workspaces | 25 | 25 |
| tabs | 85 | 85 |
| panes | 108 | 108 |
| agent sessions | 23 | 23 |
| unresolved | 0 | 0 |
| not-in-snapshot | 0 | 0 |
| sessions back in the *same* pane | — | 23 / 23 |

**The whole backup body is byte-identical before and after**, bar herdr's own snapshot
timestamp — not just the totals, but every workspace's tab and pane counts, every session
id, and every id↔cwd↔topic triple in its original order. No session resumed into the wrong
conversation or the wrong directory, and no pane came back as a bare shell.

Restore needed no intervention: Ghostty launched herdr directly, so cycle 1's manual `hd` was
not repeated. This confirms the fix made after that cycle.

Workspace count is 25 against cycle 1's 23; `agent-config` and `personal-skills` are the two
added since. Pane count is unchanged at 108.

Verified genuine rather than a server that never died: system uptime 7 min, herdr process age
5 min 55 s, 23 live `claude` processes. Swap fell from 21.6 GB used to 6.7 GB.

All 23 ids had also been cross-checked against `~/.claude/projects/` before the reboot — every
transcript existed on disk, so the backup's resume lines were usable independently of herdr.
That fallback was not needed.

**Criterion 3 (reboot resilience) is met** — two cycles, both at 100%, the second from an
unplanned memory-exhausted state.

### Criterion 1 — blocked states, settled

**The user is the oracle, and that is a stronger instrument than §7's, not a weaker one.**
§7 built its method around `notify.sh` because it assumed the human could not tell whether a
notification was owed. That assumption was wrong: having run both chains, the user can compare
them directly. Do not re-open this on the grounds that the independent oracle is gone.

Against `notify.sh`, herdr is better on every axis the user cares about:

- every notification that was needed arrived;
- **more** of them — herdr covers states `notify.sh` never hooked, which is exactly the §7
  blind spot (`AskUserQuestion`, plan-mode approval, interactive tool prompts);
- **distinguishable by sound and colour**, so what Claude is asking is clear before switching
  to the pane — `notify.sh` was undifferentiated;
- **no double notifications**, which `notify.sh` produced.

"So far" rather than a closed count, as any lower bound must be. That is what the criterion
asks for; it calls itself a lower bound in its own text.

**All five decision criteria are now met.** 1 by direct comparison against the `notify.sh` era,
2 as a lower bound on what the user happened to notice, 3 by the two reboot cycles above, 4 by
`new-workspace.sh` and `pick-agent.sh` (2026-09-06), 5 with zero server crashes since
2026-08-29.

**The trial is over. herdr is adopted.** Nothing here is pending re-measurement.

## 2026-09-06 — navigation filled in, tmux gone from the 2018 MacBook

**The default bindings are not enough to work without a mouse.** `previous_agent`,
`next_agent`, `previous_workspace`, `next_workspace` and `last_pane` are all unset by default,
and `prefix+w` lists workspaces without fuzzy matching. Bound comma/period pairs for agent and
workspace cycling — note `bracketleft`/`bracketright` are rejected as key names.

**Two gaps needed scripts, both bound as popups** (in `agent-config/herdr/`):

- `prefix+a` → `pick-agent.sh`. herdr has no agent search at all: `prefix+w` covers workspaces
  only, `prefix+g` cannot target a pane *within* a workspace, and the agent sidebar has no
  filter. The picker fuzzy-matches on workspace name plus conversation topic, which is the only
  thing distinguishing panes — every Claude pane is otherwise just "claude".
- `prefix+shift+s` → `new-workspace.sh`, the old tmux `prefix S`. herdr's own
  `prefix+shift+n` creates a workspace in the *current* cwd without asking for a directory,
  because `prompt_new_workspace_name` is false and `new_cwd` is "follow". The script also has
  to resolve label→id to focus an existing workspace, since `workspace focus` takes an id;
  the tmux binding got that for free.

Both confirmed working in use. Criterion 4 (`prefix S` rebuilt and comfortable) is met.

**tmux removed from the 2018 MacBook.** herdr cannot replace it there: it needs `zig_0_15` to
build `libghostty-vt`, and zig has no `x86_64-darwin` support, so `pkgs.herdr` does not
evaluate on that host. Nixpkgs warns that 26.05 is the last release supporting x86_64-darwin at
all, so this will not change. The machine only runs `gl && just switch` and the occasional
agent, both fine in a plain Ghostty tab.

**notify.sh and terminal-notifier removed.** herdr's toast and sound cover the same ground and
notify.sh was noisier — it fired on subagent completions. This also retires the trial's
independent oracle (§7), so blocked-state misses now have no cross-check at all; see the
caveat below, which this makes permanent rather than temporary.

## 2026-09-05 — reboot cycle 1, and migration complete

**Sessions live:** 23 workspaces / 108 panes / 21 Claude sessions (herdr), 0 (tmux).

**Reboot cycle 1 — 100% resume.** A system update plus restart, which is a slightly harder
test than the plan asked for. Verified by diffing the live state against a backup taken
immediately beforehand (since deleted along with the rest of the tmux-era backups):

| | before | after |
|---|---|---|
| workspaces | 23 | 23 |
| panes | 108 | 108 |
| agent sessions | 21 | 21 |
| sessions back in the *same* pane | — | 21 / 21 |

Tab counts, tab labels and pane counts matched for every workspace. Nothing was lost, moved,
or resumed into the wrong conversation.

`hd` had to be run by hand — expected, since §5 removed Ghostty's `command`. Ghostty now
launches herdr directly (see below), so cycle 2 should come back without intervention.

**Migration finished.** All 23 tmux sessions were recreated as herdr workspaces between
08-29 and 09-04 and the tmux sessions then terminated. Session ids came from
`assistant-sessions.json` where present, and otherwise from matching live pane content against
transcript content. Ordering transcripts by mtime was tried and would have mismatched panes —
the most recently modified transcript was not the one the pane held.

**tmux save/restore chain removed.** It was recreating sessions that had deliberately been
closed after migration: killing the last session stops the server, and starting a new one fired
the restore trigger against a snapshot that still held everything. `~/.tmux/resurrect/` (11 MB,
709 files) was deleted after this reboot validated herdr's restore.

**Ghostty now launches herdr.** `command = "${pkgs.herdr}/bin/herdr --session main"`, the
create-or-attach form, so tabs converge on one server. Note this removes the plain-shell escape
hatch: if herdr ever fails to start, every new tab fails with it.

### Config changes

- `agent_panel_sort = "priority"` — the attention queue. Needed because a finished reply decays
  to `idle` (see below), so ordering is the only thing separating "just replied" from "idle
  since yesterday".
- `[ui.sidebar.agents] rows` — replaced the default second row (`agent`, literally the string
  "claude" for every pane) with `terminal_title_stripped`, so sessions are told apart by topic.
- `[theme.custom] sidebar_bg` lifted to `#2a2b3c`. herdr has no sidebar-border setting; regions
  are separated by background alone, and Mocha ships sidebar and panel ~2% apart in luminance.
  Swapping between herdr's built-in dark themes does not help — they are all near-black.

### What herdr got wrong, or cannot do

- **No "just replied" state that persists.** The states are `idle`, `working`, `blocked`,
  `done`, `unknown`. `done` is reachable for Claude — observed after prompting a session — but
  it decays back to `idle` within about a minute. A session that replied a moment ago is then
  indistinguishable from one abandoned yesterday. §9b records the possible fix.
- **Directional focus does not wrap.** From a bottom pane, `prefix+j` does nothing where tmux
  would loop to the top. No setting for it.
- **No fuzzy directory picker for new workspaces.** `prefix+shift+n` prompts for a name, not a
  directory, so it does not replace the old `prefix S`. `new-workspace.sh` is still unwritten.

### Caveat on the miss count — superseded 2026-09-16

*Resolved by the 2026-09-16 entry, which calls criterion 1 met on eyeball-checked use. Kept
because the reasoning about what the zero does and does not cover still applies.*

The zero above is weak evidence, not a clean result. `notify.sh` only covers permission prompts
and turn endings, and the oracle-blind states of §7 — `AskUserQuestion`, plan-mode approval,
interactive tool prompts — have **not** been deliberately exercised yet. Criterion 1 cannot be
called met until they have been. Two blocked states were observed correctly during the
migration (both beair panes at a folder-trust prompt), which is encouraging but incidental
rather than a designed test.
