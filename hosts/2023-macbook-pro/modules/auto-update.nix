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

    notify_failure() {
      if [ -f ${envFile} ]; then
        source ${envFile}
        curl -s "https://api.telegram.org/bot$TELEGRAM_BOT_TOKEN/sendMessage" \
          -d chat_id="$TELEGRAM_CHAT_ID" \
          -d text="nix auto-update failed on $HOSTNAME: $1" > /dev/null
      fi
    }

    trap 'notify_failure "unexpected error on line $LINENO"' ERR

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
