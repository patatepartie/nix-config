# Home server NIC transmit timeouts — diagnosis and options

**Status:** open, deliberately not acted on. Diagnosed 2026-10-04.
**Trigger to revisit:** the server drops off the network again, or `NETDEV WATCHDOG` clusters become frequent enough to be annoying.

Not an instruction file.
It records what was established and ruled out, so a future session does not re-derive it.

## Symptom

The server becomes unreachable from the LAN: SSH hangs, `transmission.local` and the cash22 app fail, `home-server.local` stops resolving, and an open RDP session stops accepting input.
The server also loses internet access, so it is the server's network, not the Mac's.
The rest of the machine keeps running; commands issued over SSH can trickle through minutes later.

The "DNS errors" are a consequence, not the cause: `home-server.local` is answered over mDNS by the server itself, so a dead NIC makes the name vanish too.
Pinging `192.168.0.17` (fails) and `192.168.0.1` (succeeds) separates the two quickly.

On 2026-10-04 the network never recovered on its own and a reboot from the local GNOME session fixed it.

## What the kernel logs

```
r8169 0000:01:00.0 enp1s0: NETDEV WATCHDOG: CPU: 3: transmit queue 0 timed out 5328 ms
r8169 0000:01:00.0: can't disable ASPM; OS doesn't have ASPM control
r8169 0000:01:00.0 enp1s0: rtl_rxtx_empty_cond == 0 (loop: 42, delay: 100).
```

The NIC stops transmitting, the kernel's watchdog resets it, and the cycle repeats.
On 2026-10-04 it fired 37 times between 10:49 and 12:09, every one to two minutes from 11:09 on.

Count occurrences across all boots with:

```sh
ssh home-server.local "journalctl _TRANSPORT=kernel --no-pager -o short-iso | grep 'NETDEV WATCHDOG' | cut -c1-10 | sort | uniq -c"
```

`journalctl -k` alone only covers the current boot.

## Hardware

- Dell OptiPlex 3050, BIOS 1.25.0
- NIC: Realtek RTL8168h/8111h (rev 15) at `0000:01:00.0`, behind Intel 200-series root port `00:1c.0`
- Driver: in-kernel `r8169`, firmware `rtl8168h-2_0.0.2 02/26/15`
- Offloads on by default: TSO (`tx-tcp-segmentation`, `tx-tcp6-segmentation`), scatter-gather, tx checksumming

## History

| Period | Kernel | Timeouts |
|---|---|---|
| 2023-10 → 2026-07-12 | 6.1.55 → 6.18.36 | none |
| 2026-07-20, 08-11, 08-23 (×2) | 6.18.38 → 6.18.44 | 4, isolated |
| 2026-09-26 → 09-28 | 6.18.53 | 28, clustered |
| 2026-10-04 | 6.18.54 | 37, clustered, needed a reboot |

## What it correlates with

**Sustained heavy transmit from the server, mostly RDP.**
Every cluster from 2026-09-26 on ends with a gnome-remote-desktop `[RDP] Network or intentional disconnect, stopping session`.
The RDP daemon's journal only starts on 2026-09-18, the day of "HomeServer - Manage the RDP daemon's session autostart", so the clusters began once RDP was in regular use.
RDP streams the desktop as H.264 (AVC444) from the server, which is exactly the direction that times out.
On 2026-10-04 VLC was also playing over the RDP session when the first timeout hit.

The isolated July–August events predate RDP use and were not checked against other traffic; Transmission (a system service since 2026-08-15) is the obvious candidate but unconfirmed.

## Ruled out

- **ASPM.** `lspci -vv` shows `LnkCtl: ASPM Disabled` on both the NIC and root port `00:1c.0`, all L1 substates off, and the root port reports `ASPM not supported`. The firmware's FADT declares ASPM unsupported, so the kernel leaves the BIOS configuration alone (`FADT indicates ASPM is unsupported, using BIOS configuration`). The `can't disable ASPM` line is noise. `pcie_aspm=off` would be a no-op: it selects the mode already in effect.
- **A kernel driver regression at the onset.** The ChangeLogs for 6.18.37 and 6.18.38 contain no `r8169` commits. A change elsewhere in the network stack was not investigated.
- **Suspend.** Disabled in `configuration.nix` (`AllowSuspend = "no"`, `gdm.autoSuspend = false`); the box was awake throughout.
- **Link errors.** `ethtool -S enp1s0` showed zero tx/rx errors, aborts and underruns after the reboot.

`lspci` and `ethtool` are not installed on the server; run them via `nix shell nixpkgs#pciutils` / `nix shell nixpkgs#ethtool`. Reading `LnkCtl` needs root.

## Working hypothesis

The RTL8168h under `r8169` wedges its transmit path under sustained load.
This is a known weakness of the RTL8168 family; the commonly suggested mitigation is disabling TSO and scatter-gather.
That mitigation is folk wisdom from bug reports, not verified for this chip.

## Next steps, if it starts to bother

Ordered cheapest first.

1. **Reproduce on purpose before changing anything.** Because the trigger is load, it should be testable rather than waited for: push sustained traffic from the server to a Mac in bursts with idle gaps, e.g. `ssh home-server.local "head -c 30G /dev/zero" > /dev/null`, while following `journalctl -k -f` on the server for `NETDEV WATCHDOG`. RDP use triggered it within minutes, so 15–30 minutes should be enough. If it does not reproduce, any later "fix" cannot be validated this way. Do it only when someone can reach the machine — a successful reproduction may need a reboot.
2. **Disable offloads at runtime and repeat the test.** On the server: `sudo nix shell nixpkgs#ethtool --command ethtool -K enp1s0 tso off sg off`. This takes effect immediately and does not survive a reboot. If step 1 reproduced and this does not, make it permanent in `hosts/home-server/configuration.nix`.
3. **Alert on recurrence.** A systemd timer that greps the kernel journal for `NETDEV WATCHDOG` and notifies through the Telegram path the auto-update already uses. Each reset briefly restores the link, so the alert gets out, and a single hang is reported long before the box goes dark.
4. **Realtek's out-of-tree `r8168` driver**, packaged in nixpkgs as a kernel module, with `r8169` blacklisted. Not preferred: unofficial driver, and it must keep building against each kernel bump.
5. **A second NIC** — a USB 3 gigabit adapter, or an Intel PCIe card if the 3050's form factor has a slot. The most reliable fix and inexpensive.
