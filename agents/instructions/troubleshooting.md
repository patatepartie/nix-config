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
