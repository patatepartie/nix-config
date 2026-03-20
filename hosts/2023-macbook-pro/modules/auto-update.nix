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
    darwin-rebuild switch --flake ${checkoutPath}

    log "Update complete"
  '';
in
{
  launchd.daemons.nix-auto-update = {
    serviceConfig = {
      ProgramArguments = [ "${autoUpdateScript}" ];
      StartCalendarInterval = [{ Hour = 19; Minute = 0; }];
      StandardOutPath = "/var/log/nix-auto-update.log";
      StandardErrorPath = "/var/log/nix-auto-update.log";
    };
  };
}
