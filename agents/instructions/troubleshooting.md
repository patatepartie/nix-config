# Troubleshooting

Recurring issues and how to resolve them. Apply only when the symptoms match exactly — do not generalize to similar-looking errors.

## Homebrew cask install fails: "existing App is different"

**Symptom.** `just switch` aborts with output like:

```
==> Adopting existing App at '/Applications/<App>.app'
Error: It seems the existing App is different from the one being installed.
Installing <cask> has failed!
`brew bundle` failed! 1 Brewfile dependency failed to install
```

**Cause.** An unmanaged copy of the `.app` already exists in `/Applications` (typically a manual install, or a leftover from a cask that was renamed/removed). Homebrew refuses to overwrite an app whose binary doesn't match the one in the cask, and rolls back the install.

**Resolution.** Remove the conflicting `.app(s)` and re-run `just switch`:

```sh
sudo rm -rf /Applications/<App>.app
just switch
```

Some casks bundle multiple apps under one cask name. If the failing cask is known to ship more than one app (e.g. `p4v` ships `p4v.app`, `p4merge.app`, `p4admin.app`), remove all of them.

**Before doing this:** confirm the `.app` is actually unmanaged. The exact `.app` named in the error is the one to remove — do not extend the cleanup to other apps unless they are explicitly listed as bundled by the same cask.

## Homebrew cask upgrade fails: "uninstall script does not exist"

**Symptom.** `just switch` prints an error mid-upgrade but reports success anyway, and the cask ends up not installed:

```
Upgrading <cask>
Upgrading <cask> has failed!
Error: <cask>: uninstall script /Library/Application Support/<vendor>/scripts/uninstall/remove_files.sh does not exist.
==> Purging files for version X.Y.Z of Cask <cask>
==> Upgraded 1 outdated package
<cask> A.B.C -> X.Y.Z
`brew bundle` complete!
```

Despite the "Upgraded" line, `brew info --cask <cask>` shows the old version `(does not exist)` and the app is not actually present.

**Cause.** The cask's uninstall step tries to run a script shipped by the old version's pkg (e.g. a driver kit uninstaller). If a previous failed upgrade or the app's own auto-updater already removed that script, Homebrew can't cleanly uninstall the old version, so the new pkg never installs. Homebrew's receipt DB still records the old version, causing subsequent `just switch` runs to attempt an upgrade (rather than a fresh install) and hit the same error in a loop.

**Resolution.** Remove the cask from `casks.nix`, apply to uninstall it, then restore it to reinstall fresh:

1. Comment out the cask in `hosts/<host>/modules/apps/casks.nix`
2. `just switch` — nix-homebrew's `brew bundle --cleanup` uninstalls it, skipping the missing scripts with warnings
3. Restore the cask in `casks.nix`
4. `just switch` — installs the new version cleanly

The app's user config (e.g. `~/.config/karabiner/`) is not touched by this process. After reinstall, macOS may prompt to re-approve a system extension if the app uses one.

## "Update available! Run: brew upgrade claude-code" banner persists

**Symptom.** Every claude-code shell session prints `Update available! Run: brew upgrade claude-code`, even sessions that were just started, even after `just switch` ran.

**Cause.** The banner is emitted by the claude-code binary itself, not by Homebrew. On startup, claude-code's `PackageManagerAutoUpdater` queries `https://formulae.brew.sh/api/cask/claude-code.json` (Homebrew's metadata API; typically updated shortly after a cask commits to upstream `Homebrew/homebrew-cask` master) and compares the result to the running version. If the API reports a newer version, claude-code prints the banner.

`brew bundle` — the Homebrew-side install path that nix-homebrew drives during `just switch` — is bound to the `homebrew-cask` rev locked in `flake.lock`. Until that rev advances past the new cask version, `brew bundle` won't install the upgrade. So the gap is:

- `formulae.brew.sh` — minutes behind upstream `homebrew-cask` master.
- `flake.lock`'s `homebrew-cask` rev — at most as fresh as the most recent `Update flake inputs` GitHub Action run (daily at 22:00 UTC). See `agents/instructions/working-in-this-repo.md` → "How auto-updates work" for the full pipeline.

Result: when upstream `homebrew-cask` ships a new `claude-code` cask version, the banner appears in every claude-code session until the GitHub Action commits a new `flake.lock`, you pull that commit, and `just switch` (or the per-host auto-update daemon) installs the cask.

Historical note: the cask used to be referenced as `claude-code@latest`, which tracked beta builds with version `"0.0.0"` and made livecheck unhelpful. Commit `f78ccbe` switched to the stable cask (`claude-code`), which carries a real semver — that's the fix the banner has been working against ever since.

**Resolution.**

- *Just this machine, right now*: `just upgrade` (= `nix flake update && just switch`). Updates `flake.lock` locally and rebuilds. Note: this does NOT push, so other hosts are still on the old `flake.lock` until you commit and push.
- *Roll out to every host*: `just upgrade`, then `git add flake.lock && git commit -m "Upgrade flake" && git push`. Each host's auto-update daemon picks the new commit up at its next scheduled run; to skip the wait, run `just switch` on each host manually.
- *Diagnose the gap first*: `agents/scripts/cask-version-gap.sh claude-code` (from the repo root) prints the locked, upstream (`formulae.brew.sh`), and installed versions side by side. If you also want to know whether `flake.lock`'s `homebrew-cask` rev is behind upstream `homebrew-cask` master in general: `agents/scripts/flake-input-freshness.sh homebrew-cask`. Compare before "fixing" — sometimes the gap is already closed and the banner is just from a long-running session that hasn't been restarted.

## Third-party tap package frozen at an old version

**Symptom.** A package from a non-`homebrew/*` tap stays pinned at an old version indefinitely. `brew info <tap>/<pkg>` and `brew list --versions` both report the stale version, while `flake.lock` is at the tap's tip commit and the nightly Action is committing normally. Nothing errors — `just switch` reports success every time.

Observed with `gascity` stuck at 1.1.0 for ~3 months while the tap had shipped 1.4.0; `circleci` was silently affected too.

**Cause.** A mismatch between the `nix-homebrew.taps` attribute key and Homebrew's on-disk tap naming convention.

nix-homebrew uses the attribute key **verbatim** as a path — it splits on `/` only to get the namespace, then copies the tap to that exact path (`setupTaps` in nix-homebrew's `modules/default.nix`). There is no normalization of the second segment. But brew resolves a tap to `Library/Taps/<owner>/homebrew-<name>`. So a key written as:

```nix
"gastownhall/gascity" = homebrew-gascity;      # WRONG
```

creates `Library/Taps/gastownhall/gascity`, which **brew never reads**. Brew instead falls back to `Library/Taps/gastownhall/homebrew-gascity` — typically a hand-made `brew tap` clone predating the nix declaration, which nothing updates.

The two directories sit side by side, so the failure is invisible: the nix-managed copy refreshes on every `just switch` at a path nothing consults, while brew serves formulae from the frozen clone.

**Diagnosis.** List the tap's namespace directory:

```sh
ls -la /opt/homebrew/Library/Taps/<owner>/
```

Two entries (`<name>` and `homebrew-<name>`) confirms it. The mtimes are the tell: the correctly-named tap carries the timestamp of the last `just switch`, the vestigial one is stuck in the past. Compare against `homebrew/` in the same tree, which is always correct.

**Resolution.** Use the full repo name — including the `homebrew-` prefix — as the `taps` key in `hosts/<host>/default.nix`:

```nix
"gastownhall/homebrew-gascity" = homebrew-gascity;
```

Then `just switch` and verify with `brew list --versions <pkg>`.

**Do not apply the same prefix to `trust.taps`.** The two options are asymmetric on purpose. `taps` keys are filesystem paths and need the prefix; `trust.taps` entries are passed unmodified to `brew trust --tap`, which expects brew's short `owner/name` form. Leave `trust.taps = [ "gastownhall/gascity" ... ]` alone.

Once the key is fixed, the vestigial directory is orphaned and safe to remove (`sudo rm -rf`, since nix-homebrew created it root-owned). Removing it is optional tidying, not part of the fix.

**When adding any new third-party tap**, write the key as `<owner>/homebrew-<name>` from the start. Only the `homebrew/*` taps look "unprefixed", and that is because their repos are genuinely named `homebrew-core` / `homebrew-cask` — those keys already carry the prefix.

## `just switch` fails: formula "unreadable" / unknown DSL keyword or method

**Symptom.** `just switch` fails during `brew bundle`, with a formula reported as unreadable:

```
Warning: 'openssl@3' formula is unreadable: homebrew/core/openssl@3: unknown keyword: :overwrite
Upgrading awscli has failed!
`brew bundle` failed! 2 Brewfile dependencies failed to install
error: recipe `switch` failed on line 11 with exit code 1
```

Other forms of the same failure: `undefined local variable or method 'configure_clang_system'`, or any `unknown keyword:` / `undefined ... method` naming an InstallSteps DSL feature. The named formula is often a low-level dependency (`openssl@3`), so the packages that visibly fail are unrelated ones that depend on it.

**Cause.** Homebrew is migrating `homebrew-core` formulae to the declarative InstallSteps DSL and keeps adding methods and keywords to it. The nightly `nix flake update` Action advances `homebrew-core`/`homebrew-cask`, but **cannot** advance `brew` itself — `brew-src` is a hardcoded tag in `flake.nix` (see "Watch for pinned inputs" in `working-in-this-repo.md`). When a tap commit uses a DSL feature the pinned brew lacks, the formula fails to parse.

There is no version contract to catch this: `homebrew-core` declares no minimum brew version, so the only symptom is a parse failure. (`compatibility_version` exists in brew but concerns dependency-upgrade minimisation, not DSL gating — it is not relevant here.)

**The pin is deliberate and load-bearing. Do not remove it, and do not make it auto-track brew's latest tag** — auto-tracking latest is equivalent to having no pin, which is the state that caused continuous breakage. Upstream `nix-homebrew` is itself still on an older `brew-src` than this repo, so waiting for upstream to catch up does not resolve it either (tried; the gap did not close the next day). Manually bumping the pin is the accepted cost.

**Expect recurrence, and expect the pin to persist.** This is not a one-off to be cleared. Each bump fixes the formula that broke today and buys time until `homebrew-core` adopts the next DSL feature; it is not progress toward removing the pin. Treat a recurrence as routine maintenance, not as evidence that the previous fix was wrong.

**Resolution.** Bump the pin to the brew version that adds the missing feature.

1. Identify the failing keyword/method from the error (e.g. `:overwrite`).
2. Find the newest brew tag: `curl -s https://api.github.com/repos/Homebrew/brew/releases/latest | grep tag_name`
3. **Verify before bumping** that the candidate version actually adds the feature — do not assume newest is sufficient:
   ```sh
   curl -s https://raw.githubusercontent.com/Homebrew/brew/<TAG>/Library/Homebrew/install_steps.rb | grep -n -A6 "def <method>"
   ```
   For the `openssl@3` case: `def symlink` gained an `overwrite:` parameter in 6.0.15.

   Most InstallSteps DSL features live in `install_steps.rb`, but do not assume it. If that grep finds nothing, search the whole tree rather than concluding the version is wrong — the method may live elsewhere or be inherited:
   ```sh
   grep -rn "def <method>\|<keyword>:" $(readlink /opt/homebrew/Library/Homebrew)/
   ```
   That greps the *currently installed* brew. To check a candidate tag before bumping, clone shallowly to a temp dir and grep that, or browse the tag on GitHub. Only conclude the feature is absent after searching the whole `Library/Homebrew/` tree.
4. Edit the `nix-homebrew.inputs.brew-src.url` tag in `flake.nix` and update the comment above it to record the new keyword.
5. Re-lock **only** that input, so the nightly Action's other updates are not swept in:
   ```sh
   nix flake lock --update-input nix-homebrew/brew-src
   ```
   Confirm it stayed scoped: `git diff flake.lock` should touch only the `brew-src` node. If other inputs moved, you ran a full `nix flake update` by mistake — revert and redo.
6. `just switch`, then confirm the previously-failing formula reads: `brew info --formula <name>`. Also check that the packages which failed actually upgraded — `brew bundle` reports success even when a formula was merely skipped.

If `just switch` still fails naming a *different* keyword or formula, repeat from step 1; each missing DSL feature may have landed in a different brew release.

If the newest brew tag does **not** yet contain the needed method, brew has not shipped it — wait for the next brew release rather than pinning the taps backwards.

**Trap: the store path name lies about the version.** `nix-homebrew`'s `flake.nix` derives the derivation name from its *own* `flake.lock` (`brewVersion = flakeLock.nodes.brew-src.original.ref`) while using the overridden `brew-src` contents. So an overridden brew still appears at a path like `/nix/store/...-brew-6.0.13-patched`, regardless of the tag actually in use. Never use that path name as evidence of the running version — check the contents instead:

```sh
grep -n -A3 "def symlink" $(readlink /opt/homebrew/Library/Homebrew)/install_steps.rb
```

**Unrelated noise.** `continuation.bundle: warning: callcc is obsolete; use Fiber instead` appears throughout this output. It comes from loading a Ruby 4.0 extension inside the nix-built brew; nothing calls `callcc`. It is harmless and is not a symptom of this or any other failure.

## Auto-update reports success but part of the config was never applied (macOS)

**Symptom.** The daily auto-update appears to have run, but changes are missing — most visibly, a later manual `just switch` upgrades Homebrew packages that "should" already have been updated. `sudo launchctl list | grep nix-auto-update` shows last exit status **0**, and no Telegram alert was sent. The tell is in the log:

```sh
tail -3 /var/log/nix-auto-update.log
```

A complete run ends with `Update complete`. A truncated run's last line is:

```
reloading service org.nixos.nix-auto-update
```

**Cause.** nix-darwin's activation reloads any launchd service whose plist changed, via `launchctl unload` then `load -w` (`nix-darwin/modules/system/launchd.nix:18-32`). `org.nixos.nix-auto-update` is itself such a service, and the running update script *is* that job's process — so activation kills the script that started it. The Nix generation lands (the system switch completes first), but everything after the kill is skipped: the Homebrew phase and home-manager activation.

Two signals mislead here, and both are expected:
- **Exit status 0** is meaningless: `launchctl load`/`unload` always return 0 except on usage errors, so launchd records the kill as a normal stop.
- **No notification.** The script is killed by a signal; its `trap ... ERR` does not fire on signal delivery (and SIGKILL cannot be trapped at all), so no `notify_failure` runs. Silence is not evidence of success.

This is intermittent — it only fires when the plist changes, which happens whenever `autoUpdateScript`'s derivation closure changes, not only when `auto-update.nix` is edited. Observed roughly monthly.

**Resolution.** **Fixed and verified on both MacBooks (2026-08-15).** The launchd job is now a thin launcher that detaches the real work (fork → `setsid` → `exec`, with a pipe handshake so the parent cannot exit before the child detaches) and exits immediately, so `unload` has nothing to kill. A marker file at `/var/lib/nix-auto-update/run-in-progress` records the run id, and the *next* run reports a previous run that died without notifying.

If you see this symptom again, first check the plist actually points at the current launcher (`plutil -p /Library/LaunchDaemons/org.nixos.nix-auto-update.plist`) — on the 2018 the fix had been committed but never applied, so the host was still running the old script. The diagnosis, the rejected `AbandonProcessGroup` approach (it governs orphaned children, not the job's own process — do not re-propose it), and both verification records are in `agents/docs/mbp-auto-update-self-kill.md`.

## Home server unreachable after an auto-update; desktop session gone

**Symptom.** The home server stops answering SSH and mDNS, often hours after a daily update, and needs a physical power-button press to come back. On return it shows the GDM login screen (unanswerable — no keyboard is attached). Shaking the attached mouse produces no display activity. `nix-auto-update.service` failed with exit code 1 and `switch-to-configuration` returned **4**; a Telegram alert *was* sent.

**Before assuming the machine is down:** a `Could not resolve hostname home-server.local` from a sandboxed Bash call is usually the sandbox, not the network — mDNS is unavailable there, and adding flags to the `ssh` invocation triggers it. Retry the plain documented form (see "SSH to home-server.local" in `working-in-this-repo.md`) before concluding anything.

**Cause.** Two separate things, in sequence:

1. The update restarts user units whose store paths changed. `switch-to-configuration` re-execs itself as the logged-in user and stops ~28 user units *including `dbus-broker.service`*, then cannot restart them because it just killed the bus it was using (`Failed to process dbus messages while waiting for jobs` → `warning: user activation for patate failed` → exit 4). The GNOME session dies. GDM is deliberately **not** restarted (it appears in the "NOT restarting the following changed units" list), so nothing renders to the screen at all.
2. A **greeter** session starts, and ~15 minutes later *its* power daemon suspends the machine to RAM: `suspend requested from client PID … ('.gsd-power-wrap') (unit user@60578.service)` → `PM: suspend entry (deep)`. avahi withdraws the address record, and the box vanishes from the network until physically woken.

UID 60578 is `gdm-greeter`, **not** the logged-in user. Anti-sleep dconf settings under `home.nix` apply to `patate` and are never seen by the greeter — which is why they do not prevent this.

**Diagnosis.** A suspended machine is indistinguishable from a powered-off one over the network. Confirm from the previous boot's journal rather than guessing:

```sh
ssh home-server.local journalctl -b -1 --no-pager | grep -iE 'PM: suspend entry|Waking up from system sleep|suspend requested'
```

`PM: suspend entry (deep)` followed later by `Waking up from system sleep state S3` means it slept. A clean `shutdown`/`reboot` pair in `last -x` immediately before a boot is consistent with a *graceful* power-button press, not a power cut.

## Touch ID for sudo stops working after a macOS update (Intel/T2)

**Symptom.** sudo asks for a password instead of offering Touch ID — an **OS modal prompting for the password**, not a silent terminal prompt. It had been working on this machine, and still works on the other MacBook. Config is unchanged. Observed on the 2018 MBP after the macOS 15.7.9 update (2026-08-02); Touch ID for *unlock* and Apple Pay still work fine.

**Do not chase these — all were checked and are correct:** `security.pam.services.sudo_local.touchIdAuth` / `.reattach` in `hosts/<host>/modules/system.nix`, the generated `/etc/pam.d/sudo_local`, `/etc/pam.d/sudo` (the OS update rewrites all of `/etc/pam.d/`, but the `auth include sudo_local` line survives, and `sudo_local` is a nix symlink it cannot touch), Touch ID hardware/enrollment (`bioutil -r`, `bioutil -c`), and `biometrickitd`.

**Cause.** macOS now enforces Library Validation on `sudo`, which is a platform binary. `pam_reattach.so` is **completely unsigned**, so the kernel refuses to map it into `sudo`. Without the reattach, sudo stays in the background bootstrap namespace and Touch ID cannot present its UI, so PAM falls through to password auth.

Confirm with (note the absolute path — see the `log` gotcha below):

```sh
/usr/bin/log show --last 5m --predicate 'eventMessage CONTAINS[c] "pam_reattach"' --style compact | grep Rejecting
```

```
Library Validation failed: Rejecting '/nix/store/…/pam_reattach.so' (Team ID: none, platform: no)
for process 'sudo' (Team ID: N/A, platform: yes), reason: mapped file has no cdhash, completely unsigned?
```

The follow-on error in the same run is the real failure: `LACopyResultOfPolicyEvaluation -> (null), Error … Code=-1004 "User interaction is required."` — with `BiometryType=1` and `AvailableMechanisms=(1)`, i.e. Touch ID is present and available but cannot show its UI.

**Resolution.** None available. Both dead ends below were tested on the machine and **failed** — do not re-propose either:

- **Ad-hoc signing** (`codesign -s - pam_reattach.so`). Gives the module a cdhash, and the kernel error does change to `mapping process is a platform binary, but mapped file is not` — but sudo still falls back to a password. A platform binary needs more than an ad-hoc signature.
- **Switching to Homebrew's `pam-reattach`.** Its bottle is unsigned too (`code object is not signed at all`, verified by unpacking the bottle), the formula has no `codesign` step, and Intel bottles stop at `sonoma` while Apple Silicon has `sequoia`/`tahoe`. Identical failure, plus a needless dependency. Never tried in this repo's history, so it looks unexplored — it isn't.

A real fix needs a Developer ID signature, which only upstream can provide. No issue exists in [pam_reattach](https://github.com/fabianishere/pam_reattach) or nixpkgs as of 2026-08-15. Until then sudo in tmux prompts for a password. Dropping `reattach = true` does **not** help: it removes the module whose absence causes the `-1004`, and the tmux case is exactly the one that needs it.

The other MacBook is unaffected only because it is on an older macOS major version; expect the same break when it updates.

**Gotcha that wasted time here:** a zsh function/alias shadows `log`, so a bare `log show …` fails with `(eval):log:1: too many arguments` — which looks exactly like "the log is empty" and led to a wrong "no biometric errors" conclusion. Always use `/usr/bin/log`. Also, `log show` returns nothing useful from inside the Bash sandbox; run it with `dangerouslyDisableSandbox: true`.

**Resolution.** No fix is deployed yet. The verified fix for the suspend is `services.displayManager.gdm.autoSuspend = false` (it writes the anti-sleep keys into the greeter's own dconf profile), with `systemd.sleep.settings.Sleep.AllowSuspend = "no"` as a system-wide backstop. Note `AllowSuspend` belongs in `sleep.conf`, **not** `logind.conf`, where it silently does nothing. Full plan, including decoupling Transmission from the desktop session, in `agents/docs/home-server-session-decoupling.md`.

## `als` does not list an alias you know exists

**Symptom.** `als <keyword>` returns nothing, or omits an alias that is definitely declared in this repo. Two distinct causes, with the same surface symptom.

**Cause 1 — the shell is stale.** `als` is oh-my-zsh's `aliases` plugin: a wrapper that pipes the output of the `alias` builtin into `plugins/aliases/cheatsheet.py`. It reads the *running shell's* alias table and never touches any file, so an alias added by a `just switch` is invisible to every shell that was already open. Confirm with `alias | grep <name>`: empty in the old shell, present in a new one. Resolution: open a new shell (or re-source the profile). Nothing to fix in the config.

**Cause 2 — it is a function, not an alias.** `als` can only ever see real `alias` entries. Anything defined as a shell function is structurally invisible to it, no matter how alias-like it looks. The oh-my-zsh **tmux plugin is the trap here**: its README documents `ta`, `tad`, `to`, `ts`, `tkss` as aliases, but `tmux.plugin.zsh` builds them with `_build_tmux_alias`, which does `eval "function $1 { … }"` — functions, despite the helper's name. Only `tksv`, `tl`, `tmuxconf` are declared with `alias`, and only those three appear in `als` output. This is an upstream README inaccuracy, not a local misconfiguration — there is no knob to change it.

`als tmux` is doubly unhelpful for a second reason: the plugin also does `alias tmux=_zsh_tmux_plugin_run` and `alias tds=_tmux_directory_session`, so the surviving entries point at opaque function names rather than any text containing `tmux attach`.

**Before concluding a plugin was removed,** read the `plugins = [ … ]` array rather than grepping for the plugin name — a grep for `tmux` in `home.nix` returns dozens of resurrect/continuum hits and buries the one line that matters. All three hosts do list `tmux`: `hosts/2023-macbook-pro/home.nix` has the long list ending `"mise" "tmux" "gascity"`, and both `hosts/2018-macbook-pro/home.nix` and `hosts/home-server/home.nix` have `[ "aliases" "git" "tmux" ]`.

To find things `als` cannot show:

```sh
whence -v <name>          # says whether it is an alias, function, or binary
functions <name>          # prints a function's body
functions | grep -B5 'tmux attach'   # search function bodies by content
```

## An activation script silently never runs (nix-darwin)

**Symptom.** A `system.activationScripts.<name>` block is declared, `just switch` succeeds, and the thing it was supposed to do never happens. No error, no warning. `nix eval` on the attribute returns the script text, which makes it look correctly wired.

**Cause.** nix-darwin's `modules/system/activation-scripts.nix` builds the final script by interpolating a **fixed list of known attribute names** (`preActivation`, `checks`, `etc`, `homebrew`, `postActivation`, …). It does not iterate the attrset. A custom name is therefore evaluated, type-checked, and dropped.

This is easy to reach by accident: nix-darwin removed `preUserActivation` / `postUserActivation` / `extraUserActivation` when activation moved to running entirely as root. Those removed names trigger an assertion, so the tempting fix is to rename the block to something custom — which silences the error *and* the functionality. That happened here in "Update flake" (July 2025) and went unnoticed for 13 months.

**Resolution.** Never invent an attribute name.

- User-scoped work (anything under `$HOME` — editor extensions, per-user caches) belongs in home-manager: `home.activation.<name> = lib.hm.dag.entryAfter [ "writeBoundary" ] ''…''`. It runs as the user, so no `sudo -u` and no username literal. `writeBoundary` is required for anything with side effects.
- System-scoped work goes in `system.activationScripts.postActivation.text`. Fragments from multiple modules merge. It runs as root; `config.system.primaryUser` and `config.system.primaryUserHome` are available rather than a hardcoded name.

Homebrew's bundle runs before `postActivation`, and home-manager activation runs inside it, so both options are safely ordered after `brew` has installed and upgraded packages.

**Verifying a block actually runs.** Grep the built output — a dropped block is *absent*, which is exactly the signal the silent failure hides:

```sh
nix build .#darwinConfigurations.<host>.config.home-manager.users.<user>.home.activationPackage \
  --no-link --print-out-paths
grep -n '<a string from your block>' <that-path>/activate
```

home-manager blocks additionally honour `DRY_RUN` via the `run` helper, so they can be exercised without side effects:

```sh
DRY_RUN=1 <that-path>/activate
```

`system.activationScripts` has no equivalent dry run; grepping the built `activate` is the only check.

## `code --install-extension github.copilot` fails the switch

**Symptom.** VS Code extension installation aborts activation with:

```
Error while installing extension github.copilot-chat: Extension 'github.copilot-chat'
is a built-in extension with version 'X' and cannot be downgraded to version 'Y'.
```

**Cause.** `github.copilot` is deprecated as a standalone package. VS Code redirects the request to `GitHub.copilot-chat`, resolves the version compatible with the *deprecated* package, and then refuses to downgrade the copy it now ships built in. Confirm with `code --install-extension github.copilot --log trace`, which logs the redirect explicitly.

Copilot is not missing when this happens — it ships inside the VS Code app bundle (`/Applications/Visual Studio Code.app/Contents/Resources/app/extensions/copilot/`). Check the real state with `code --list-extensions --show-versions`; a bundled extension will not appear there.

**Resolution.** Remove `github.copilot` from the managed extension list. Do not suppress the error with `|| true`: the failure is a correct signal that a list entry is obsolete, and hiding it is what let this sit unnoticed.

Note `code --install-extension` exits non-zero on failure, but piping it (e.g. `| tail`) reports the pipe's status instead. Redirect to a file and check `$?` when testing by hand.

## Chrome will not start / a stuck headless Playwright browser

**Symptom.** Clicking Google Chrome does nothing — no window, no error. Often first noticed after a Chrome update that forced a quit.

**Cause.** `playwright-cli` defaults to the `chrome` channel, which drives `/Applications/Google Chrome.app` by design. It launches it with `--headless --no-startup-window`, and macOS LaunchServices then hands your click to that running instance, which has no window to show. `playwright-cli` keeps sessions alive in a background daemon between commands, so one can outlive its caller by days.

In `playwright-core`, an unspecified browser resolves to browserName `chromium` but channel `chrome`, and the channel wins:

```js
if (!browserName) {
  browserName = "chromium";
  if (browser.launchOptions.channel === void 0)
    browser.launchOptions.channel = "chrome";
}
```

Identify it by the temp profile in the command line:

```sh
ps aux | grep playwright_chromiumdev_profile | grep -v grep
```

**Resolution.** Run `playwright-cli kill-all` first, then `pkill -f playwright_chromiumdev_profile` and `pkill -f cliDaemon.js`. `kill-all` alone is not enough: it matches only daemon patterns, not the browser processes those daemons spawned, so an orphaned browser survives it and keeps blocking Chrome (upstream issue #388, closed without a fix). Then start Chrome normally.

**Prevention.** Always pass `--browser=chromium`, which selects the separate Chrome for Testing build under `~/Library/Caches/ms-playwright/` instead of the user's Chrome. The `playwright-cli` skill in `~/Tech/agent-config/skills/` carries this and the rest of the usage rules.

`chromium` is undocumented — `--help` and the CLI's own bundled skill list only `chrome`, `firefox`, `webkit`, `msedge` — but it is accepted, and maps to the `chrome-for-testing` channel.

Neither a config file nor an env var can replace the flag. `.playwright/cli.config.json` cannot clear the default channel (upstream issue #320), and `PLAYWRIGHT_MCP_BROWSER` applies only to sessions whose own caller had it set, since each session spawns its own daemon.

**The browser must be installed** or `--browser=chromium` fails hard, with no auto-download and no fallback. `hosts/2023-macbook-pro/modules/apps/playwright.nix` installs it on every activation via `home.activation.installPlaywrightBrowsers`:

```sh
playwright-cli install-browser chromium
```

It is a fast no-op when the right build is present, and resolves the required revision from the installed CLI, so a Homebrew bump of `playwright-cli` is picked up automatically on the next `just switch`. Verify the build is there — the path should be under `~/Library/Caches/ms-playwright/`, never `/Applications`:

```sh
ls ~/Library/Caches/ms-playwright/ | grep chromium
```

**Sessions leak by design.** `playwright-cli open` spawns a detached daemon that holds its browser until something sends `close`, and an agent that opens a session and exits never sends it (upstream issue #460, open). Close every session you open, including on failure.

Note this repo manages the `playwright-cli` CLI only. The Claude Code Playwright *plugin* (`npx @playwright/mcp`) was a second, independent entry point that could start the same fallback browser; it was uninstalled deliberately. If Chrome starts getting hijacked again, check whether a plugin or MCP server reintroduced it.

## `herdr server` shows high cumulative CPU

**Symptom.** `ps aux -r` ranks `herdr server` near the top by CPU time — hundreds of minutes accumulated over a few days, more than WindowServer. Instantaneous CPU sits around 9-18%.

**Cause.** Expected, given the working set. herdr holds one live PTY per pane, each paired with a tokio worker thread; a session with 23 workspaces and ~84 tabs runs ~108 PTY threads. The cost scales with how much output those panes produce, not with pane count alone — an idle pane is nearly free.

A `sample <pid>` profile confirms the shape: the main thread spends the overwhelming majority of its samples parked in `tokio::runtime::park` (measured 5746 parked vs 158 working, ~2.7% active), with the working portion in `render_retained_pty_update_and_stream` — reading dirty terminal cells via Ghostty, serializing frames with bincode, and streaming them to the client. That is the render path doing real work proportional to real output, not a busy-wait.

`sample` reports every thread at the full sample count regardless of activity, because blocked threads still get sampled. Read the *thread count* and the parked-vs-working split in the call graph, not the per-thread totals.

**Resolution.** None needed unless it grows out of proportion to the working set. To reduce it, close panes you are not using — the load is roughly linear in actively-producing panes.

Escalate only if the profile changes shape: the main thread no longer dominated by `park`, or CPU staying high with no pane producing output. Neither was true as of 2026-09-06.

## gascity burns CPU; `gc doctor` reports stale scheduled orders

**Symptom.** Activity Monitor shows sustained high CPU that tracks gascity activity rather than a specific busy process. `gc doctor` reports `✗ order-firing-current — scheduled orders are stale`. `gc` feels sluggish. A single `ps aux -r` snapshot often shows nothing: `gc supervisor run` sits near 1% CPU, which reads as innocent and is misleading.

**Cause.** Upstream <https://github.com/gastownhall/gascity/issues/5164>. gascity's `version_compat` preflight gate requires an *exact* string match between the installed `bd` CLI version and the beads library version `gc` was compiled against. When `bd` is newer but semver-compatible the gate fails silently, and gascity falls back to BdStore — fork-per-operation mode. The cost lands in a storm of short-lived `bd` subprocesses (upstream measured 170+ forks/s against a 100/s threshold), not in any one long-lived process, which is exactly why a point-in-time `ps` misses it.

The skew is structural, not accidental: the Homebrew formula declares an unversioned `depends_on "beads"`, so `beads` always installs at its latest release and drifts ahead of the version `gc`'s `go.mod` pins. Every new beads release re-opens the gap.

Check for the skew with `brew list --versions gascity beads` plus `bd --version`. Note that `gc` exposes no way to read the gate's verdict or the linked beads version — `gc --version` does not exist (`gc version` prints only gascity's own version), and no `gc doctor` check reports the active store mode. Adding that visibility is part of the same upstream issue, so until it ships the stale-orders check is the most reliable local tell.

**Resolution.** None available yet — wait for an upstream release.

The fix (PR #5252, merged 2026-08-30) relaxes the gate to accept a same-major `bd` at or above the library version. It is **not in any released tag**: the latest release, v1.4.1, shipped 2026-08-15, two weeks before the merge. The formula tracks stable tags and declares no `head` spec, so there is no `--HEAD` install path, and gascity is not Nix-packaged here — nothing in this repo can pull the fix forward. `GC_BEADS_FORCE_FALLBACK` is not a workaround; it forces the slow path rather than avoiding it.

When a release after v1.4.1 appears, `just switch` picks it up through the normal tap path once `flake.lock`'s tap rev advances. Confirm the fix landed by checking that `gc doctor` no longer reports stale orders. Do not chase this by pinning or hand-installing beads at an older version: the redundant `"beads"` entry in `hosts/2023-macbook-pro/modules/apps/brews.nix` is a deliberate transitive-dep marker, and downgrading it would fight the formula on every update.

## New Ghostty tabs fail to launch after changing or removing a `command` setting

**Symptom.** Every new Ghostty tab and window dies immediately. The error names whatever the OLD `command` pointed at, in one of two forms:

```
bash: /nix/store/<hash>-ghostty-tab-init: No such file or directory
Ghostty failed to launch the requested command
```

```
zsh:1: command not found: tmux
Ghostty failed to launch the requested command:
/usr/bin/login -flp <user> /bin/bash --noprofile --norc -c exec -l zsh -l -c 'tmux new-session -As main'
```

Read the command in that second line: if it is not what the current config says, this is the entry you want.

**Cause.** The running Ghostty holds the previous config in memory. Ghostty reads `command` when launching a surface, not per keystroke, so the stale value survives until the process restarts — and the thing it names is now gone, either because `just switch` garbage-collected the store path, or because the same change removed the binary it invoked.

**Both machines hit this.** The 2023 MacBook on 2026-08-29 (GC'd `ghosttyTabInitScript` path) and the 2018 on 2026-09-06 (tmux removed in the same commit as the `command` that ran it). Whenever a switch changes `programs.ghostty.settings.command`, expect it and say so before applying — a full relaunch is a two-second fix only if you know that is what it is.

**Beware of what "restart Ghostty" means here.** Closing every window is not enough, and neither is exiting whatever was running inside them: the Ghostty process survives and keeps the stale value. That is exactly how the 2018 case presented — the user exited their tmux sessions, the windows went away, and the next launch still used the old command.

Nothing is wrong on disk. `cat ~/.config/ghostty/config` already shows the correct contents, and `ls -l ~/.config/ghostty/config` points at the current generation. Do not re-run `just switch` or go hunting for a broken store path — neither is the problem.

**Resolution.** Quit Ghostty fully with `Cmd+Q` and relaunch. Closing the window is not enough. `Cmd+Shift+,` reload-config may also work, but `command` is among the settings least likely to be re-read on reload, so the relaunch is the reliable path.

This is **transition-only**: once Ghostty restarts against a config with no `command` at all, there is nothing stale left to point anywhere, and it cannot recur.

If every window dies on launch and you have no working terminal left, use **Terminal.app** to check `cat ~/.config/ghostty/config` and to run `killall Ghostty`.

**One thing to know before quitting.** `Cmd+Q` ends every Claude session running in a Ghostty tab, so commit in-flight work first. On a machine where herdr or tmux holds the sessions, they survive independently of the client and come back on reattach.
