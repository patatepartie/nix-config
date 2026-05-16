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
- *Diagnose the gap first*: `claude --version` shows the running version; `curl -s https://formulae.brew.sh/api/cask/claude-code.json | jq .version` shows what `formulae.brew.sh` is advertising (this is what the banner compares against); `nix flake metadata --json | jq '.locks.nodes["homebrew-cask"].locked.rev'` shows your locked tap rev; `brew info --cask claude-code | head -1` shows what your locked rev would install. Compare before "fixing" — sometimes the gap is already closed and the banner is just from a long-running session that hasn't been restarted.
