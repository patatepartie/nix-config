# gascity/beads version_compat gate — diagnosis and options

**Status:** open, waiting on upstream. Diagnosed 2026-08-09/11.
**Trigger to revisit:** [gascity#5164](https://github.com/gastownhall/gascity/issues/5164) resolving, or a gascity release that repins beads.

Not an instruction file. Nothing here needs doing today; it records why the CPU
load exists and which options were rejected, so a future session does not
re-derive it.

## Symptom

`gc supervisor run` and `dolt sql-server` burn noticeable CPU while the city is
idle. `ps` lifetime-average %CPU is misleading here (it showed 91% for the
supervisor); measure consumed CPU time instead. Over one 6.5h idle run:

| Process | CPU time | ≈ share of one core |
|---|---|---|
| `dolt sql-server` | 58 min | ~15% |
| `gc supervisor run` | 15 min | ~4% |

Dolt is the consumer; `gc` is the cause. Other observed markers:

- ~300 distinct `bd`/`gc` PIDs spawned per 30s (~10/s)
- 500–640 sockets in `TIME_WAIT` on the Dolt port, ~0 `ESTABLISHED`
- `hq` journal growing ~65 KB/s (~5.6 GB/day) with no agent doing work

## Root cause

`gc doctor` reports:

```
⚠ beads-store — beads store running on BdStore fallback (fork-per-op;
  gate=version_compat): bd version differs from linked beads library version
```

gascity's native (in-process) Dolt store requires its compiled-in beads library
version to **exactly string-match** the standalone `bd` binary — not a semver
range, so a *newer* `bd` fails just as hard as an older one. On mismatch it
falls back to `BdStore`, which forks a `bd` process per operation; each fork
opens a fresh TCP connection to Dolt and exits. That churn is the CPU load.

gascity 1.4.0 `go.mod` links `github.com/steveyegge/beads v1.1.0`
(`steveyegge/beads` is the historical module path for `gastownhall/beads`).
Installed `bd` is 1.1.2 — both are the latest Homebrew releases.

Structural cause: the tap's `Formula/gascity.rb` declares a bare
`depends_on "beads"` with no version constraint, so Homebrew always installs the
newest beads regardless of what `gc` was built against. beads ships faster than
gascity, so they drift apart every cycle. Recurred across at least three version
pairs: [#3632](https://github.com/gastownhall/gascity/issues/3632),
[#3946](https://github.com/gastownhall/gascity/issues/3946),
[#5164](https://github.com/gastownhall/gascity/issues/5164). The precedent fix
was upstream repinning the release branch (PR #4226 for #3946), not user action.

Related upstream: [#2463](https://github.com/gastownhall/gascity/issues/2463)
(idle bd subprocess churn, open), [#3977](https://github.com/gastownhall/gascity/issues/3977)
(linked beads version not observable from any `gc` surface).

## Ruled out

- **`gc doctor --fix`** — cannot repair this gate. `BeadsStoreCheck` hardcodes
  `CanFix() == false`; the warning's "repair the named preflight gate" hint has
  no implementation behind it.
- **Downgrading `bd` to 1.1.0** — would satisfy the gate, but a newer `bd` may
  have migrated the Dolt schema forward, and the store has been running under
  1.1.2. Rejected as too risky (2026-08-11).
- **Pinning the Homebrew formula** — incompatible with this setup, not merely
  discouraged. `homebrew.onActivation.upgrade = true` re-runs `brew upgrade` on
  every `just switch`, and `cleanup = "uninstall"` drives toward "newest of
  exactly the declared list". nix-darwin's `homebrew` module has no per-formula
  pin/version option, so there is nowhere to express it.
- **Switching wholesale to nixpkgs** — nixpkgs has `beads` 1.0.3 (vs 1.1.2
  installed) and no `gascity` at all. `dolt` matches at 2.2.3. Swaps one
  mismatch for another.
- **`depends_on "beads"` satisfied by a non-Homebrew `bd`** — no. A bare-string
  `depends_on` is a *formula* dependency resolved against Homebrew's installed
  formulae; it never consults `PATH`. A nix-provided `bd` is invisible to it.

## Mitigation in use

`gc stop` when the city is not in use. The load only exists while it runs.

## If it needs solving before upstream fixes it

Package both `gc` and `bd` in this repo so Homebrew's unpinned `depends_on`
stops being a factor — the only arrangement where a pin survives a `gc`
upgrade, which is exactly when it must hold. Both are prebuilt Go binaries, so
this is `fetchurl` + install one binary, no compilation:

- `gascity.rb` is just `bin.install "gc"` from a release tarball; the formula
  carries the sha256 per platform.
- nixpkgs' `beads` is a plain `buildGoModule` with version + hash, so it
  overrides to any tag. Verified for v1.1.0:
  `sha256-+dFV//0N8ZDw9BHOJOoWZ+BvLmJKlnGtONHIYPRhfBE=`.

Requires removing `"beads"` and `"gastownhall/gascity/gascity"` from
`brews.nix`, and forfeits Homebrew's upgrade path for gascity.

Deferred 2026-08-11: not worth doing while an upstream fix may land and make it
moot. Pinning at the current 1.1.2 was considered as drift insurance — it
converts a possible future *downgrade* (risky, rejected) into a forward-only
bump — but it needs the packaging work above to actually hold.

## Watch for

`brew upgrade` runs on every `just switch`, so `beads` can move underneath this
machine at any rebuild. If it bumps before #5164 resolves, the gap to whatever
`gc` eventually requires widens and the forward-only argument gets stronger.
