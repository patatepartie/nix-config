# Working in nix-config

## Homebrew

Never run `brew tap`, `brew install`, or other mutating brew commands. All Homebrew config (taps, brews, casks) is managed declaratively through nix-darwin. To add a package, modify the appropriate nix file (`brews.nix`, `casks.nix`) and apply via `just switch`.

## Commit prefixes

Prefix commit titles based on which hosts are affected:
- **MBP2018** — 2018 MacBook Pro only
- **MBP2023** — 2023 MacBook Pro only
- **MBPs** — both MacBook Pros
- **HomeServer** — home server only
- No prefix — all hosts or host-agnostic changes

## tmux

Always use `command tmux` instead of bare `tmux`. The oh-my-zsh tmux plugin intercepts bare `tmux` and fails in non-interactive shells.

## Nix rebuild output

After any `just switch` or nix eval, report all warnings to the user — don't silently ignore them.

## Remote machines

Cannot run `sudo` over SSH to remote machines. When an operation needs sudo on the home server, tell the user what command to run rather than attempting it.

## SSH to home-server.local

Use unquoted form for read-only SSH commands so auto-approval rules match:
```
ssh home-server.local journalctl -u foo --no-pager     # auto-approved
ssh home-server.local "journalctl -u foo --no-pager"   # prompts (quoted form breaks prefix match)
```
For commands requiring shell metacharacters on the remote side (`*`, `|`, `>`, `;`), quoted form is fine — the resulting prompt is intentional.
