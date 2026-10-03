# macOS major upgrade — Nix recovery (MBP2023)

Scope: the Nix/nix-darwin slice of a macOS major upgrade only.
Broader upgrade prep (backups, app compatibility, work tooling) lives in the vault upgrade doc.

Written 2026-09-18, ahead of Sonoma 14.8.9 → Tahoe 26.7.
Facts below were verified on this machine on that date; re-verify if much time has passed.

## Why this document exists

`/nix` on this machine is a **separate APFS volume**, not a directory.
It is mounted by `/etc/synthetic.conf` (which creates the empty `/nix` mountpoint at boot) plus `/Library/LaunchDaemons/org.nixos.darwin-store.plist` (which mounts the volume there).
macOS major upgrades are known to reset `/etc/synthetic.conf` and `/etc/fstab`.
When that happens the volume is still on disk and intact, but nothing mounts it: `/nix` looks empty and every Nix-installed binary disappears from `PATH`.

This is a mount problem, never data loss.
Do not reinstall Nix as a first response.

## Recovery facts

Keep these readable from another device — you will want them when the terminal has no Nix in `PATH`.

| Fact | Value |
|---|---|
| Nix Store volume UUID | `a49a89f9-6616-47c2-b7a9-17545005150c` |
| Volume device (at time of writing) | `/dev/disk3s7` |
| Volume label | `Nix Store` |
| Nix version | 2.34.8 |
| Installer | Determinate `nix-installer` 0.19.0, at `/nix/nix-installer` |
| Current darwin generation | `system-600-link` |

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

Four things, in rough order of likelihood. None is data loss.

**1. `/nix` disappears.** The most probable. Covered above; fix is to restore the two files and reboot.

**2. Command Line Tools need reinstalling.** This machine runs CLT 16.2.0 with no full Xcode. Major upgrades typically invalidate CLT, and Nix needs it. Fix: `xcode-select --install`.

**3. nix-darwin launch daemons unloaded.** Five live in `/Library/LaunchDaemons/`: `org.nixos.darwin-store` (mounts the volume), `org.nixos.nix-daemon`, `org.nixos.activate-system`, `org.nixos.nix-gc`, `org.nixos.nix-auto-update`. A successful `just switch` re-establishes them.

**4. Homebrew wants relinking.** Expected, and the point of the upgrade — once on Tahoe, `arm64_tahoe` bottles exist and the formulae currently stuck on Sonoma resolve.

## Recovery order

Sequence matters; each step depends on the one before.

1. Reinstall CLT: `xcode-select --install`

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
sudo /nix/var/nix/profiles/system-600-link/activate
```

Substitute whichever generation you recorded in "Before upgrading" — the number will have moved on by then.
