# macOS major upgrade — Nix recovery (MBP2023)

Scope: the Nix/nix-darwin slice of a macOS major upgrade only.
Broader upgrade prep (backups, app compatibility, work tooling) lives in the vault upgrade doc.

Written 2026-09-18 ahead of a Sonoma 14.8.9 upgrade; the machine went to macOS 27.0.1 (Golden Gate) on 2026-10-03 rather than the Tahoe 26.7 originally planned.
Facts below were verified on 2026-10-03 and describe the live setup, so they stay usable for the next major upgrade; re-verify if much time has passed.

**What actually happened on 2026-10-03.** The Nix volume survived untouched — it stayed mounted at `/dev/disk3s7` and none of the recovery procedure below was needed.
The one breakage that did occur was the Command Line Tools: they remained at the Sonoma version, and brew refused to build against them until they were reinstalled.
Expect that to be the likely failure next time too, and see `agents/instructions/troubleshooting.md` → "no bottle available" / "Tier 3 configuration" for the symptom, which misleadingly names a single formula.

## Why this document exists

The expensive failure mode is losing the Nix store, so the facts needed to recover it are recorded here even though the 2026-10-03 upgrade did not need them.

`/nix` on this machine is a **separate APFS volume**, not a directory.
It is mounted by `/etc/synthetic.conf` (which creates the empty `/nix` mountpoint at boot) plus `/Library/LaunchDaemons/org.nixos.darwin-store.plist` (which mounts the volume there).
macOS major upgrades can reset `/etc/synthetic.conf` and `/etc/fstab` — widely reported, though it did not happen here.
If it does, the volume is still on disk and intact but nothing mounts it: `/nix` looks empty and every Nix-installed binary disappears from `PATH`.

That is a mount problem, never data loss.
Do not reinstall Nix as a first response — an unmounted volume and a damaged store look identical from a shell with no `nix` on `PATH`.

## Recovery facts

Keep these readable from another device — you will want them when the terminal has no Nix in `PATH`.

| Fact | Value |
|---|---|
| Nix Store volume UUID | `a49a89f9-6616-47c2-b7a9-17545005150c` |
| Volume device (at time of writing) | `/dev/disk3s7` |
| Volume label | `Nix Store` |
| Nix version | 2.34.8 |
| Installer | Determinate `nix-installer` 0.19.0, at `/nix/nix-installer` |
| Darwin generation when last verified | `system-608-link` (2026-10-03) |

The device node (`disk3s7`) can change; the UUID cannot. Always mount by UUID.

### `/etc/synthetic.conf`

Two lines. The separator on the second line is a **literal tab**, not spaces — with spaces it fails silently.

```
nix
run	private/var/run
```

### `/etc/fstab`

Note: the file has **no trailing newline** on this machine.

```
# nix-installer created volume labelled `Nix Store`
UUID=a49a89f9-6616-47c2-b7a9-17545005150c /nix apfs rw,noauto,nobrowse,suid,owners
```

## Before upgrading

1. Back up (Time Machine or a full clone). This is also the escape hatch if the volume gets into a bad state.
2. Confirm the repo is clean and pushed: `git status` and `git log origin/main..HEAD` (should be empty). The whole machine definition lives in git — that is what makes step 5 below a rebuild rather than a manual reassembly.
3. Note the current darwin generation (`ls /nix/var/nix/profiles/ | grep system-`), so there is a known-good rollback target.

## Expected breakage

Ordered by what actually happened on 2026-10-03, not by what was anticipated. None is data loss.

**1. Command Line Tools need reinstalling.** The only breakage observed, and it blocks `just switch` entirely. A major upgrade leaves the old CLT in place rather than removing it, and brew will not build against it. Fix, which needs a TTY for sudo and so belongs to the user: `sudo rm -rf /Library/Developer/CommandLineTools` then `sudo xcode-select --install`. The plain `xcode-select --install` does nothing while the old directory is still there, so the removal is not optional. Verify with `pkgutil --pkg-info=com.apple.pkg.CLTools_Executables` — the version must match the new OS.

**2. `/nix` disappears.** Anticipated as the most likely failure and it did not occur; the volume stayed mounted. Still worth checking first in the recovery order below, because it is cheap to rule out and everything else depends on it. Fix is to restore the two files and reboot, or the remount one-liner in step 3.

**3. Third-party tools lose their system approvals.** Karabiner-Elements was installed but not running: macOS 27 revoked its driver extension and Input Monitoring grants, and `/Library/LaunchAgents/org.pqrs.karabiner.*` was a 0-byte stub. No `just switch` can fix this — the approvals are user gestures, re-granted in System Settings → General → Login Items & Extensions → Driver Extensions, then Privacy & Security → Input Monitoring. Note the caps-lock and tilde remaps come from nix-darwin's `system.keyboard`, so they return with the switch regardless.

**4. nix-darwin launch daemons unloaded.** Five live in `/Library/LaunchDaemons/`: `org.nixos.darwin-store` (mounts the volume), `org.nixos.nix-daemon`, `org.nixos.activate-system`, `org.nixos.nix-gc`, `org.nixos.nix-auto-update`. A successful `just switch` re-establishes them. They were intact in 2026-10-03.

**5. Dock entries for apps the new OS removed.** macOS 26 deleted Launchpad, so the `persistent-apps` entry for `/System/Applications/Launchpad.app` in `system.nix` rendered as a `?`. Cosmetic, but it means `system.defaults.dock.persistent-apps` is worth re-reading after a major upgrade.

**6. Homebrew wants relinking.** Expected, and the point of the upgrade — bottles for the new OS exist, so formulae stuck on the old one resolve. The 2026-10-03 upgrade took the outdated count from 24 to 6.

## Recovery order

Sequence matters; each step depends on the one before.

1. Reinstall CLT — the removal first, or the install is a no-op:
   `sudo rm -rf /Library/Developer/CommandLineTools`, then `sudo xcode-select --install`.
   It is a multi-GB download behind a GUI dialog, so start it before anything else.

2. Check whether `/nix` is mounted: `mount | grep nix`
   Expect `/dev/diskNsN on /nix (apfs, local, journaled, nobrowse, protect)`.

   If mounted, skip to step 4.

3. If not mounted, try the immediate remount first — no reboot, no file edits:

   ```
   sudo /usr/sbin/diskutil mount -mountPoint /nix A49A89F9-6616-47C2-B7A9-17545005150C
   ```

   That is exactly what `org.nixos.darwin-store.plist` runs.
   If it succeeds, the volume is fine and only the boot-time wiring is broken: restore `/etc/synthetic.conf` and `/etc/fstab` from the values above so it survives the next reboot.

   If the mountpoint itself is missing, restore both files and **reboot** — `/etc/synthetic.conf` only takes effect at boot.

4. Verify the store: `ls /nix/store | head` should list many entries.

5. If `nix` is not on `PATH`: `. /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh`

6. From the repo root, re-apply: `just switch`
   Report any warnings rather than ignoring them.

## Fallback

If the store is genuinely damaged rather than unmounted, reinstalling Nix is viable because the config is reproducible: uninstall via `/nix/nix-installer uninstall`, reinstall, then `just switch`.

Treat this as the last resort, not the plan. Inspect the actual state first — an unmounted volume and a damaged store look similar from a shell with no `nix` in `PATH`, and only the latter justifies a reinstall.

## Rollback

`darwin-rebuild --rollback` returns to the previous generation, or activate a specific one directly:

```
sudo /nix/var/nix/profiles/system-608-link/activate
```

Substitute whichever generation you recorded in "Before upgrading" — the number will have moved on by then.
