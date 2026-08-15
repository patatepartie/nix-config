# Home server: auto-update kills the GNOME session, box then suspends — diagnosis and plan

**Status:** diagnosed 2026-08-14, refined 2026-08-15. Not yet implemented.
**Affects:** `hosts/home-server/` (`configuration.nix`, `home.nix`, `auto-update.nix`).
**User impact:** machine becomes **unreachable over the network for hours** and
needs a physical power-button press to come back. Running apps and in-flight
torrent downloads are lost.

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
  so files written by the daemon will not match unless you set
  `services.transmission.user`/`group` or arrange group-writable permissions
  (`downloadDirPermissions`). Note the module applies heavy systemd sandboxing
  (`RootDirectory`, `BindPaths`, `ProtectHome = "read-only"`) that assumes a
  dedicated low-privilege user; running it as `patate` weakens that. Decide
  deliberately.
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

Remaining open question: migrating existing torrent state out of
`~/.config/transmission/`. Firewall currently
`networking.firewall.allowedTCPPorts = [ 1883 3389 51413 ]` — 51413 is the BT
peer port; RPC 9091 is not open and should only be opened deliberately.

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
#    403 = listening, but rpc-whitelist is rejecting you (see required settings).
#    000/refused = not listening, or firewall/rpc-bind-address wrong.
#    Distinguishing these three tells you which layer to fix.

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

#    and the greeter's dconf profile (the primary fix):
ssh ... cat /etc/dconf/db/gdm.d/*  2>/dev/null | grep -A4 'plugins/power'
#    expect sleep-inactive-ac-type='nothing' and sleep-inactive-ac-timeout=0

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

## Work item 2b (optional) — recover the display after a teardown

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

1. **Work item 2** (system-wide suspend off) — small, verified, and the only
   change that stops the machine vanishing from the network. Highest immediate
   relief; do this first.
2. **Work item 1** (Transmission as a system service) — the structural fix;
   makes the desktop session disposable so a teardown costs nothing that matters.
3. **Work item 2b** (restart the display manager on activation failure) —
   optional polish once the box no longer disappears.
4. Re-run an update and confirm a session teardown is now merely cosmetic: the
   box stays reachable over SSH and downloads keep running.

Commit prefix: **HomeServer**.

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
