# herdr trial log

Running record for the trial specified in `herdr-trial-plan.md`.
Totals first so a later session does not have to re-tally the file.

## Totals

- Blocked-state misses: 0 confirmed — but see the caveat under 2026-09-05
- Blocked-state false alarms: 0 noticed
- Reboot cycles: 1 attempted, 1 at 100% resume
- herdr crashes: 0

## 2026-09-05 — reboot cycle 1, and migration complete

**Sessions live:** 23 workspaces / 108 panes / 21 Claude sessions (herdr), 0 (tmux).

**Reboot cycle 1 — 100% resume.** A system update plus restart, which is a slightly harder
test than the plan asked for. Verified against
`~/claude-session-backups/herdr-sessions-20260905T094347.md`:

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

### Caveat on the miss count

The zero above is weak evidence, not a clean result. `notify.sh` only covers permission prompts
and turn endings, and the oracle-blind states of §7 — `AskUserQuestion`, plan-mode approval,
interactive tool prompts — have **not** been deliberately exercised yet. Criterion 1 cannot be
called met until they have been. Two blocked states were observed correctly during the
migration (both beair panes at a folder-trust prompt), which is encouraging but incidental
rather than a designed test.
