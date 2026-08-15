# MBP auto-update killed by its own activation — diagnosis and plan

**Status:** diagnosed 2026-08-14, implemented and verified on the 2023 MBP
2026-08-15. Applied to the 2018 MBP in the same commit but **not yet verified
there**.

> **On the 2018 MBP?** Go straight to "If you are the 2018 MBP session, start
> here" under "How to test". Your task is verification only — the fix is already
> committed. Do not run Step 0, and do not re-plan the fix.
**Affects:** both MacBook Pros (`hosts/2023-macbook-pro/modules/auto-update.nix`,
`hosts/2018-macbook-pro/modules/auto-update.nix` — same script, same bug).
**Symptom the user sees:** none. That is the whole problem.

## Symptom

`/var/log/nix-auto-update.log` shows the daily run starting, then ending abruptly at:

```
reloading service org.nixos.nix-auto-update
```

with no `Update complete`. A healthy run continues well past that line into the
Homebrew phase (`brew bundle`) and home-manager activation before logging
`Update complete`.

Confirmed occurrences (2023 MBP): 2026-03-24, 04-25, 07-12, 07-25, 08-02, 08-14.
Roughly monthly, not daily — see "Why it is intermittent".

Two things make this invisible:

- `sudo launchctl list | grep nix-auto-update` reports last exit status **0**.
- No Telegram alert fires, even though `telegram.env` exists and the notify path
  works (proven on the home server, which *did* alert on 2026-08-14).

## Root cause

nix-darwin's activation reloads any launchd service whose plist changed.
`org.nixos.nix-auto-update` is itself such a service, and the running update
script **is** that job's process. Activation therefore kills the script that
invoked it.

From `nix-darwin/modules/system/launchd.nix:18-32` (verified in the pinned input,
store path resolvable via
`nix eval --impure --raw --expr '(builtins.getFlake (toString ./.)).inputs.nix-darwin.outPath'`):

```sh
launchdActivation = basedir: target: ''
  if ! diff '${cfg.build.launchd}/Library/${basedir}/${target}' '/Library/${basedir}/${target}' &> /dev/null; then
    if test -f '/Library/${basedir}/${target}'; then
      echo "reloading service $(basename ${target} .plist)" >&2
      launchctl unload '/Library/${basedir}/${target}' || true     # <-- kills the running script
    ...
    cp -f ...
    launchctl load -w '/Library/${basedir}/${target}'              # <-- new plist installed here
  fi
'';
```

The `echo` on that line is the exact last line in the truncated logs, so the kill
is `launchctl unload` on the next line.

Why the two misleading signals:

- **exit status 0** — `man launchctl` notes `load`/`unload` are legacy subcommands
  that "always return 0 except for usage errors". launchd records the
  unload-stop as a normal stop.
- **no notification** — the script is killed by a signal. The script only has a
  `trap ... ERR`, which does not fire on signal delivery, so no handler runs
  either way. If the signal is SIGKILL it is additionally *impossible* to catch
  (kernel-delivered, never seen by the process; POSIX forbids trapping it).
  Strictly, the evidence (truncated log, exit status 0) is equally consistent
  with an untrapped SIGTERM — `launchctl unload` sends SIGTERM first and
  escalates. The distinction does not change the fix: either way no in-process
  handler runs, so notification must come from outside the dying process, and
  the fix is to stop the kill happening at all.

## Scope

Self-contained. This doc concerns the **two MacBooks only** and needs no context
from any other plan. (The home server has an unrelated auto-update problem with a
different cause and fix; nothing here depends on it. The server's notify path
works precisely because its failures are normal non-zero exits rather than
SIGKILL.)

### Why it is intermittent

The plist embeds the store path of `autoUpdateScript`, a `writeShellScript`
derivation. Any change that alters that derivation's closure changes the plist
and triggers the reload — not only edits to `auto-update.nix`. That is why it
fires irregularly (~monthly) rather than every day.

### What survives, what does not

The system-level switch completes before activation reaches the launchd step, so
the Nix generation *does* land (`/run/current-system` matched the newly built
`darwin-system-...` on 2026-08-14). What is lost is everything after the kill:

- the **Homebrew phase** (`brew bundle`) — zero Homebrew lines in a truncated run
- home-manager activation

This is why a manual `just switch` afterwards appears to "update brew packages":
it is finishing work the auto-update silently skipped.

## Rejected fix — do not re-propose

`launchd.daemons.nix-auto-update.serviceConfig.AbandonProcessGroup = true;`

The option is real and nix-darwin accepts it (`modules/launchd/launchd.nix`,
typed `nullOr bool`), **but it does not do what is needed.** From
`man launchd.plist`, verbatim:

> When a job dies, launchd kills any remaining processes with the same process
> group ID as the job. Setting this key to true disables that behavior.

It governs cleanup of orphaned *children* after the job dies. It does not affect
whether launchd terminates the job's own process during `unload`. It would not
prevent this failure. (Proposed and rejected on 2026-08-14 after checking the
man page and nix-darwin source.)

## Plan A — stop the kill (the actual fix)

Make the long-running work not be the launchd-tracked process, so `unload` has
nothing to kill.

Shape:

1. The launchd daemon becomes a thin launcher that returns immediately.
2. It detaches the real update+rebuild logic into its own session/process group,
   **then exits promptly**.
3. **The detached script must run from a stable path outside the Nix store**
   (e.g. `/var/lib/nix-auto-update/run-update.sh`, copied into place by the
   launcher or an activation script). A store-path script changes identity on
   every rebuild, which is the very thing that makes this fire.

### Which part is load-bearing — read this before implementing

**The launcher exiting quickly is what actually defeats `unload`.** By the time
activation reloads the job, launchd's tracked process is already gone, so there
is nothing for it to kill. The detach (`setsid`/`nohup`) is a *secondary*
protection against process-group cleanup (`killpg`), not the primary mechanism.

The failure mode to avoid: wrapping the whole script in `setsid` but keeping the
launchd-tracked process alive waiting on it. That still gets killed. **Do not
`wait` on the detached child.**

Practical notes:

- **`setsid` is not present on macOS base** (verified: no `setsid` on PATH, no
  man page). Use `nohup` (`/usr/bin/nohup`, present), a `perl -e 'setsid'`
  wrapper, or nixpkgs `util-linux`. Whichever is chosen, verify the resulting
  process is genuinely in a different process group (see test step 3).
- **Logging.** The plist sets `StandardOutPath`/`StandardErrorPath` to
  `/var/log/nix-auto-update.log`. Once the work is detached from the launchd job,
  it no longer inherits those. The detached script must redirect its own
  stdout/stderr to that file explicitly, or **the log silently goes empty** —
  which would destroy the only evidence trail this bug has. Append, don't
  truncate.
- **`RunAtLoad` is not set** in `auto-update.nix` (default `false` per
  `man launchd.plist`), so activation's `launchctl load -w` will not itself
  start a run. This was previously an open question; it is settled — no
  double-start from that path.

Property to preserve and verify: activation still writes and loads the **new**
plist (`launchctl load -w`, line 30 above), so the *next* scheduled run picks up
the latest config while the *current* run completes. Both, not either/or.

Once the script survives, a genuine failure reaches the existing
`notify_failure` path and alerts **the same morning**. That is the user's
stated requirement (plan A = immediate notification).

### Open questions — all resolved during implementation (2026-08-15)

- **Detach mechanism.** A perl helper: `fork()`, then `setsid()` in the child,
  then `exec`. Two details are load-bearing and both were found the hard way.
  - **`fork()` before `setsid()` is mandatory.** `setsid(2)` fails when the
    caller is already a process group leader, which the launchd-spawned job is.
    Forking first guarantees the child is not a leader, so its `setsid` always
    succeeds. Without the fork the child silently stays in the job's group.
  - **The parent must block until the child has detached.** launchd tears the
    job's process group down within ~35ms of the job going inactive (measured
    in `log show`: spawn at `16:18:01.992`, `service inactive` at
    `16:18:02.027`). A child that has not yet called `setsid` at that moment is
    killed with it. The helper uses a pipe: the child writes one line after
    `setsid`, the parent blocks reading it, then exits. Do not background the
    helper with `&` — that reintroduces the race.

  Symptom when this is wrong: the launcher exits 0, `run-update.sh` is installed,
  and **nothing else happens** — no log output, no marker file. It looks exactly
  like a crashed launcher.
- **Where to copy the script.** The launcher `install`s it to
  `/var/lib/nix-auto-update/run-update.sh` on every run: simple, self-healing,
  and it avoids depending on the same activation that does the reload.
- **`RunAtLoad`.** Settled: not set in the plist (verified with `plutil -p`), so
  activation's `launchctl load -w` does not start a second run. This contradicted
  an earlier draft of this doc, which listed it as both settled and open.

### How to test

This bug is intermittent (it only fires when the plist changes), so waiting for
it proves nothing and "it worked once" proves nothing. **Force the condition.**

**Step 0 — reproduce the bug first.** Do this before fixing, so you know the test
can fail. Without this, a passing test after the fix is meaningless.

**The run MUST be started via launchd, not by hand.** launchd only kills the
process *it* spawned for a given job Label. Running the store path directly
(`sudo /nix/store/<hash>-nix-auto-update`) produces a process launchd does not
associate with the job, so `unload` will not touch it and the bug will not
reproduce — you would "prove" a fix that does not exist.

Three preconditions have to hold at once, and an earlier version of this recipe
got all three wrong. Read them before running anything.

1. **The edited script must already be installed when you kickstart.** A marker
   edit only reaches the plist after an activation installs it. Kickstarting
   first runs the *old* script — the log then shows no marker, and you are
   testing the wrong binary. `just switch` first, then kickstart.
2. **The run needs a window long enough to race.** A cached build finishes the
   whole run in ~19s, which is not enough time to start a second `just switch`
   and have it reach activation. Add a temporary `sleep 180` before
   `darwin-rebuild` to hold the window open.
3. **The daemon's checkout must be behind `origin/main`,** or the script exits
   at "Already up to date" without rebuilding at all.

```sh
# 1. Edit auto-update.nix: add `log "STEP0-MARKER"` after "Starting nix
#    auto-update", and `sleep 180` just before the darwin-rebuild call.
#    git add it (untracked files are invisible to the build).
git add hosts/2023-macbook-pro/modules/auto-update.nix

# 2. INSTALL it first, so launchd runs the edited script.
just switch

# 3. Put the daemon's checkout behind origin so the run does real work.
sudo git -C /var/lib/nix-auto-update/nix-config reset --hard HEAD~1

# 4. Start the job THROUGH LAUNCHD so it is the tracked process.
sudo launchctl kickstart -k system/org.nixos.nix-auto-update

# 5. Confirm the RIGHT script is running before going further:
sudo tail /var/log/nix-auto-update.log
#    must show STEP0-MARKER. If it does not, you are racing the old script.

# 6. While it sleeps, change the script again so the plist DIFFERS, then switch.
#    An unchanged plist does not reload, and the job is NOT killed — that is the
#    control case, and it is worth seeing once.
#    Edit the marker to STEP0-MARKER-V2, git add, then:
just switch    # prints "reloading service org.nixos.nix-auto-update"

# 7. Expect: the daemon's log stops mid-sleep with no "Update complete" and no
#    Homebrew phase, and the PID is gone.
```

Note the `reloading service` line appears on the stdout of whichever process
runs the activation — your `just switch` here, not the daemon's log. The
historical logs show it inline only because those runs were the auto-update
doing its own rebuild. Its absence from the daemon log is not a failed repro.

**The self-revert trap — this will bite you.** The runner rebuilds from
`/var/lib/nix-auto-update/nix-config` at `origin/main`. While the fix is
committed locally but **not pushed**, that commit does not contain the fix, so
every daemon run *reverts the installed plist to the old script*. You then
kickstart again, get the old behaviour, and conclude the fix does not work.

Check the plist after any daemon run, before drawing conclusions:

```sh
plutil -p /Library/LaunchDaemons/org.nixos.nix-auto-update.plist | grep -A2 ProgramArguments
```

To test before pushing, point the checkout's `origin/main` at the local commit
(`sudo git -C /var/lib/nix-auto-update/nix-config update-ref refs/remotes/origin/main <sha>`).
Note the runner's `git fetch origin` will reset that ref again, so re-run
`update-ref` immediately before each kickstart. Do **not** repoint `origin` at
the user-owned working repo: the runner runs as root and git rejects it with
"detected dubious ownership", and the `safe.directory` workaround does not reach
the runner because its `PATH` pins a different git.

**Step 1 — after the fix, same procedure, opposite result.** Assert all four:

1. The script reaches **`Update complete`**.
2. The **Homebrew phase ran** — its output contains `Homebrew bundle...` /
   `brew bundle` lines. This is the half that was silently skipped, so it is the
   assertion that actually matters. Checking only for "Update complete" would
   miss a partial run.
3. `/run/current-system` advanced to the newly built generation.
4. The **new** plist is on disk afterwards, proving the next run picks up the new
   config:
   ```sh
   plutil -p /Library/LaunchDaemons/org.nixos.nix-auto-update.plist
   #   the embedded script path must be the NEW store hash, not the old one
   sudo launchctl list | grep nix-auto-update
   ```

**Step 2 — the scheduled run still works.** The detach must not break normal
operation. Either wait for the next 07:30 run, or trigger it:

```sh
sudo launchctl kickstart -k system/org.nixos.nix-auto-update
tail -f /var/log/nix-auto-update.log
```
Confirm it logs `Starting nix auto-update` → … → `Update complete`, and that the
log is not truncated or duplicated (see the `RunAtLoad` open question — a
double-start would show as two `Starting` lines close together).

**Step 3 — verify the work really is detached.** While a run is in flight:

**Both checks below are required — neither is sufficient alone.** A launcher that
simply *crashed* also leaves no tracked PID, so "no PID" on its own is equally
consistent with the fix working and with the update never starting.

```sh
# (a) the launchd job is no longer holding the work
sudo launchctl list | grep nix-auto-update
#     EXPECT '-' in the PID column (launcher already exited).

# (b) AND the real work is nevertheless still running, detached
pgrep -fl run-update.sh                        # must return a live process
ps -o pid,ppid,pgid,sess,command -p <runner-pid>
#     PPID should be 1 (reparented to init); PGID should equal the runner's own
#     PID (it is its own group leader), i.e. different from the launcher's.
```

Observed on the 2023 MBP, 2026-08-15 (a passing run):

```
  PID  PPID  PGID   SESS COMMAND
35968     1 35968      0 .../bash /var/lib/nix-auto-update/run-update.sh 20260815T162022-35960
```

`SESS` shows `0` on macOS `ps` even after a successful `setsid`; do not treat
that as a failure. `PPID=1` and `PGID == PID` are the assertions that matter.

Fails if: (a) shows a present, long-lived PID — the launchd-tracked process is
still doing the work and `unload` can kill it. Also fails if (a) passes but (b)
finds nothing — that is a crashed launcher, not a successful detach. Confirm the
run actually completes (`Update complete` in the log) before calling it green.

**Step 4 — the marker (if plan B is implemented).** Test that it reports rather
than lying:

```sh
# Simulate an unnotifiable death mid-run:
sudo pkill -9 -f nix-auto-update
ls /var/lib/nix-auto-update/            # marker file must still be present
sudo launchctl kickstart -k system/org.nixos.nix-auto-update
#   expect a Telegram alert naming the PREVIOUS run's timestamp/run-id,
#   then a normal run that clears the marker.
# And confirm no false positive: run twice cleanly in a row, expect no alert.
```

**Do both MacBooks.** The 2018 has the same bug; a fix verified only on the 2023
is half done.

### If you are the 2018 MBP session, start here

Your job is **verification, not implementation**. The fix is already committed
and applies to this host — do not re-derive it, do not re-plan it, and do not
start at Step 0 above. Step 0 reproduces the *unfixed* behaviour; running it here
means deliberately breaking a host that is already fixed, for no new information.
It was needed once, on the 2023, to prove the test could fail.

Substitute `hosts/2018-macbook-pro/modules/auto-update.nix` wherever the recipes
above say `2023-macbook-pro` — Step 0's snippet hardcodes the 2023 path.

Procedure:

1. `git pull` — confirm `MBPs - Stop auto-update killing itself during activation`
   is in the log, and that this host's `auto-update.nix` matches the 2023's
   (`diff hosts/2018-macbook-pro/modules/auto-update.nix hosts/2023-macbook-pro/modules/auto-update.nix`
   must be empty).
2. `just switch`, then confirm the plist points at the new launcher:
   `plutil -p /Library/LaunchDaemons/org.nixos.nix-auto-update.plist`.
3. Put the daemon's checkout behind origin so a run does real work:
   `sudo git -C /var/lib/nix-auto-update/nix-config reset --hard HEAD~1`.
4. `sudo launchctl kickstart -k system/org.nixos.nix-auto-update`, then run the
   **Step 3** detach checks while it is in flight — both (a) and (b), together.
   This is the assertion that actually distinguishes a working detach from a
   crashed launcher.
5. Assert the four **Step 1** outcomes, and Step 4 for the marker.

Because the fix is pushed by the time you run this, the self-revert trap does
**not** apply to you: the runner rebuilds from `origin/main`, which now contains
the fix, so the plist stays correct across the run. Verify it anyway (step 2's
command, re-run afterwards) — if the plist reverts to a different store path, the
commit did not reach this host.

Expected wall-clock: a run takes seconds to a couple of minutes. If the log shows
`Starting nix auto-update (run <id>)` and then nothing, with `run-update.sh`
present but no marker file, you are looking at the detach race described under
"Open questions" — not a new bug.

### Verification record — 2023 MBP, 2026-08-15

Step 0 reproduced the bug under control before any fix was written: with the
plist **unchanged**, a concurrent `just switch` left the running job alive; with
the plist **changed**, the same switch printed `reloading service
org.nixos.nix-auto-update` and the job died mid-`sleep` (PID gone, log
truncated, no Homebrew phase). That pairing is what pins the cause to the
plist-change reload specifically, rather than to concurrent activation in
general.

After the fix, a daemon run rebuilt across a plist change and:

| Assertion | Result |
|---|---|
| Reached `Update complete` | ✅ 16:22:19 |
| Homebrew phase ran | ✅ `brew bundle` present |
| **Survived `reloading service …` in its own log** | ✅ the line the old code died on |
| `/run/current-system` advanced | ✅ |
| Launcher already exited (`-` PID) while runner alive | ✅ both, together |
| Marker cleared on success | ✅ |
| Stale marker reported on next run | ✅ named the previous run id |
| No false positive on two clean runs | ✅ |

## Plan B — marker file (implemented alongside plan A)

Only a detector, not a fix, and it reports up to ~24h late (at the *next* run).
The user explicitly ranked this below plan A. Implement it in addition to plan A,
not instead of it, to cover "killed by something we did not anticipate" — the
class of failure that by definition cannot notify from inside the dying process.

Shape: write a marker at script start containing a **timestamp and run id**;
remove it on `Update complete`. Next run sees a leftover marker and notifies that
the previous run died.

Known correctness issue to handle: a manual `just switch` racing the scheduled
run could clobber or misattribute the marker. The timestamp/run-id is what makes
the alert say *which* run died; do not reduce it to a bare touch-file.

As implemented, the marker holds `run <id> started <timestamp>`, so the alert
names the run that died. Two limits are accepted rather than solved:

- **Two overlapping daemon runs** (only reachable by kickstarting during a run —
  the 07:30 schedule cannot do it) share one marker path, so the second
  overwrites the first and the first goes unreported.
- **A manual `just switch` does not touch the marker at all.** It is written
  only by the runner, so a manual switch cannot clobber it; it can still *kill*
  a run, which is precisely the case the next run reports.

Both are strictly better than the pre-fix state, where nothing was reported at
all. Revisit only if overlapping runs stop being purely hypothetical.

## Files

- `hosts/2023-macbook-pro/modules/auto-update.nix` — launcher + detach helper + runner
- `hosts/2018-macbook-pro/modules/auto-update.nix` — identical; verify there too
- `/var/lib/nix-auto-update/run-update.sh` — the runner, installed on every run
- `/var/lib/nix-auto-update/run-in-progress` — plan B marker (absent when idle)
- `/var/log/nix-auto-update.log` — evidence (grep for `reloading service org.nixos.nix-auto-update`)

Commit prefix for a change touching both: **MBPs**.
