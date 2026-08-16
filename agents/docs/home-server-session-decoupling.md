# Home server: auto-update kills the GNOME session, box then suspends — diagnosis and plan

**Status:** diagnosed 2026-08-14, refined 2026-08-15, **implemented and verified
2026-08-15**. Work items 1 and 2 are done and tested on the live host; work item
2b remains optional and undone.
**Affects:** `hosts/home-server/` (`configuration.nix`, `home.nix`, `auto-update.nix`).
**User impact:** machine becomes **unreachable over the network for hours** and
needs a physical power-button press to come back. Running apps and in-flight
torrent downloads are lost.

## What was implemented (2026-08-15)

Five commits, all prefixed `HomeServer`:

| Commit title | What it does |
|---|---|
| Stop the box suspending itself after a session teardown | Work item 2 |
| Run Transmission as a system service | Work item 1 |
| Remove the Transmission GUI from the desktop session | Retires `transmission-gtk` |
| Manage desktop autostart entries with home-manager | Chrome, Files, Console |
| Add a Transmission remote client and transmission.local | `transmission-remote-gtk`, mDNS name |

**Verified on the live host**, not just by evaluation:

- `busctl … CanSuspend` went from `"challenge"` (before) to `"no"` (after). This
  is the cheap non-destructive probe — see "Testing suspend without suspending".
- The **regression test passed**: the GNOME session was terminated, a greeter
  session (uid 60578) sat idle for **21 minutes** — past the ~15 minutes that
  suspended the box on 2026-08-14 — and the machine stayed reachable with
  `PM: suspend entry` count 0 and uptime unbroken.
- A **throttled download continued across a session teardown**: 0.69% → 1.90% →
  2.48% while the desktop session was killed and restarted. `transmission.service`
  kept the same `ActiveEnterTimestamp` throughout, i.e. it never restarted.
- Downloaded files land `-rw-rw-r-- transmission users`, so `patate` can read and
  delete them, and `/home/patate/Downloads` is **still owned by `patate`**.

### Things this doc got wrong or did not predict

Each of these cost a round trip; none were visible from evaluation alone.

1. **`/etc/dconf/db/gdm.d/` does not exist on this host.** The doc's test command
   greps it and would report the primary fix as missing. The greeter profile at
   `/etc/dconf/profile/gdm` is a **store symlink** whose `file-db:` line points at
   a compiled binary DB in `/nix/store`. Verify with:
   ```sh
   ssh home-server.local "cat /etc/dconf/profile/gdm"     # find the file-db: path
   ssh home-server.local "grep -a -oE 'sleep-inactive-[a-z-]*|nothing' <that-path> | sort -u"
   ```
2. **`incomplete-dir` fails the unit when `downloadDirPermissions` is null.**
   `BindPaths=` does not create its targets, and the module only creates
   `.incomplete` inside the `downloadDirPermissions != null` branch of
   `transmission-setup.service`. Leaving that null to protect the download dir's
   ownership therefore breaks the service with
   `Failed to set up mount namespacing: …/.incomplete: No such file or directory`
   and `status=226/NAMESPACE`. Create the directory with a tmpfiles rule instead;
   `transmission.service` is already ordered `After=systemd-tmpfiles-setup.service`.
3. **RPC answers 421, not 403, when reached by hostname.** The doc lists 409/403/000
   but not this. `rpc-host-whitelist-enabled` defaults to **true with an empty
   list**, which rejects any request whose `Host:` header is a name rather than an
   address — so `curl http://192.168.0.17:9091/…` returns 409 while
   `curl http://home-server.local:9091/…` returns 421. This is a *separate* check
   from `rpc-whitelist`. Set `rpc-host-whitelist-enabled = false`.
4. **`downloadDirPermissions` is not needed at all**, and setting it is actively
   undesirable here — see "Keeping the download dir owned by patate" below.
5. **A stale autostart entry was hiding in `~/.config/autostart/`.** Removing the
   `transmission_4-gtk` package does not remove a hand-placed `.desktop` copy.
   Three such 2023-era files were there, one (`chromium-browser.desktop`) pointing
   at a browser that is not installed — which is why Chrome never came back with
   the session. They are now declared through home-manager instead.
6. **Removing the GUI leaves no client.** `transmission-remote` (CLI) ships with
   the daemon, but there is no GUI until `transmission-remote-gtk` is installed
   explicitly.

### Keeping the download dir owned by `patate`

The doc presents a choice between the module's confined `transmission` user and a
Samba-compatible one, and flags `downloadDirPermissions` as the lever. **Neither
trade-off is necessary.** The module binds `download-dir` into a `RootDirectory`
jail precisely so the daemon never traverses the parent directory
(`transmission.nix`, comment above `RootDirectory=`: *"makes it possible to use
the same paths download-dir/incomplete-dir … without requiring cfg.user to have
access to their parent directories"*). So `/home/patate` can stay `drwx------`.

What actually works:

- `services.transmission.group = "users"` (patate's primary group)
- `settings.umask = "002"` so created files are `664`, not `600`
- **omit `downloadDirPermissions`** — setting it makes `transmission-setup` run
  `install -d -o transmission …` on the download dir, chowning it away from patate
- a tmpfiles rule for mode only: `d /home/patate/Downloads 0775 patate users -`
- a second tmpfiles rule to create `.incomplete`, owned by `transmission`

Note the unit sets `UMask=0066` at the systemd level, which looks like it would
strip group-read from downloaded files. It does not win: Transmission applies its
own `settings.umask` when creating files. Verified — files land `-rw-rw-r--`.

### Testing suspend without suspending

The doc's step 0 (`systemctl suspend` before the change, to prove the test can
fail) takes the box down and needs a physical power press. It is unnecessary:

```sh
ssh home-server.local "busctl call org.freedesktop.login1 /org/freedesktop/login1 \
  org.freedesktop.login1.Manager CanSuspend"
```

`"challenge"` = permitted by policy, merely needs authentication → the test can
fail, so a later pass is meaningful. `"no"` = refused by `sleep.conf`. This reads
the same policy `systemctl suspend` consults, without suspending anything.

### Connecting to the daemon

| Where | Client | Notes |
|---|---|---|
| Mac | Web UI at `http://transmission.local:9091` | Works with no install |
| Mac | `transmission-remote-gtk` | **Not available** — `platforms = linux` |
| Server | `transmission-remote` CLI | Ships with the daemon |
| Server | `transmission-remote-gtk` | Installed, autostarts with the session |

`transmission.local` is published by an `avahi-publish` unit modelled on the
existing `avahi-publish-cash22` one. Both **hardcode `192.168.0.17`**, so both
break if the server's address changes.

### Fixed in passing: the `gdm-greeter-N` UID warnings

Every activation logged three `warning: not applying UID change of user
‘gdm-greeter-N’` lines. Not cosmetic: four of the five greeter users had drifted
one place from the UIDs the GDM module declares, and **`gdm-greeter-4` and
`gdm-greeter-5` had ended up sharing UID 60582**.

They predate the module pinning UIDs, so NixOS had allocated them sequentially.
`update-users-groups.pl` warns and then *keeps* the existing UID (see the
`$u->{uid} != $existing->{uid}` branch), deliberately, because files could be
owned by the old number — so no rebuild can ever fix this on its own.

Safe to repair here because nothing referenced those UIDs: no files under `/var`
or `/home` owned by 60580/60581/60582, `/run/gdm/home/` is a tmpfs and was empty,
and no processes ran as them. Only `gdm-greeter` (60578, already correct) is used
on a single-seat machine.

Fix: `sudo userdel gdm-greeter-{2,3,4,5}` then `just switch`, which recreates them
at the declared UIDs. Confirmed afterwards with `/run/current-system/dry-activate`
— a dry run is the cheap way to check for activation warnings without applying
anything.

### Still open

- **Work item 2b is implemented but has never fired.** It needs a real
  user-activation failure to prove itself; every teardown so far was triggered by
  hand. If a future update does tear the session down, check for the Telegram
  notification "user activation failed, display manager restarted" and confirm
  the desktop came back on its own.
- Test a session cycle with a **reboot**, not a logout, when convenient: GDM
  autologin fires on boot but generally shows the greeter after an explicit
  logout. Nothing here has been verified across a reboot — the box has been up
  continuously since 2026-08-14.
- `transmission.local` still needs its `:9091`. See
  `transmission-bare-hostname.md` for the skeleton plan; the blocker is that
  kamal-proxy owns port 80 and is not managed by this repo.

## Symptom

On 2026-08-14 the 07:30 JST auto-update ran, tore down the logged-in GNOME
session, and ~15 minutes later **the machine suspended itself to RAM** and
dropped off the network. `nix-auto-update.service` failed with exit code 1; the
underlying `switch-to-configuration switch` returned **4**. A Telegram alert *was*
sent — the notify path works on this host, because the failure is an ordinary
non-zero exit rather than a signal kill.

The generation itself applied fine: `/run/booted-system` and `/run/current-system`
both pointed at `...nixos-system-home-server-26.11.20260813.0e251e2`. Only user
session activation failed.

## Corrected timeline (this supersedes the first-pass diagnosis)

The first pass concluded "the update leaves you at a GDM password prompt you
cannot type into". **That was wrong**, and the correction came from the user's
own observation: shaking the attached mouse produced no display activity at all,
which a live greeter would have woken. The journal confirms what actually
happened:

| Time (JST) | Event |
|---|---|
| 07:33 | Update tears down the GNOME session. `gnome-shell` logs `Connection to xwayland lost`; every GNOME session target stops. `display-manager.service` is in the **NOT restarting** list, so GDM is not restarted. A **greeter** session starts (`user@60578.service`). |
| 07:48:54 | `systemd-logind`: `suspend requested from client PID 283545 ('.gsd-power-wrap') (unit user@60578.service)` → `The system will suspend now!` → `PM: suspend entry (deep)`. `avahi-daemon: Withdrawing address record for 192.168.0.17`. |
| 07:48 → 11:35 | **Suspended (S3). Machine is off the network** — this is why SSH failed and why a subnet sweep found no host. |
| 11:35:46 | User presses the power button → `ACPI: PM: Waking up from system sleep state S3`. Resumes to the greeter → the login screen the user saw. |
| 11:36 | User reboots from that screen with the mouse. Clean shutdown (`Finished System Reboot`, swap deactivated in order, filesystems synced). |

Two distinct events — a **wake from S3** and a **subsequent reboot** — were
initially collapsed into one "fresh boot". They are not the same, and only the
reboot produced the clean-shutdown record.

### The key detail: who requested the suspend

**UID 60578 is `gdm-greeter`** (`getent passwd 60578` →
`gdm-greeter:x:60578:132::/run/gdm/home/gdm-greeter:...`), not `patate`.

The user's own anti-sleep settings in `home.nix:99-102`
(`sleep-inactive-ac-type = "nothing"`) and `idle-delay = 0` (`home.nix:95-97`)
are **user-level dconf applied to `patate`**. The greeter is a different user
with its own dconf and never sees them. The settings are correct; they simply do
not apply to the process that suspended the machine.

This is also why the screen lock was never involved — the greeter logged
`Screen lock is locked down, not locking`, confirming the user's lockdown
setting was in effect.

### Rejected: the screen-lock fix

An earlier draft proposed `org/gnome/desktop/screensaver lock-enabled = false`
and `disable-lock-screen = true` to stop the password prompt. **Do not implement
this as the fix.** There was no lock screen to dismiss and no compositor running;
the display was dead because the machine was asleep. The dconf lock settings
would not have changed anything on 2026-08-14. (Harmless as hygiene, but it
addresses nothing in this failure chain.)

## Root cause

The daily flake update moves packages (pipewire, gvfs, dconf, the xdg portals…)
to new store paths. `switch-to-configuration` restarts a unit whose store path
changed — including **user** units. It re-execs itself as the logged-in user to
do this (`switch-to-configuration-ng/src/main.rs:2381-2440`).

That child stopped ~28 user units, **including `dbus-broker.service`**, and then
could not start anything back because it had just killed the bus it was talking
over:

```
Failed to start user unit default.target: Connection is closed
Error: Failed to process dbus messages while waiting for jobs
    Caused by: Failed to read/write data, disconnected from D-Bus?
warning: user activation for patate failed
```

Every such failure sets `exit_code = 4` in that source file — matching the
observed status.

Note the journal line `NOT restarting the following changed units:
display-manager.service, ..., user@1000.service`: GDM and the user manager were
deliberately spared. **The session died from the D-Bus teardown underneath it,
not from GDM being restarted.**

There is a real reason for the restarts — the old processes keep running
now-deleted store paths until restarted, which `nix-gc` later reclaims. The
problem is not that restarts happen; it is that the desktop session and the
always-on workloads share one blast radius.

## Findings on the live machine (2026-08-14)

Gathered over SSH; re-verify before implementing, these may drift.

| Thing | Value |
|---|---|
| NixOS | 26.11.20260813 "Zokor" (unstable) |
| GNOME Shell | 50.4 |
| Session type | **Wayland** (`loginctl show-session 1` → `Type=wayland`, `Class=user`, `State=active`) |
| GDM autologin | enabled, user `patate` (`configuration.nix:104-105`) |
| Transmission | `transmission-gtk` (GUI), PID in a transient scope `app-gnome-transmission\x2dgtk-*.scope`, parented to `user@1000.service` |
| Transmission RPC | `rpc-enabled = false` in `~/.config/transmission/settings.json` |
| Lingering | `Linger=no`; `/var/lib/systemd/linger/` empty |
| Docker | `cash22-web`, `kamal-proxy` — already system-level, unaffected by logout |
| Chrome | 151.x, `restore_on_startup: 1`, but `exit_type: "Crashed"` after the incident |
| systemd | 261 (261.1) |
| Suspend | **not blocked** — no `sleep.conf` restrictions; greeter suspended the box on 2026-08-14 |

**SSH: use the hostname, plain.** `~/.ssh/config` maps `Host home-server.local`
→ `User patate`, so this works and is auto-approved:

```
ssh home-server.local journalctl -u nix-auto-update --no-pager -n 20
```

**Keep the invocation plain — do not add flags, and do not switch to a raw IP.**
`.claude/settings.json` excludes `ssh home-server.local *` from the sandbox, so
plain calls run outside it where mDNS works. A flag between `ssh` and the
hostname breaks that glob match, the command runs *inside* the sandbox, and
`.local` fails to resolve there. `Could not resolve hostname home-server.local`
is therefore a sandbox artifact, not evidence the host is down. Put any
persistent options in `~/.ssh/config`, not on the command line.

(The box's address is 192.168.0.17, recorded here only because it appears in the
journal lines quoted above. Use the hostname.)

## Decisions taken

**Is an always-on graphical session normal on a server?** No — conventional
practice is headless, services as systemd units. But that is not the real
problem, and the user is **not** required to change habits. The problem is the
entanglement of desktop session and always-on workloads. Decouple those and the
always-on session becomes harmless.

**Chosen direction: decouple, keep the always-on session.** Once nothing critical
lives inside the session, a botched update costs some open windows, not
downloads. This directly addresses "tired of restarting my programs" without
requiring the user to log out.

### Rejected options

- **`restartIfChanged = false` on the user units** — treats the symptom. The
  failure was the whole user D-Bus session going away mid-sequence, and
  `dbus-broker.service` was itself in the stop list. Does not address downloads
  surviving logout. (Note: user units *do* honour `X-RestartIfChanged` —
  `main.rs:738` — so this is a real knob, just the wrong one here.)
- **Move the rebuild to a time nobody is logged in** — probabilistic patch on a
  machine the user wants to sit logged into indefinitely. Also does nothing for
  downloads.
- **Full GNOME app session restore** — not achievable. GNOME dropped X11 XSMP
  session restore and Wayland has no equivalent; arbitrary apps (VLC, terminals,
  file managers) will not reopen. Do not promise this. Chrome tab restore is the
  exception (see below).

### Correction to an earlier misreading

The timer is **not** misscheduled. `auto-update.nix` sets
`OnCalendar = "*-*-* 22:30:00 UTC"` and `time.timeZone = "Asia/Tokyo"`, so 22:30
UTC == 07:30 JST. Same instant. Nothing to fix there.

## Work item 1 — Transmission as a system service

**Goal:** downloads continue while logged out, and survive session teardown.

Today `transmission-gtk` is a child of the graphical session with `Linger=no`, so
logging out kills it. It has no independent lifecycle.

Plan: replace it with the NixOS `services.transmission` module as a **system**
service, `rpc-enabled = true`, RPC bound to the LAN and whitelisted to the local
subnet. Downloads keep landing in `/home/patate/Downloads` (already Samba-shared
— check the `Downloads` share's `force user`/permissions still line up with
whatever user the daemon runs as; the share currently forces `patate:users`).

**The user keeps a GUI.** `transmission-gtk` has no remote/RPC flag (verified:
its `--help` offers only `--config-dir`, `--paused`, `--minimized`, `--version`),
so the GTK app itself cannot attach to a daemon. Use **`transmission-remote-gtk`**
instead — nixpkgs `pkgs/by-name/tr/transmission-remote-gtk`, described as "GTK
remote control for the Transmission BitTorrent client". `transmission-qt` also
supports remote sessions.

This satisfies a bonus the user asked for: with RPC enabled, torrents can be
added **from the MBP** without logging into the server — either via
`transmission-remote-gtk` on the Mac, the web UI, or the `transmission-remote`
CLI. Note `transmission-remote-gtk` is `platforms = linux` in nixpkgs; on macOS
use the web UI or another RPC client. Verify before promising a Mac GUI.

### Required settings — these are NOT defaults, and omitting them fails silently

Verified by reading `nixos/modules/services/torrent/transmission.nix` in the
pinned nixpkgs. Every one of these bites:

- **HARD EVAL BLOCKER — `package` must be set explicitly.** `transmission.nix:340-351`
  throws if `system.stateVersion` is older than `25.11` and `package` is unset.
  This host is `system.stateVersion = "23.05"` (`configuration.nix:267`), so
  **`services.transmission.enable = true` alone will not evaluate.** Set:
  ```nix
  services.transmission.package = pkgs.transmission_4;
  ```
  The throw exists because the 3→4 default change caused data loss for some
  users — **back up torrent state before switching** (NixOS 24.11 release notes).
- **User/group defaults to `transmission:transmission`**, not `patate`. The
  Samba `Downloads` share uses `force user = patate` (`configuration.nix:222`),
  so files written by the daemon will not match unless you adjust something.
  **Resolved in implementation — see "Keeping the download dir owned by patate"
  above.** Short version: set `group = "users"` and `settings.umask = "002"`,
  leave `downloadDirPermissions` unset, and grant group-write with a tmpfiles
  rule. This keeps the module's sandboxing *and* patate's ownership; the
  either/or framing below turned out to be a false choice.
- **`download-dir` defaults to `${cfg.home}/Downloads`** = `/var/lib/transmission/Downloads`,
  **not** `/home/patate/Downloads`. Set `settings.download-dir` explicitly or
  downloads stop appearing in the Samba share.
- **`rpc-bind-address` defaults to `127.0.0.1`** — remote access needs it
  widened, otherwise nothing off-box can connect.
- **`rpc-whitelist` is enabled by default and allows only `127.0.0.1,::1`.**
  Widening `rpc-bind-address` without also setting `settings.rpc-whitelist` to
  include the LAN yields **HTTP 403**, not a connection error — a confusing
  failure that looks like the daemon working. `services.transmission.openRPCPort`
  exists for the firewall side.

**There was no torrent state to migrate.** `~/.config/transmission/torrents/` was
empty and the queue was `[]` — the nine directories in `Downloads` are finished
downloads with no active torrent, so nothing was seeding and the NixOS 24.11
data-loss warning about the 3→4 default change did not apply. Confirm this again
before assuming it still holds. Worth knowing: when a completed file is already
on disk, adding its torrent to the daemon makes it verify and adopt the data
immediately (observed: a 3.41 GB ISO went straight to 100%), so a future
migration would not re-download.

`openRPCPort = true` handles the firewall; the resulting port list is
`[22,139,445,1883,3389,5357,9091,51413]`.

### How to test work item 1

Do this with at least one **active torrent** in progress, otherwise the critical
assertion (downloads survive) is vacuous.

```sh
# 1. Daemon runs at system level, not under the user session
ssh ... systemctl status transmission          # active, and NOT under user@1000
ssh ... systemctl show transmission -p MainPID -p FragmentPath

# 2. RPC reachable from the MBP (the point of the change)
curl -s http://home-server.local:9091/transmission/rpc -o /dev/null -w '%{http_code}\n'
#    409 = working. That is the RPC handshake asking for a session id.
#    421 = rpc-host-whitelist rejecting the Host: header, NOT the IP whitelist.
#          Observed for real. Compare against the IP form to confirm:
#          curl http://192.168.0.17:9091/... returning 409 while the hostname
#          returns 421 is exactly this. Fix: rpc-host-whitelist-enabled = false.
#    403 = listening, but rpc-whitelist is rejecting your address.
#    000/refused = not listening, or firewall/rpc-bind-address wrong.
#    Distinguishing these four tells you which layer to fix.

# 3. Downloads survive the user logging out — the actual requirement
ssh ... transmission-remote -l                 # note progress % of an active torrent
ssh ... loginctl list-sessions                 # find patate's session id
#    log out of the GNOME session (physically, or: loginctl terminate-session <id>)
sleep 120
ssh ... transmission-remote -l                 # progress MUST have advanced

# 4. Survives the failure that started all this
#    trigger a switch that restarts user units, then re-check:
ssh ... transmission-remote -l                 # still running, progress advancing
```

Also verify files still land correctly for Samba: download something small and
confirm it appears in `/home/patate/Downloads` with ownership the `Downloads`
share can serve (the share forces `patate:users`). A daemon running as a
different user is the most likely way this breaks silently.

Rollback: the old `transmission-gtk` state lives in `~/.config/transmission/`.
Do not delete it until the daemon has been proven to work with the migrated
torrents.

## Work item 2 — stop the machine suspending itself (highest priority)

**This is the fix for the user's actual pain: the box disappears from the
network and only a physical power press brings it back.**

A machine serving Samba, Docker, MQTT and torrents should never suspend. The
per-user dconf settings cannot guarantee that, because *any* user session
(notably `gdm-greeter`) can request a suspend. The fix must be **system-wide**,
below the desktop layer.

### Verified fix — primary: stop the greeter idling to sleep

nixpkgs ships a purpose-built option for **exactly** this failure. GDM's module
(`nixos/modules/services/display-managers/gdm.nix:151-158`) has:

```nix
services.displayManager.gdm.autoSuspend = false;
```

> "On the GNOME Display Manager login screen, suspend the machine after
> inactivity. (Does not affect automatic suspend while logged in, or at lock
> screen.)" — default `true`.

When false, the module writes (`gdm.nix:337-347`) into the **greeter's own**
dconf profile:

```
org/gnome/settings-daemon/plugins/power:
  sleep-inactive-ac-type      = "nothing"
  sleep-inactive-battery-type = "nothing"
  sleep-inactive-ac-timeout   = 0
  sleep-inactive-battery-timeout = 0
```

These are the same keys `home.nix:99-102` sets for `patate` — but scoped to
`gdm`, which is the user that actually suspended the machine. **This addresses
the root cause** rather than removing a capability system-wide.

Verified against the real host config:

```
nix eval --impure --json --expr 'let f = builtins.getFlake (toString ./.);
  e = f.nixosConfigurations.home-server.extendModules {
    modules = [{ services.displayManager.gdm.autoSuspend = false; }]; };
in map (d: d.settings) (builtins.filter (d: d ? settings)
     e.config.programs.dconf.profiles.gdm.databases)'
```

→ `[{"org/gnome/settings-daemon/plugins/power":{"sleep-inactive-ac-timeout":"0",
"sleep-inactive-ac-type":"nothing","sleep-inactive-battery-timeout":"0",
"sleep-inactive-battery-type":"nothing"}}]`

`programs.dconf.enable = true` is already set (`configuration.nix:241`), so this
is a genuine one-liner with no extra wiring.

### Verified fix — belt-and-braces: block suspend system-wide

Keep this **in addition**, as a backstop for any other future suspend requester
(not as the primary fix). `AllowSuspend=` is a **`sleep.conf`** directive, not a
`logind.conf` one. In NixOS it maps to `systemd.sleep.settings.Sleep`.

```nix
# hosts/home-server/configuration.nix
systemd.sleep.settings.Sleep = {
  AllowSuspend = "no";
  AllowHibernation = "no";
  AllowSuspendThenHibernate = "no";
  AllowHybridSleep = "no";
};
```

Caveat worth knowing: this removes the ability to suspend *deliberately* too. On
a machine meant to be always-on that is the intent, but state it out loud rather
than discovering it later.

Verified by evaluating against the real host config (not a toy module):

```
nix eval --impure --raw --expr 'let f = builtins.getFlake (toString ./.);
  e = f.nixosConfigurations.home-server.extendModules { modules = [{ ... }]; };
in e.config.environment.etc."systemd/sleep.conf".text'
```

produces exactly:

```
[Sleep]
AllowHibernation=no
AllowHybridSleep=no
AllowSuspend=no
AllowSuspendThenHibernate=no
```

Per `man systemd-sleep.conf` (systemd 261, read on the box): *"By default, any
power-saving mode is advertised if possible… Those switches can be used to
disable specific modes."* `AllowSuspend=no` also implies
`AllowSuspendThenHibernate=no` and `AllowHybridSleep=no`; the extra lines are
belt-and-braces and harmless.

### Belt-and-braces: idle action

Optionally also pin logind's idle behaviour, which is a separate path from the
desktop's:

```nix
services.logind.settings.Login.IdleAction = "ignore";
```

Verified output:

```
[Login]
IdleAction=ignore
KillUserProcesses=false
```

### Verified pitfalls — read before editing

- **`services.logind.extraConfig` and `systemd.sleep.extraConfig` are REMOVED,
  not merely deprecated.** Both are `mkRemovedOptionModule`
  (grep `mkRemovedOptionModule` in `logind.nix` / `systemd.nix`), so using the
  old names is a hard
  **eval error**, not a warning. Use `services.logind.settings.Login` and
  `systemd.sleep.settings.Sleep`.
- **`AllowSuspend` does NOT exist in `logind.conf`.** Confirmed: `grep -c
  AllowSuspend logind.conf.5` returns **0** on systemd 261. Putting it under
  `services.logind.settings.Login` would silently do nothing. It belongs in
  `sleep.conf`.
- **Do NOT set `HandlePowerKey = "ignore"`.** The power button is currently the
  user's only physical recovery path on a machine with no keyboard attached.
  Disabling it removes that escape hatch. (`configuration.nix:100` currently
  sets GNOME's `power-button-action = "interactive"`, which is a separate,
  user-level setting.)
- There is **no NixOS wrapper option** for these (no `allowedTypes`, no
  `AllowSuspend` helper anywhere in `nixos/modules/`) — the freeform
  `settings` passthrough is the supported route.

### How to test work item 2

Test before applying too, so you know the test can actually fail — otherwise a
passing result proves nothing.

```sh
# 0. BEFORE the change: confirm the machine really does suspend on request.
#    Run from a shell you can afford to lose; it WILL go down.
ssh ... systemctl suspend
#    machine drops off the network -> the test is meaningful. Wake it physically.

# 1. AFTER the change: both fixes landed
ssh ... cat /etc/systemd/sleep.conf
#    expect:
#      [Sleep]
#      AllowHibernation=no
#      AllowHybridSleep=no
#      AllowSuspend=no
#      AllowSuspendThenHibernate=no

#    and the greeter's dconf profile (the primary fix).
#    NOTE: /etc/dconf/db/gdm.d/ does NOT exist on this host — see "Things this
#    doc got wrong" above. Follow the store symlink instead:
ssh ... cat /etc/dconf/profile/gdm                    # note the file-db: path
ssh ... "grep -a -oE 'sleep-inactive-[a-z-]*|nothing' <that-path> | sort -u"
#    expect the four sleep-inactive-* keys and the value 'nothing'

# 2. Suspend is actually refused (the real assertion)
ssh ... systemctl suspend ; echo "exit=$?"
#    expect a non-zero exit and an error like "Sleep verb 'suspend' is disabled
#    by config". The machine MUST stay reachable:
ssh ... uptime                               # still up, uptime NOT reset

# 3. Nothing suspended it behind your back
ssh ... journalctl -b --no-pager | grep -c 'PM: suspend entry'   # expect 0
```

**The regression test that matters** — reproduce the original chain, because
steps 1-3 do not prove the *greeter* cannot suspend the box:

```sh
# Tear down the graphical session the way the update does, then wait out the
# greeter's idle timer (the 2026-08-14 suspend came ~15 min after teardown).
ssh ... loginctl terminate-session <patate-session-id>
sleep 1200                                   # 20 min, comfortably past 15
ssh ... uptime                               # MUST still respond
ssh ... journalctl -b --no-pager | grep 'PM: suspend entry'      # MUST be empty
```

If the box is unreachable after that sleep, the fix did not work — check whether
the suspend came from a path `sleep.conf` does not cover.

Finally, confirm the box survives a real update cycle: wait for (or trigger) a
`nixos-rebuild switch` that restarts user units, then verify SSH still answers.

## Work item 2b (DONE 2026-08-16) — recover the display after a teardown

**Implemented** in `hosts/home-server/auto-update.nix`. The script now matches
`user activation for patate failed` in the switch log — the marker that
`switch-to-configuration` returned 4 because the user D-Bus session died —
restarts `display-manager.service`, and reports the run as complete with a
notification saying what happened.

Ordering matters and is deliberate: the `switchInhibitors` case is matched
*first* so an inhibitor-blocked switch still stages via `boot`, and anything that
matches neither still reports a genuine failure. Verified against the real
2026-08-14 log text plus a synthetic build failure, so the branch is narrow and
does not mask real breakage.

Not yet exercised by a real failure — the 2026-08-16 auto-update succeeded
without tearing the session down, so this path is still untested in anger.

The original description follows.

Even with suspend disabled, a torn-down session leaves **no compositor and no
greeter** (GDM is deliberately in the "NOT restarting" list), so the screen stays
dark until something restarts the display manager. The machine remains reachable
over SSH, so this is no longer an emergency — but for an unattended desktop it is
still worth having the auto-update restart `display-manager.service` when user
activation fails (`switch-to-configuration` exit 4). Autologin then fires on the
fresh GDM and the desktop returns without intervention.

Not yet designed; lower priority than work items 1 and 2.

## Work item 3 (optional) — Chrome tabs

`restore_on_startup: 1` is already set, so tabs *do* come back — but only after a
**clean** shutdown, which sets `exit_type: "Normal"`. The 2026-08-14 teardown was
not clean, hence the current `exit_type: "Crashed"`. Nothing to configure; this
is a behavioural note. Once work item 1 lands, losing Chrome is cheap, and an
explicit logout (rather than a killed session) is what makes tabs reliably
return.

## Suggested order

Items 1 and 2 are **done** (2026-08-15), in the order below.

1. ~~**Work item 2** (system-wide suspend off)~~ — done. Smallest change, biggest
   relief, and independent of everything else. Doing it first was correct.
2. ~~**Work item 1** (Transmission as a system service)~~ — done.
3. ~~**Work item 2b** (restart the display manager on activation failure)~~ —
   done 2026-08-16.
4. ~~Confirm across a **real** auto-update cycle~~ — done. The 2026-08-16 07:30
   run completed with `Update complete`, the GNOME session **survived**, uptime
   was unbroken and `PM: suspend entry` stayed at 0. Compare 2026-08-14, where
   the same job returned exit 4 and the box suspended 15 minutes later.
   Work item 2b's recovery path was therefore *not* exercised — the session was
   never torn down — so it remains untested against a real failure.

Commit prefix: **HomeServer**.

### Deploying to this host without pushing

The auto-update service hard-resets to `origin/main`, so it cannot test unpushed
work. There is a checkout at **`/home/patate/tech/nix-config`** to use instead:
transfer the commit with `git format-patch -1 HEAD --stdout | ssh
home-server.local "cat > /tmp/x.patch"` then `git am` it there, and have the user
run `just switch` from that directory. Note `scp` is **not** in the sandbox
exclusion list — it fails to resolve `home-server.local` — but piping through
`ssh` works. `just switch` needs sudo, which cannot be run over SSH from here.

## Scope

Self-contained. This doc concerns the **home server only** and needs no context
from any other plan.

**On the nixpkgs line numbers cited below:** they were accurate when written
against the then-locked `nixpkgs` rev, but `flake.lock` advances daily, so treat
them as hints. Grep for the quoted identifier (`autoSuspend`,
`mkRemovedOptionModule`, `stateVersion`) rather than trusting the line number.
The quoted *content* is what matters and has been verified. (The MacBooks have an unrelated auto-update bug with a
superficially similar "the update didn't finish" symptom and a completely
different cause; it shares no code or fix with this one. Nothing here depends on
it.)

## Lesson for future sessions

"Machine not reachable over SSH" was initially read as "machine is powered off"
(and then as "machine is up but its display is dead"). Both were wrong. Before
theorising about *why* a host is unreachable, check `journalctl -b -1` for
`PM: suspend entry` / `Waking up from system sleep state`, and check whether
avahi withdrew the address record. A suspended box looks identical to an absent
one from the network side. The user's physical observation — "I shook the mouse
and nothing happened" — was the decisive evidence, not the network scan.

**From the implementation session (2026-08-15):**

- **A `Monitor` watching this host reports `UNREACHABLE` even when it is up.**
  Monitor commands run *inside* the sandbox, where `.local` mDNS cannot resolve,
  so every check fails with `Could not resolve hostname home-server.local:
  -65563`. Direct `ssh home-server.local …` calls are sandbox-excluded and work.
  This is the same trap that caused the wrong diagnoses above — it fired again,
  and was only caught because the error string was recognised. To wait on this
  host, run the sleep **on the server** (`ssh home-server.local "sleep 600; …"`)
  rather than polling from a monitor.
- **Every real defect this session was found by testing on the box, not by
  evaluating the config.** All six items under "Things this doc got wrong"
  evaluated perfectly and failed at runtime — `226/NAMESPACE`, HTTP 421, a
  missing `gdm.d` path, a stale `.desktop` file. Build success is not evidence
  that a change works.
- **`install -d` is not recursive**, so the feared "chown of the whole download
  directory" was never going to touch the 143 GB inside it. Check what a script
  actually does before treating it as high-risk; the real risk here was Samba's
  `force user` interacting with a directory it no longer owned.
