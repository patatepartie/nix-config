# Version-controlling the global Claude config

Written 2026-08-26. Executed by a separate session — this document is the spec and should be
followed without needing the conversation that produced it.

Goal: move the hand-authored parts of `~/.claude` into a git repo at `~/Tech/agent-config`,
symlinked back into place, so the global Claude Code config is versioned, reviewable, and
reinstallable on a new machine. Machine-generated state stays in `~/.claude` and is never
versioned.

This is worth doing on its own merits. It was prompted by the herdr trial
(`agents/docs/herdr-trial-plan.md`), because `herdr integration install claude` edits
`~/.claude/settings.json` and versioning it first makes that edit a reviewable diff — but the
work stands alone and that trial does not depend on it. See "Relationship to the herdr trial"
below.

Two steps, in order:

| Step | What |
|---|---|
| **§2** | Create the repo, move content in, replace originals with symlinks |
| **§3** | Move `personal-skills` in with its history via `git subtree` |

**If you are a fresh session picking this up**, start at §1 — it says where to begin. Treat it
as a claim to spot-check, not gospel: if it says §2 is done, confirm
`ls -l ~/.claude/settings.json` really is a symlink before building on that.
**Before you stop, update §1** so the next session knows where it left off. That is the only
handoff mechanism; nothing else records progress.

### A note on numbers in this document

Line numbers, file sizes and counts drift. Anything of that kind here is a **navigation hint
as of the date given, not a fact to rely on** — grep for the named anchor before editing, and
re-measure counts at execution time rather than quoting them from this file.

### Relationship to the herdr trial

The herdr trial wants this done first, so that `herdr integration install claude`'s edit to
`settings.json` lands as a diff on a committed baseline rather than on an unversioned file.

That is a convenience, not a hard dependency. **If this work stalls or you decide against it,
the herdr trial must not wait** — copying `~/.claude/settings.json` somewhere before running
the installer, and diffing against that copy afterwards, gives the same safety property.

Worth knowing while working here: the installer appends a single `SessionStart` hook and
preserves foreign entries (verified against herdr's source and its unit tests), so the
existing `tmux-resurrect-hooks` entries in `settings.json` are not at risk from it.

---

## 1. State of play — update this before ending a session

This is a checklist, not a glossary. Every term below is explained in the section it belongs
to; if something here means nothing to you yet, go to the section named beside it.

**Last updated:** 2026-08-29.

| Step | Status | Notes |
|---|---|---|
| §2 — agent-config repo + symlinks | **done** | All 7 paths symlinked. Baseline commit "Import Claude global config from ~/.claude" on branch `master`. |
| §3 — personal-skills subtree | **done, verified** | 34 commits of history imported. All 9 skills symlinked into `agent-config/skills/`; `/skills` and `/context` in a fresh session list all 9 as User-source, and the three `instructions/*.md` load as memory files through the symlink. |

Statuses are coarse, and §2's step 6 swaps seven paths one at a time. **If you stop part-way
through it, say exactly which paths are already symlinked in that row's Notes** — otherwise
the next session reads "not started" and may re-run the copy steps against already-moved
content.

**Findings and decisions** (fill in as you go):

- Verification gate (§2): **all four pass.** All 7 paths are symlinks, `settings.json` resolves to `-rw-------` through the link, `bash-guard.sh` fired its escaped-whitespace denial from the symlinked copy, and the user confirmed the statusline renders in a fresh session (item 3 confirmed, not substituted).
- `install.sh` written, idempotent, and **tested** by re-running it: **yes** — 15 assertions against a throwaway `HOME`, covering clean install, no-op re-run, refusal to clobber a real file *and* a real directory, and `--force`.
- `personal-skills` retired: **yes — `~/Tech/Bespoke/personal-skills` deleted 2026-08-29.** Before removal: `diff -r` against `agent-config/skills/` was byte-identical (excluding `.git` and the dropped `install.sh`), the repo was clean, and all 9 skills were in the pushed commit. All 9 symlinks re-verified as resolving afterwards. `agent-sidecar` untouched.
- Remote: **added 2026-08-29** — private, `git@github.com:patatepartie/agent-config.git`, `master` tracks `origin/master`, all 36 commits pushed. This supersedes decision 5.
- **Open question for the user, if any:** **§3 linked 9 skills where 7 were linked before.** `install.sh` links every directory containing a `SKILL.md`, so `refactoring-claude-md` and `ubiquitous-language` — noted in §3 as previously unlinked — are now active, and both registered live in the session that ran it.
  If either was deliberately held back, remove the symlink from `~/.claude/skills/` or move the directory out of `skills/`; the install script will otherwise re-link it on every run.

**Sandbox note (learned 2026-08-29).** The Bash write allowlist covers neither `~/` nor `~/Tech`, so every write to `~/Tech/agent-config` needs `dangerouslyDisableSandbox: true` — §3's `git subtree add` included.
Two consequences for §2 as written: the step 0 backup to `~/.claude.bak-pre-agent-config` **cannot be created**, and the step 6 swap script was refused by the auto-mode classifier and had to be run by the user.
The step 0 backup turns out to be unnecessary rather than merely awkward: once the §2 baseline is committed, every moved item exists both in git and in the `agent-config` working tree, so rollback is `rm` the symlink and `cp` from the repo.
The whole-`~/.claude` copy the step describes would additionally cover unversioned machine state (`projects/`, `history.jsonl`) — but no procedure in this document ever restores those, as step 0's own comment says.
The real uncovered risk was losing `~/Tech/agent-config` itself, which takes git and the working copy together; that is now addressed by the private remote (see decision 5), not by a local backup.

---

## Decisions already made — do not relitigate

1. **One `agent-config` repo at `~/Tech/agent-config`**, covering personal and work use.
2. **Symlink style**: directory symlinks for `hooks/`, `instructions/`, `scripts/`,
   `commands/`, `agents/`; file symlinks for `CLAUDE.md` and `settings.json`.
3. **`skills/` at repo root**, not under `claude/` — skills are portable across harnesses.
4. **Move `personal-skills` with history** via `git subtree`.
5. ~~**No git remote for now.**~~ **Superseded 2026-08-29** — the repo now has a private remote at `git@github.com:patatepartie/agent-config.git`, and `master` tracks `origin/master`.
   The original reasoning (remotes complicate workflows; local-only matches `personal-skills` and `agent-sidecar`) was weakened once §3 moved the skills in: a single `rm -rf ~/Tech/agent-config` would otherwise take the global config, every skill, and all their history at once.

---

## 2. Create `~/Tech/agent-config`

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
└── skills/            (added in §3)
```

### What moves

Whole directories move, contents and all — do not curate them. The examples below are what
each held on 2026-08-26; expect additions.

- `~/.claude/CLAUDE.md` (mode 644)
- `~/.claude/settings.json` (**mode 600 — preserve this**)
- `~/.claude/hooks/` — guard and notification scripts, plus notification icons
- `~/.claude/instructions/` — the `*.md` files `CLAUDE.md` pulls in with `@instructions/…`
- `~/.claude/scripts/` — `statusline.sh` and anything alongside it
- `~/.claude/commands/`, `~/.claude/agents/` — empty at the time of writing; create them in
  the repo for future use, and move any contents if they are no longer empty

### What must NOT move

Machine state: `projects/`, `history.jsonl`, `sessions/`, `cache/`, `file-history/`,
`shell-snapshots/`, `session-env/`, `paste-cache/`, `stats-cache.json`, `telemetry/`,
`plugins/`, `backups/`, `jobs/`, `tasks/`, `debug/`, `daemon/`, `daemon.log`, `security/`,
`ide/`, `plans/`, `.cc-writes/`, `.last-cleanup`, `gsd-file-manifest.json`,
`security_warnings_state_*.json`, `.anthropic/`.

Note: `~/.claude/.credentials.json` does **not** exist — credentials live in the macOS
Keychain (service "Claude Code-credentials"). Nothing to protect there.

`~/.claude/settings.json.bak` was a stale hand-made backup (3.9k, dated 20 Mar 2026), never versioned.
**Deleted 2026-08-29** once the §2 gate had passed and the live `settings.json` was committed and pushed.

Already managed, leave alone:
- `~/.claude/skills/` — per-skill symlinks (re-pointed in §3)
- `~/.claude/tmux-resurrect-hooks` — symlink into the nix store, owned by `home.nix:153–154`.
  **Do not bring into `agent-config`**; `settings.json` references it by the stable
  `~/.claude/...` path and a moving store path would 404 after a GC.

### Why symlinks are safe

Every **hook and script command path** in `settings.json` is `~/.claude/…`-relative — no
absolute nix-store paths. Redirecting `~/.claude/hooks` to the repo is therefore invisible to
Claude Code.

Re-confirm this rather than trusting it, since hooks get added over time — the check is that
no command path escapes `~/.claude/`:

```sh
grep -oE '"command":[^"]*"[^"]*"' ~/.claude/settings.json
```

As of 2026-08-26 that was the guard hooks, `scripts/statusline.sh`, two
`tmux-resurrect-hooks/` entries, and one inline `python3 -c` command that references no file
at all. If anything now points outside `~/.claude/` — an absolute path into the nix store,
say — that one needs thinking about before you symlink.

(`settings.json` does also contain absolute paths in its `sandbox` allowlist block —
`~/.azure`, `/tmp`, `/nix/var/nix/daemon-socket/socket`, etc. Those are not command paths and
are unaffected by the symlinking.)

### Procedure

**Before starting, check where you are.** These commands are destructive and the block is
only safe to run from a clean start:

```sh
ls -ld ~/Tech/agent-config 2>/dev/null          # exists? → a previous run got partway
ls -l  ~/.claude/settings.json                  # already a symlink? → §2 already done
```

- **Neither exists** — clean start. Proceed from step 0.
- If `~/.claude/settings.json` is already a symlink into `agent-config`, §2 is done — skip to
  the verification gate.
- If `~/Tech/agent-config` exists but `~/.claude/settings.json` is still a regular file, the
  previous run stopped mid-way. Do **not** re-run from the top: the `cp -a` steps read from
  `~/.claude`, and if the originals were already removed, they would fail or clobber the repo
  copy. Instead, compare `~/Tech/agent-config/claude/` against `~/.claude/` by hand, then
  resume at whichever step is genuinely next.
- **If `~/.claude/settings.json` is missing entirely**, a previous run died between step 6's
  `rm` and its matching `ln -s`. Claude Code is broken for every session right now, so fix it
  first: if the file exists in `~/Tech/agent-config/claude/`, just create the symlink. If it
  exists in **neither** place, restore from `~/.claude.bak-pre-agent-config` (step 0's backup)
  or from the repo's git history before doing anything else.

```sh
# 0. Back up. Delete only after the verification gate passes.
#    Note: this copies all of ~/.claude including projects/ and history.jsonl. Those are
#    never restored from it by any procedure here — only the moved items are — so an
#    internally-inconsistent copy of them is acceptable.
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

# 4. Confirm the copy is complete BEFORE deleting anything.
diff -r ~/.claude/hooks claude/hooks && echo "hooks OK"
diff -r ~/.claude/instructions claude/instructions && echo "instructions OK"
diff -r ~/.claude/scripts claude/scripts && echo "scripts OK"

# 5. Commit the baseline BEFORE deleting the originals. §3 requires a commit to exist.
#    (.gitkeep so the empty dirs survive; git does not track empty directories.)
touch claude/commands/.gitkeep claude/agents/.gitkeep
git add -A
git commit -m "Import Claude global config from ~/.claude"

# 6. Replace originals with symlinks.
rm    ~/.claude/CLAUDE.md ~/.claude/settings.json
rm -rf ~/.claude/hooks ~/.claude/instructions ~/.claude/scripts
rmdir ~/.claude/commands ~/.claude/agents        # empty at writing; fails loudly if not.
                                                 # If it fails, copy the contents into the
                                                 # repo first, then remove and re-run.
ln -s ~/Tech/agent-config/claude/CLAUDE.md     ~/.claude/CLAUDE.md
ln -s ~/Tech/agent-config/claude/settings.json ~/.claude/settings.json
ln -s ~/Tech/agent-config/claude/hooks         ~/.claude/hooks
ln -s ~/Tech/agent-config/claude/instructions  ~/.claude/instructions
ln -s ~/Tech/agent-config/claude/scripts       ~/.claude/scripts
ln -s ~/Tech/agent-config/claude/commands      ~/.claude/commands
ln -s ~/Tech/agent-config/claude/agents        ~/.claude/agents
```

Step 6 deletes and recreates paths that a running Claude Code session reads. Run it in one
go rather than leaving it half-done; if interrupted between the `rm` and the matching `ln -s`,
finish the remaining `ln -s` lines by hand rather than restarting the block.

`.gitignore` — the repo holds only hand-authored content, so this is minimal:
```
.DS_Store
*.log
```

`README.md` — short: what the repo is (global agent/Claude config, symlinked into
`~/.claude`), how to install on a new machine (`./install.sh`), and the rule that generated
state stays in `~/.claude` and is never added here.

`install.sh` — **written once, here in §2.** (§3 does not write a second one; it only deletes
the redundant copy that `git subtree add` drags in.) Include the skills loop now even though
`skills/` does not exist yet — it simply matches nothing until §3 runs.

**Read `~/Tech/Bespoke/personal-skills/install.sh` first**; it is the model. (That file is gone — `personal-skills` was deleted on 2026-08-29 — but it survives in `agent-config`'s history, before the commit "Drop the skills subtree's install.sh in favour of the top-level one".) It resolves
`SCRIPT_DIR`, `mkdir -p`s the target, and for each subdirectory containing a `SKILL.md`
removes any existing symlink or directory and `ln -s`. Extend it to two loops: one linking a
**hardcoded list** of `claude/<item>` entries (`CLAUDE.md`, `settings.json`, `hooks`,
`instructions`, `scripts`, `commands`, `agents`) to `~/.claude/<item>` — hardcoded rather than
globbed, so a stray `.DS_Store` is never linked — and one linking each `skills/<dir>`
containing a `SKILL.md` to `~/.claude/skills/<name>`.

**Do not copy its clobber behaviour.** The existing script does `rm -rf "$target"` on a real
directory without asking. The new one must be idempotent *and* refuse to clobber a real file
or directory that is not a symlink unless given `--force`, so a re-run on a fresh machine
cannot silently destroy existing config.

**Both properties need testing, not just asserting** — this script exists to run on a machine
whose `~/.claude` you care about, and "looks idempotent" is not evidence:
- *Idempotent*: run it twice in a row. The second run must change nothing and exit cleanly.
- *Refuses to clobber*: point it at a scratch `HOME` containing a real (non-symlink) file at
  one of the target paths, and confirm it refuses without `--force` and leaves that file
  untouched. Use a throwaway directory — never test this against your real `~/.claude`.

### Verification gate — all four must pass before §3

1. `ls -la ~/.claude/settings.json ~/.claude/hooks` — both show as symlinks into
   `~/Tech/agent-config/`.
2. `stat -f '%Sp' ~/.claude/settings.json` resolves through the link to `-rw-------`.
3. **(needs the user — an agent cannot do this to itself.)** Start a **fresh** Claude Code
   session and confirm the statusline renders, proving `statusLine.command` →
   `~/.claude/scripts/statusline.sh` resolves through the symlink. An agent session should ask
   the user to do this. Running `~/.claude/scripts/statusline.sh` directly is *not* a
   substitute — it proves the symlink resolves, not that Claude Code invokes it. If you
   substitute, say so and mark the gate partially verified in §1 rather than "passed".
4. Confirm a `PreToolUse` hook still fires. **Read `~/Tech/agent-config/claude/hooks/
   bash-guard.sh` first** to find a pattern it actually rejects, then issue a matching Bash
   call and confirm the block. Do not guess a test command — a non-triggering guess looks
   identical to a broken hook.

Record the result in §1 before stopping. If any fail: `rm` the symlinks and restore with
`cp -a ~/Tech/agent-config/claude/<item> ~/.claude/`, then diagnose.
(The original text restored from `~/.claude.bak-pre-agent-config`; that backup cannot be created — see the sandbox note in §1 — and the repo copy serves the same purpose.)

---

## 3. Move `personal-skills` into `agent-config/skills`

`~/Tech/Bespoke/personal-skills` is a local-only git repo (**no remote**, branch **`master`**)
holding one directory per skill plus `install.sh` and `.gitignore`. It is actively used, so
the commit count and skill list move — check both at execution time. Note that not every
skill directory is symlinked into `~/.claude/skills/`; as of 2026-08-26, two were not
(`refactoring-claude-md`, `ubiquitous-language`). Re-derive the set rather than assuming:
compare `ls ~/Tech/Bespoke/personal-skills/` against `ls ~/.claude/skills/`.

**Prerequisite**: §2 must have produced at least one commit — `git subtree add` merges into
HEAD and fails on an unborn branch.

**Check first**: if `~/Tech/agent-config/skills/` already exists, this step has run. Do not
re-run `git subtree add` — it fails when the prefix already exists.

```sh
cd ~/Tech/agent-config
# Direct-path form: the repository argument may be a filesystem path.
# The trailing `master` is personal-skills' branch, not agent-config's — the two are
# independent, and `git init` here produces `master` as well.
git subtree add --prefix=skills /Users/cyrilledru/Tech/Bespoke/personal-skills master
```

Then:
1. Re-point the 7 existing symlinks in `~/.claude/skills/` to
   `~/Tech/agent-config/skills/<name>` (or just run the new `install.sh`).
2. Delete `skills/install.sh` — the copy the subtree import brought in. The top-level
   `install.sh` written in §2 already supersedes it; only merge anything genuinely unique to
   the subtree's version. A future `git subtree pull` may conflict on that file if upstream
   changes it — resolve by keeping the top-level version.
3. Update the **3** references to `~/Tech/Bespoke/personal-skills/` in
   `agent-config/claude/instructions/skills.md` (lines 5, 7, 13) to
   `~/Tech/agent-config/skills/`. **`~/.claude/CLAUDE.md` contains no such reference** —
   verified, nothing to change there.
4. **Leave `~/Tech/Bespoke/personal-skills` in place, untouched**, until symlinks are
   verified. Retire it in a later commit.
   **Done 2026-08-29** — verified via `/skills` and `/context`, then deleted. See §1.

Verify: `/skills` in a fresh session lists the same skills as before. Record in §1.
(`/skills` is the command that lists skills by source; `/help` lists commands and does not show them. `/context` also shows loaded skills.)

**Rollback note.** Once this step has run, §2 is no longer independently revertible: the
skill symlinks in `~/.claude/skills/` point into `~/Tech/agent-config/skills/`, so deleting
that repo dangles them.

The original advice here — re-run `personal-skills/install.sh` to re-point the symlinks before removing `agent-config` — **no longer applies**, because `personal-skills` was deleted on 2026-08-29.
`agent-config` is now the only copy on disk, and rollback means restoring from it rather than falling back to a second repo: clone the private remote (`git@github.com:patatepartie/agent-config.git`), then either run its `install.sh` or copy `claude/` and `skills/` back into `~/.claude` as real files.

**Note**: `~/Tech/Bespoke/agent-sidecar` is a different thing — per-work-repo content keyed
by Bespoke repo name, also remote-less. Out of scope; do not touch.

---

## Repo conventions

This document lives in `nix-config`, but the work it describes happens in
`~/Tech/agent-config` and `~/Tech/Bespoke/personal-skills` — **separate repos with their own
conventions**. The `MBP2023` commit prefix and other `nix-config` rules do not apply to commits
made there.

Applies here regardless:

- **`git fetch` and check against `origin/main` before editing this document** — the daily
  Action pushes "Upgrade flake" commits most days.
- **Never commit machine-generated state** into `agent-config`. If in doubt, check it against
  the "What must NOT move" list in §2.
