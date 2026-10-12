# ADR 0001: Report unknown warnings from unattended rebuilds

**Date:** 2026-10-12
**Status:** accepted, implemented

## Context

Each of the three machines rebuilds itself unattended from `main`.
Nobody reads the output of those rebuilds, so a warning that matters goes unnoticed until it causes harm.

One such case was handled by hand on 2026-10-12.
`hosts/home-server/freerdp-nla-patch.nix` prints a warning when a temporary FreeRDP patch stops being applied, and only an unattended rebuild would ever have printed it, so that file got a dedicated Telegram notice.
This decision covers the general case.

Being told about every warning is not acceptable either: some are permanent and already accepted.

## Decision

After each unattended rebuild, the host sends on Telegram every warning in the output of the system switch that is not on an accepted list.

- **Reported every time.**
  An unknown warning is reported after every rebuild until it is fixed or accepted, not once.
  This needs no memory between rebuilds, and a report lost to a failed send comes back with the next rebuild.
- **Every kind of warning counts**, not only evaluation warnings.
  Noisy ones get accepted one by one.
- **A warning is a line containing `warning:`**, in any case, together with the indented lines that follow it.
  Identical warnings within one rebuild are reported once.
- **Accepting is one entry in one file**, `hosts/shared/accepted-warnings.txt`.
  An entry is a fixed piece of text matched anywhere in the warning, chosen to leave out the parts that change between rebuilds.
  There is no fingerprinting or normalisation of versions and store paths.
- **The list is read from the checkout at run time**, not baked into the system.
  Each host reads it from the checkout it has just reset to `main`, so an acceptance takes effect on the run that pulls it.
- **One list for unattended runs and for sessions.**
  The same file tells agents which warnings not to mention after an interactive rebuild.
  The one exception is `Git tree is dirty`, which stays in the instruction file: it is expected in a session and would be worth hearing about from an unattended run.
- **Telegram is the channel**, as for the failure notices of the same runs.

## Alternatives considered

- **List baked into the system.**
  Simpler, but an acceptance would only take effect one rebuild later, so each machine would report an accepted warning once more.
- **The home-server evaluates all three configurations daily.**
  One place, and earlier than the rebuilds, but it sees evaluation warnings only and misses everything printed while applying the system.
  It could be added as an early warning; it cannot replace the per-host report.
- **A GitHub issue per warning.**
  A session could be pointed straight at it and repeats would collapse into one issue, but the server's deploy key cannot open issues, so all three machines would need a new token.
- **Email.**
  Needs mail credentials on three machines, for no gain over Telegram.
- **Desktop notification on the MacBooks.**
  The rebuild runs as a detached root daemon, the notification vanishes when nobody is there, and it does not cover the server.
- **Two lists**, one for unattended runs and one for sessions.
  Every acceptance would be two edits, and forgetting one leaves either Telegram or the agents still reporting.

## Consequences and known limits

- **Only lines containing `warning:` are caught.**
  A problem that does not use that word, such as a deprecation note or a non-fatal `error:`, still goes unseen.
- **A continuation line must be indented.**
  A multi-line warning whose later lines start at the margin is reported with its first line only, and an accepted entry cannot match text on those later lines.
- **An accepted entry applies to all three hosts.**
  A warning accepted because of one machine is not reported if it later appears on another.
- **A long report is cut** to fit in one Telegram message.
  The full output is in the host's log or journal.
- **No report on a day without a rebuild.**
  The scripts stop early when `main` has not moved, so a warning is repeated per rebuild, not per day.
- **Only the system switch is scanned.**
  The home-server's fallback, which stages the new generation for the next boot when the switch is blocked, is not.
- **A failed send is logged, not retried later.**
  The run carries on, and the warning is reported again only by the next rebuild.
- **A change to the reporting itself takes effect one run late** on each host, and cannot be tested from a branch end to end.
  See `agents/instructions/testing-auto-update-scripts.md`.

## Deferred

- A way to make the auto-update scripts follow a branch, for testing.
  Postponed until it is needed a second time.
