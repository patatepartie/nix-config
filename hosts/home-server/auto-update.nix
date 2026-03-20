{ config, pkgs, ... }:

let
  httpsUrl = "https://github.com/patatepartie/nix-config.git";
  checkoutPath = "/var/lib/nix-auto-update/nix-config";

  autoUpdateScript = pkgs.writeShellScript "nix-auto-update" ''
    set -euo pipefail
    export PATH=/run/current-system/sw/bin:/usr/bin:/bin

    log() { echo "$(date '+%Y-%m-%d %H:%M:%S') $*"; }

    log "Starting nix auto-update"

    if [ ! -d ${checkoutPath} ]; then
      log "Cloning repository"
      mkdir -p /var/lib/nix-auto-update
      git clone ${httpsUrl} ${checkoutPath}
    fi

    cd ${checkoutPath}

    log "Pulling latest changes"
    BEFORE=$(git rev-parse HEAD)
    git pull --ff-only

    AFTER=$(git rev-parse HEAD)
    if [ "$BEFORE" = "$AFTER" ]; then
      log "Already up to date"
      exit 0
    fi

    log "Rebuilding system ($BEFORE -> $AFTER)"
    nixos-rebuild switch --flake ${checkoutPath}

    log "Update complete"
  '';
in
{
  systemd.services.nix-auto-update = {
    description = "Auto-update nix configuration from GitHub";
    path = [ pkgs.git pkgs.nixos-rebuild ];
    serviceConfig = {
      Type = "oneshot";
      ExecStart = autoUpdateScript;
    };
  };

  systemd.timers.nix-auto-update = {
    description = "Daily nix auto-update";
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = "*-*-* 19:00:00 UTC";
      Persistent = true;
    };
  };
}
