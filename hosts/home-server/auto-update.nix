{ config, pkgs, ... }:

let
  httpsUrl = "https://github.com/patatepartie/nix-config.git";
  checkoutPath = "/var/lib/nix-auto-update/nix-config";

  envFile = "/var/lib/nix-auto-update/telegram.env";

  autoUpdateScript = pkgs.writeShellScript "nix-auto-update" ''
    set -euo pipefail
    export PATH=/run/current-system/sw/bin:/usr/bin:/bin

    HOSTNAME=$(hostname)

    log() { echo "$(date '+%Y-%m-%d %H:%M:%S') $*"; }

    notify() {
      if [ -f ${envFile} ]; then
        source ${envFile}
        curl -s "https://api.telegram.org/bot$TELEGRAM_BOT_TOKEN/sendMessage" \
          -d chat_id="$TELEGRAM_CHAT_ID" \
          -d text="$1" > /dev/null
      fi
    }

    notify_failure() {
      notify "nix auto-update failed on $HOSTNAME: $1"
    }

    trap 'notify_failure "unexpected error on line $LINENO"' ERR

    log "Starting nix auto-update"

    if [ ! -d ${checkoutPath} ]; then
      log "Cloning repository"
      mkdir -p /var/lib/nix-auto-update
      git clone ${httpsUrl} ${checkoutPath}
    fi

    cd ${checkoutPath}

    log "Syncing from origin"
    BEFORE=$(git rev-parse HEAD)
    git fetch origin
    git reset --hard origin/main
    git clean -fd

    AFTER=$(git rev-parse HEAD)
    if [ "$BEFORE" = "$AFTER" ]; then
      log "Already up to date"
      exit 0
    fi

    log "Rebuilding system ($BEFORE -> $AFTER)"
    switch_log=$(mktemp)
    trap 'rm -f "$switch_log"' EXIT

    nixos-rebuild switch --flake ${checkoutPath} 2>&1 | tee "$switch_log" || true
    switch_status=''${PIPESTATUS[0]}

    if [ "$switch_status" -eq 0 ]; then
      log "Update complete"
      exit 0
    fi

    if grep -qF "Pre-switch check 'switchInhibitors' failed" "$switch_log"; then
      log "Switch blocked by inhibitors, staging via boot"
      if ! nixos-rebuild boot --flake ${checkoutPath}; then
        notify_failure "nixos-rebuild boot failed ($BEFORE -> $AFTER)"
        exit 1
      fi
      notify "nix auto-update on $HOSTNAME: switch blocked by inhibitors, new generation staged, reboot to apply ($BEFORE -> $AFTER)"
      exit 0
    fi

    notify_failure "nixos-rebuild switch failed ($BEFORE -> $AFTER)"
    exit 1
  '';
in
{
  systemd.services.nix-auto-update = {
    description = "Auto-update nix configuration from GitHub";
    path = [ pkgs.git pkgs.nixos-rebuild ];
    restartIfChanged = false;
    stopIfChanged = false;
    serviceConfig = {
      Type = "oneshot";
      ExecStart = autoUpdateScript;
    };
  };

  systemd.timers.nix-auto-update = {
    description = "Daily nix auto-update";
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = "*-*-* 22:30:00 UTC";
      Persistent = true;
    };
  };
}
