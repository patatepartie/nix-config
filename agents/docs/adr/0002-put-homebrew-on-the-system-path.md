# ADR 0002: Put Homebrew on the system PATH

**Date:** 2026-11-01
**Status:** accepted, implemented

## Context

On the 2023 MacBook, Homebrew lives in `/opt/homebrew/bin`, which is on no default macOS or nix-darwin path.
Until now it reached `PATH` only through `eval "$(/opt/homebrew/bin/brew shellenv)"` in the zsh `initContent` of `hosts/2023-macbook-pro/home.nix`, which only interactive shells run.
That line went in when nix-homebrew replaced a hand-installed Homebrew, following Homebrew's own installation advice; no alternative was weighed at the time.

nix-darwin's `/etc/zshenv` runs for every zsh, interactive or not, and overwrites `PATH` with `environment.systemPath`.
A `PATH` handed down by the parent process does not survive it, unless the parent also exports nix-darwin's guard variable `__NIX_DARWIN_SET_ENVIRONMENT_DONE`.
So any program that starts `zsh -c` without a terminal behind it runs without Homebrew.

gascity hit this.
Its supervisor runs from a launch agent and starts each agent session as `/bin/zsh -c "claude …"` in tmux.
From 2026-10-08 to 2026-11-01 every `bd.dog` maintenance session died at once with `exec: claude: not found`, retried every six minutes, and left `gc doctor` failing `order-firing-current` and `startup-health-episodes`.
gascity 1.5.0 logged only a 60-second start timeout; 1.5.1 surfaces the shell error.

## Decision

Add `/opt/homebrew/bin` to `environment.systemPath` on the 2023 MacBook, in `hosts/2023-macbook-pro/modules/apps/homebrew.nix`, as a plain list entry.

- **Plain entry, not `lib.mkAfter`.**
  A plain entry puts `/opt/homebrew/bin` first, ahead of the Nix profiles and `/usr/bin`.
  That is the order `brew shellenv` gives interactive shells, so a script and a terminal resolve a command the same way.
  `mkAfter` would put it last instead, keeping scripts on the Nix `jq` and Apple's `python3`, `pip3` and `openssl` while the terminal uses Homebrew's.
- **2023 MacBook only.**
  The 2018 MacBook's Homebrew is in `/usr/local/bin`, which is already on the system path.
- **`brew shellenv` stays in `initContent`.**
  It also sets `HOMEBREW_PREFIX`, `MANPATH` and `INFOPATH`, which interactive shells still want.

## Alternatives considered

- **Point gascity at `/opt/homebrew/bin/claude`** with `command` in `[providers.claude]` of the city's `city.toml`.
  `claude` starts, but the session's `PATH` still lacks Homebrew, so the hooks gascity installs for Claude cannot find `gc`, and the agent cannot run `gc`, `bd` or `dolt`, which is all a dog does.
- **Set `PATH` through `env` in `[providers.claude]`.**
  gascity passes it as tmux session environment, and `/etc/zshenv` overwrites it; tested on 2026-11-01.
- **Set `__NIX_DARWIN_SET_ENVIRONMENT_DONE=1` through that `env`.**
  Works in a test session, but depends on the name of a nix-darwin internal, fails silently if that changes, and lives outside this repo.
- **Add the variable or a `PATH` to the supervisor's launch agent.**
  The plist is written by `gc supervisor install` and rewritten on reinstall, and `PATH` alone would be overwritten as above.

## Consequences

- **Every non-interactive zsh on the 2023 MacBook now finds Homebrew tools**, not only gascity's.
  This is intended, but it is machine-wide.
- **Such zsh scripts now get Homebrew's `jq`, `python3`, `pip3` and `openssl`** where they used to get the Nix `jq` and Apple's copies.
  bash scripts are unaffected, the auto-update scripts and nix-darwin activation among them, because nix-darwin resets `PATH` only for interactive bash.
- **`~/.local/bin` and mise's directories are still missing** from non-interactive zsh.
  A tool installed only there would hit the same failure.
