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
