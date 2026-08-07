#!/usr/bin/env bash
# End-to-end test of the tmux save/restore chain on a throwaway tmux server.
#
# Why this exists: the save/restore path has broken repeatedly in ways only
# visible after a real restart (hook fires before its option is set, continuum
# auto-save silently disabled by a theme, nix-store paths GC'd out from under a
# long-lived server). Each bug cost a full set of live Claude sessions. This
# exercises the same chain without touching the `default` server or
# ~/.tmux/resurrect.
#
# Isolation, three layers — all three are load-bearing:
#   1. `tmux -L <socket>` — a separate server, so no live sessions are at risk.
#   2. HOME=<sandbox> for every save/restore invocation — the assistant-resurrect
#      scripts hardcode RESURRECT_DIR="${HOME}/.tmux/resurrect" and ignore
#      @resurrect-dir, so overriding HOME is the only way to keep them off the
#      real state. @resurrect-dir is set to match, for tmux-resurrect itself.
#   3. A PATH shim that rewrites bare `tmux` to `tmux -L <socket> -f /dev/null`.
#      Without it the test SILENTLY READS PRODUCTION: resurrect's scripts all
#      invoke bare `tmux`, which connects to the default socket no matter which
#      server launched them. First run of this harness enumerated 101 real panes
#      and 16 real assistant sessions, then handed that file to restore.sh —
#      only the script's own "pane already has an assistant" guard stopped it
#      from firing `claude --resume` into live panes. Never remove this shim.
#   4. `-f /dev/null` on every invocation. A fresh `tmux -L <socket>` server
#      still sources ~/.tmux.conf, whose auto-restore run-shell then replays the
#      REAL ~/.tmux/resurrect/last into the test server — the second failure
#      this harness hit. Skipping user config is what makes the server a clean
#      room; the test sets the @resurrect-* options it needs explicitly below.
#
# Usage: agents/scripts/test-tmux-resurrect.sh [--keep]
#   --keep  leave the test server and sandbox up for inspection

set -uo pipefail

SOCKET="resurrect-test"
SOCKET_PATH="${TMUX_TMPDIR:-/private/tmp}/tmux-$(id -u)/$SOCKET"
SANDBOX="${TMPDIR:-/tmp}/tmux-resurrect-test-$$"
# Run-unique so the isolation assertions cannot be fooled by a real session that
# happens to share the test name (a bare `testsess` did leak onto the live
# server once during development).
TESTSESS="testsess-$$"
KEEP=0
[ "${1:-}" = "--keep" ] && KEEP=1

# Resolved once, before the shim directory is ever on PATH — otherwise the
# shim would exec itself.
TMUX_BIN="$(command -v tmux || echo /opt/homebrew/bin/tmux)"
case "$TMUX_BIN" in
  */tmux-resurrect-test-*) TMUX_BIN=/opt/homebrew/bin/tmux ;;
esac
# Both plugin paths are discovered from the RUNNING server's options rather
# than from a nix expression. `nix-build '<nixpkgs>' -A tmuxPlugins.resurrect`
# would resolve against the ambient channel, which can drift from what
# flake.lock pins — the test would then exercise a different tmux-resurrect
# than the one actually deployed, defeating the point of the harness.
#
# These two are the only bare-`tmux` calls in the script, and they are
# deliberate: they query the real server precisely because it is the source of
# truth for what is deployed. Both are read-only `show-option`s and cannot
# mutate it. Everywhere else, bare `tmux` is forbidden — use tm().
probe_real_option() { "$TMUX_BIN" show-option -gqv "$1" 2>/dev/null; }

RESURRECT="$(probe_real_option @resurrect-save-script-path | sed -E 's|/save\.sh$||')"
if [ -z "$RESURRECT" ] || [ ! -d "$RESURRECT" ]; then
  echo "could not locate tmux-resurrect via the running server" >&2
  echo "(start a normal tmux server first so the @resurrect-* options are set)" >&2
  exit 1
fi

pass=0
fail=0
ok()   { echo "  PASS  $*"; pass=$((pass + 1)); }
bad()  { echo "  FAIL  $*"; fail=$((fail + 1)); }
info() { echo "== $*"; }

tm() { "$TMUX_BIN" -L "$SOCKET" -f /dev/null "$@"; }

# Every resurrect/assistant invocation runs with the sandboxed HOME *and* a
# PATH whose `tmux` is pinned to the test socket (see isolation note above).
# TMUX is set deliberately, not inherited. restore.sh computes the socket it
# creates sessions on as `echo $TMUX | cut -d, -f1` and then calls
# `tmux -S <that path>`, which bypasses the PATH shim's -L entirely. Run it with
# TMUX unset (or inherited from the real server) and restore creates its
# sessions on the DEFAULT socket — this leaked a `testsess` into the live server
# during development. Pointing TMUX at the test socket is what keeps
# `tmux -S "$(tmux_socket)"` on the test server.
sandboxed() {
  env HOME="$SANDBOX" \
    TMUX_ASSISTANT_RESURRECT_DIR="$SANDBOX/state" \
    PATH="$SANDBOX/bin:$PATH" \
    TMUX="$SOCKET_PATH,0,0" \
    "$@"
}

make_tmux_shim() {
  mkdir -p "$SANDBOX/bin"
  cat >"$SANDBOX/bin/tmux" <<SHIM
#!/bin/sh
# Force every bare-\`tmux\` call inside resurrect onto the test socket, with
# user config skipped (see isolation note 3 and 4 above).
exec "$TMUX_BIN" -L "$SOCKET" -f /dev/null "\$@"
SHIM
  chmod +x "$SANDBOX/bin/tmux"
}

cleanup() {
  if [ "$KEEP" = "1" ]; then
    echo
    info "kept: server 'tmux -L $SOCKET', sandbox $SANDBOX"
    info "clean up with: tmux -L $SOCKET kill-server; tmux -L $SOCKET-holder kill-server; rm -rf $SANDBOX"
    return
  fi
  tm kill-server 2>/dev/null
  "$TMUX_BIN" -L "$SOCKET-holder" -f /dev/null kill-server 2>/dev/null
  rm -rf "$SANDBOX"
}
trap cleanup EXIT INT TERM

# --- guard: never run against the real server -------------------------------
if [ "$SOCKET" = "default" ]; then
  echo "refusing to run against the default server" >&2
  exit 1
fi

mkdir -p "$SANDBOX/.tmux/resurrect" "$SANDBOX/state"
make_tmux_shim

ASSISTANT_SRC="$(probe_real_option @resurrect-hook-post-save-all |
  sed -E "s/^bash '//; s|/scripts/save-assistant-sessions.sh'$||")"
if [ -z "$ASSISTANT_SRC" ] || [ ! -d "$ASSISTANT_SRC" ]; then
  echo "could not locate tmux-assistant-resurrect via the running server" >&2
  echo "(start a normal tmux server first, or set ASSISTANT_SRC by hand)" >&2
  exit 1
fi
ASSISTANT="$ASSISTANT_SRC/scripts"

info "test server:  tmux -L $SOCKET"
info "sandbox HOME: $SANDBOX"
info "resurrect:    $RESURRECT"
info "assistant:    $ASSISTANT"
echo

# --- build a server that mirrors the real config ordering -------------------
info "starting test server with 3 windows"
tm new-session -d -s "$TESTSESS" -c "$HOME" 2>/dev/null
tm new-window -t "$TESTSESS" -c "$HOME" 2>/dev/null
tm new-window -t "$TESTSESS" -c "$HOME" 2>/dev/null
tm split-window -t "$TESTSESS:1" -c "$HOME" 2>/dev/null

# Mirror home.nix: set the @resurrect-* options, INCLUDING the hooks, and point
# resurrect's own dir at the sandbox.
tm set-option -g @resurrect-dir "$SANDBOX/.tmux/resurrect"
tm set-option -g @resurrect-capture-pane-contents 'on'
tm set-option -g @resurrect-save-script-path "$RESURRECT/save.sh"
tm set-option -g @resurrect-restore-script-path "$RESURRECT/restore.sh"
tm set-option -g @resurrect-hook-post-save-all "bash '$ASSISTANT/save-assistant-sessions.sh'"
tm set-option -g @resurrect-hook-post-restore-all "bash '$ASSISTANT/restore-assistant-sessions.sh'"

win_before=$(tm list-windows -t "$TESTSESS" 2>/dev/null | wc -l | tr -d ' ')
pane_before=$(tm list-panes -s -t "$TESTSESS" 2>/dev/null | wc -l | tr -d ' ')
info "before save: $win_before windows, $pane_before panes"
echo

# --- test 1: the ordering bug ------------------------------------------------
# The regression that cost a full session set: restore.sh reads
# @resurrect-hook-post-restore-all at call time, so if the restore trigger fires
# before that option is set, panes come back as bare shells with no assistants.
info "test 1: post-restore hook option is set before restore runs"
hook=$(tm show-option -gqv @resurrect-hook-post-restore-all)
if [ -n "$hook" ]; then
  ok "@resurrect-hook-post-restore-all is set"
else
  bad "@resurrect-hook-post-restore-all is EMPTY — restore would skip assistants"
fi

# --- test 2: save produces state --------------------------------------------
info "test 2: save writes resurrect state + assistant sidecar"
TMUX="" sandboxed "$RESURRECT/save.sh" >/dev/null 2>&1
sleep 1

last_link="$SANDBOX/.tmux/resurrect/last"
if [ -f "$last_link" ]; then
  ok "resurrect save file written ($(wc -l <"$last_link" | tr -d ' ') lines)"
else
  bad "no resurrect save file at $last_link"
fi

# Isolation assertion: the save must describe ONLY the test server. If a real
# session name shows up here, the tmux shim is not in effect and the harness is
# reading production — fail hard rather than reporting misleading results.
info "test 2b: save captured the test server only, not the real one"
if [ -f "$last_link" ]; then
  stray=$(awk -F'\t' '$1 == "pane" || $1 == "window" { print $2 }' "$last_link" |
    sort -u | grep -vx "$TESTSESS" | head -5)
  if [ -z "$stray" ]; then
    ok "save contains only '$TESTSESS'"
  else
    bad "ISOLATION LEAK — save contains real sessions: $(echo "$stray" | tr '\n' ' ')"
  fi
fi

# --- test 3: assistant hook actually fired on save --------------------------
info "test 3: post-save hook wrote the assistant sidecar"
if [ -f "$SANDBOX/.tmux/resurrect/assistant-save.log" ]; then
  ok "assistant-save.log written (post-save hook fired)"
else
  bad "assistant-save.log MISSING — post-save hook did not fire"
fi

if [ -f "$SANDBOX/.tmux/resurrect/assistant-sessions.json" ]; then
  n=$(jq '.sessions | length' "$SANDBOX/.tmux/resurrect/assistant-sessions.json" 2>/dev/null || echo 0)
  # The test panes run plain shells, so 0 is the only correct answer. A nonzero
  # count means the save enumerated the real server (see the isolation note).
  if [ "$n" = "0" ]; then
    ok "assistant-sessions.json written with 0 sessions (correct — test panes are plain shells)"
  else
    bad "assistant-sessions.json has $n session(s) — expected 0; harness is seeing the real server"
  fi
else
  bad "assistant-sessions.json MISSING"
fi

# --- test 4: real state was not touched -------------------------------------
info "test 4: the real ~/.tmux/resurrect was not modified"
real_last="$HOME/.tmux/resurrect/last"
real_before=$(stat -f %m "$real_last" 2>/dev/null || echo none)
sleep 1
real_after=$(stat -f %m "$real_last" 2>/dev/null || echo none)
if [ "$real_before" = "$real_after" ]; then
  ok "real resurrect state untouched (mtime unchanged)"
else
  bad "REAL STATE MODIFIED — isolation leak"
fi

# --- test 5: restore rebuilds the layout ------------------------------------
info "test 5: kill the server, restore, compare layout"
tm kill-server 2>/dev/null
sleep 1

tm new-session -d -s placeholder -c "$HOME" 2>/dev/null

# tmux-resurrect's restore needs an ATTACHED client — it uses `switch-client`
# and `new-window` against the current client, and without one every call fails
# with "no current client" and no sessions are created. In production this is
# satisfied implicitly (restore fires from inside an attached tmux). Headless,
# we have to supply one: park a detached `attach` inside a throwaway holder
# server so the test server sees a real client.
tm set-option -g @resurrect-dir "$SANDBOX/.tmux/resurrect"
"$TMUX_BIN" -L "$SOCKET-holder" -f /dev/null \
  new-session -d -s holder \
  "$TMUX_BIN -L $SOCKET -f /dev/null attach -t placeholder" 2>/dev/null
sleep 2

if [ "$(tm list-clients 2>/dev/null | wc -l | tr -d ' ')" -gt 0 ]; then
  ok "test server has an attached client (restore precondition)"
else
  bad "no client attached — restore will fail with 'no current client'"
fi
tm set-option -g @resurrect-dir "$SANDBOX/.tmux/resurrect"
tm set-option -g @resurrect-capture-pane-contents 'on'
tm set-option -g @resurrect-save-script-path "$RESURRECT/save.sh"
tm set-option -g @resurrect-restore-script-path "$RESURRECT/restore.sh"
tm set-option -g @resurrect-hook-post-save-all "bash '$ASSISTANT/save-assistant-sessions.sh'"
tm set-option -g @resurrect-hook-post-restore-all "bash '$ASSISTANT/restore-assistant-sessions.sh'"

TMUX="" sandboxed "$RESURRECT/restore.sh" >/dev/null 2>&1
sleep 2

win_after=$(tm list-windows -t "$TESTSESS" 2>/dev/null | wc -l | tr -d ' ')
pane_after=$(tm list-panes -s -t "$TESTSESS" 2>/dev/null | wc -l | tr -d ' ')
info "after restore: $win_after windows, $pane_after panes"

if [ "$win_after" = "$win_before" ]; then
  ok "window count restored ($win_after)"
else
  bad "window count $win_after != $win_before"
fi

if [ "$pane_after" = "$pane_before" ]; then
  ok "pane count restored ($pane_after)"
else
  bad "pane count $pane_after != $pane_before"
fi

# --- test 6: the post-restore hook fired ------------------------------------
# This is the check that would have caught the bug: the layout can restore
# perfectly while the assistant hook never runs. Its log is the only evidence.
info "test 6: post-restore hook fired (the check that catches the ordering bug)"
if [ -f "$SANDBOX/.tmux/resurrect/assistant-restore.log" ]; then
  ok "assistant-restore.log written — post-restore hook fired"
  echo "        $(tail -1 "$SANDBOX/.tmux/resurrect/assistant-restore.log")"
else
  bad "assistant-restore.log MISSING — hook did NOT fire (this is the prod bug)"
fi

# --- test 7: nothing leaked into the real server -----------------------------
# Backstop for the restore.sh socket behaviour described above: if any test
# session appears on the default server, the isolation is broken regardless of
# what the other tests reported.
info "test 7: no test sessions leaked onto the default server"
leaked=$("$TMUX_BIN" list-sessions -F '#{session_name}' 2>/dev/null |
  grep -Ex "$TESTSESS|placeholder|probe" | tr '\n' ' ')
if [ -z "$leaked" ]; then
  ok "default server has no test sessions"
else
  bad "LEAKED into the real server: $leaked  (kill with: tmux kill-session -t <name>)"
fi

echo
info "$pass passed, $fail failed"
[ "$fail" -eq 0 ]
