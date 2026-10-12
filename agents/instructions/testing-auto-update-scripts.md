# Testing a change to the auto-update scripts

Read this before changing `hosts/shared/darwin-auto-update.nix`, `hosts/home-server/auto-update.nix` or the helpers they import from `hosts/shared/`.
How the unattended rebuilds work is in `working-in-this-repo.md` → "How auto-updates work"; this file is only about testing a change to them.

## Unit tests

`just test` runs the tests in `hosts/shared/tests/`.
Each test is a small derivation that runs a script on fixture files and fails to build when the output differs from the expected file, printing the diff.
They are exposed as the flake's `checks` output, so `nix flake check` runs them too, but it also evaluates all three machine configurations and is slower.

`.github/workflows/test.yml` runs the same check on every push.
It does not gate anything: it runs after the push, and the hosts pull `main` on their schedule whatever its result.
So run `just test` before pushing a change to a script that has a test.

Only the warning filter (`unknown-warnings.nix`) has a test.
To add a case, extend the fixtures under `hosts/shared/tests/unknown-warnings/`.
To test another script, add an attribute in `hosts/shared/tests/default.nix`, and its name to the `test` recipe in the `justfile` and to the workflow.

The rest of a script (the fetch, the rebuild, the Telegram send) has no unit test and can only be exercised by a real run, as below.

## Two facts that shape any real test

**A script change takes effect one run late.**
The run that rebuilds a host is executed by the script already installed on it, so the run that installs a new script still uses the old one.
The new script first runs on the following scheduled run.
The schedules are in the two modules named at the top, and they differ between the MacBooks and the home-server.

**The scripts only ever follow `origin/main`.**
They reset their own checkout to `origin/main` and rebuild from it, whatever branch your working checkout is on.
A branch can therefore install a new script on a host (`just switch` from the branch), but the run that script then performs rebuilds `main`:

- that run reinstalls the old script, so the host is back to `main`'s version afterwards;
- anything the script reads from its checkout at run time, such as the accepted-warnings list, is `main`'s version, or absent if `main` does not have it yet;
- a successful test is silent when the rebuild prints no warning that `main`'s accepted list lets through, so it proves the script still completes a rebuild, not that a report arrives.

There is no branch override.
It was considered on 2026-10-12 and postponed until testing from a branch is needed a second time.

## Testing from a branch, host by host

On the host, in its working checkout of this repo:

```bash
git fetch
git switch <branch>
just switch
```

Then force a run.
The script exits early with `Already up to date` when `main` has not moved, so first move its own checkout back one commit.
The script's next step resets it to `origin/main` again, so this leaves nothing behind.

The checkout path, the log path and the systemd unit name are defined in the two modules named at the top; check them there if these commands stop matching.
The launchd label is not written in the repo: nix-darwin derives it from the daemon's attribute name in `hosts/shared/darwin-auto-update.nix`.

MacBook:

```bash
sudo git -C /var/lib/nix-auto-update/nix-config reset --hard HEAD~1
sudo launchctl kickstart system/org.nixos.nix-auto-update
tail -f /var/log/nix-auto-update.log
```

Home-server (**it reboots at the end of a successful run**):

```bash
sudo git -C /var/lib/nix-auto-update/nix-config reset --hard HEAD~1
sudo systemctl start nix-auto-update
journalctl -u nix-auto-update -f
```

These need sudo, so on a remote host they are for the user to run.

## What to check afterwards

- **MacBook:** the log ends with `Update complete`, and the captured rebuild output (`switchLog` in `hosts/shared/darwin-auto-update.nix`) has just been rewritten.
- **Home-server:** the journal lines of the run are prefixed with the store hash of the script that ran; it must be the hash of the script built from the branch, which `nix eval --raw .#nixosConfigurations.home-server.config.systemd.services.nix-auto-update.serviceConfig.ExecStart` prints. The "update applied, rebooting" Telegram message also arrives.
- **2018 MacBook:** its log cannot be read from another machine, so the user has to read it there.
- **Telegram:** a failed send does not stop a run; it leaves `Telegram notification failed` in the log or journal. A host without the credentials file sends nothing and logs nothing about it.

To see a warning report arrive, the rebuild has to print a warning that `main`'s accepted list does not cover.
No host prints one in normal operation, so an end-to-end proof of the report needs a deliberate, temporary warning on `main`.

## Cleaning up

On each host, `git switch main` and delete the local branch.
Deleting the branch on GitHub before a host has switched back is harmless: `git switch main`, `git pull`, `git branch -d <branch>` still work there.
