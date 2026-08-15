# MBP auto-update killed by its own activation — diagnosis and plan

**Status:** diagnosed 2026-08-14, not yet implemented.
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

### Open questions for the implementing session

- Exact detach mechanism on macOS under launchd. `setsid` is not in macOS base;
  check what is available in the script's `PATH`
  (`/run/current-system/sw/bin:/usr/bin:/bin`) — nixpkgs `util-linux` provides
  `setsid`, or use `nohup` + `disown`, or a small `perl -e 'setsid'`. Verify the
  detached process genuinely leaves the job's process group, or `unload` may
  still reach it.
- Whether the launcher should copy the script to the stable path on every run
  (simple, self-healing) or via a `system.activationScripts` entry (cleaner, but
  runs during the same activation that does the reload).
- Whether `RunAtLoad` interacts badly: activation does `load -w` immediately
  after `unload`, which could trigger a second run right after the first was
  killed. Check the current plist for `RunAtLoad` before changing anything.

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

```sh
# Confirm the current (unfixed) behaviour kills the script.
# 1. Edit auto-update.nix so autoUpdateScript's derivation changes
#    (e.g. add a `log "marker"` line). git add it (untracked files are invisible
#    to the build), but do NOT commit yet.
# 2. Start the job THROUGH LAUNCHD so it is the tracked process:
sudo launchctl kickstart -k system/org.nixos.nix-auto-update
tail -f /var/log/nix-auto-update.log
# 3. While it is mid-rebuild, from ANOTHER terminal:
just switch
# 4. Expect: the log stops at "reloading service org.nixos.nix-auto-update",
#    with no "Update complete" and no Homebrew phase.
```

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
pgrep -fl darwin-rebuild                       # must return a live process
ps -o pid,ppid,pgid,sess,command -p <rebuild-pid>
#     PPID should be 1 (reparented to init); PGID/SESS should differ from the
#     original launcher's.
```

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

## Plan B — marker file (fallback only)

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

## Files

- `hosts/2023-macbook-pro/modules/auto-update.nix` — daemon + script
- `hosts/2018-macbook-pro/modules/auto-update.nix` — same bug, apply the same fix
- `/var/log/nix-auto-update.log` — evidence (grep for `reloading service org.nixos.nix-auto-update`)

Commit prefix for a change touching both: **MBPs**.
