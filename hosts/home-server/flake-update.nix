{ config, pkgs, ... }:

let
  user = "nix-flake-update";
  sshUrl = "git@github.com:patatepartie/nix-config.git";
  stateDir = "/var/lib/nix-flake-update";
  checkoutPath = "${stateDir}/nix-config";
  keyPath = "${stateDir}/id_ed25519";

  flakeUpdateScript = pkgs.writeShellScript "nix-flake-update" ''
    set -euo pipefail

    HOSTNAME=$(hostname)

    log() { echo "$(date '+%Y-%m-%d %H:%M:%S') $*"; }

    notify() {
      if [ -f "$CREDENTIALS_DIRECTORY/telegram" ]; then
        source "$CREDENTIALS_DIRECTORY/telegram"
        curl -s "https://api.telegram.org/bot$TELEGRAM_BOT_TOKEN/sendMessage" \
          -d chat_id="$TELEGRAM_CHAT_ID" \
          -d text="$1" > /dev/null
      fi
    }

    trap 'notify "flake.lock update failed on $HOSTNAME: unexpected error on line $LINENO"' ERR

    if [ ! -f ${keyPath} ]; then
      ssh-keygen -q -t ed25519 -N "" -C "${user}@$HOSTNAME" -f ${keyPath}
      log "Generated a deploy key. Register it on GitHub with write access:"
      log "  gh repo deploy-key add <file> --allow-write --title $HOSTNAME"
      cat ${keyPath}.pub
      notify "flake.lock update on $HOSTNAME: generated a deploy key, register it on GitHub (journalctl -u nix-flake-update)"
      exit 0
    fi

    export GIT_SSH_COMMAND="ssh -i ${keyPath} -o IdentitiesOnly=yes"

    log "Starting flake.lock update"

    if [ ! -d ${checkoutPath} ]; then
      log "Cloning repository"
      git clone ${sshUrl} ${checkoutPath}
    fi

    cd ${checkoutPath}

    log "Syncing from origin"
    git fetch origin
    git reset --hard origin/main
    git clean -fd

    nix flake update

    if git diff --quiet flake.lock; then
      log "flake.lock unchanged"
      exit 0
    fi

    git add flake.lock
    git -c user.name="Cyril Ledru" -c user.email="cyril.ledru@gmail.com" commit -m "Upgrade flake"
    git push origin HEAD:main
    log "Pushed $(git rev-parse HEAD)"
  '';
in
{
  users.users.${user} = {
    isSystemUser = true;
    group = user;
    home = stateDir;
  };
  users.groups.${user} = { };

  programs.ssh.knownHosts."github.com".publicKey =
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOMqqnkVzrm0SdG6UOoqKLsabgH5C9okWi0dh2l9GKJl";

  systemd.services.nix-flake-update = {
    description = "Update flake.lock and push it to GitHub";
    path = [ pkgs.git pkgs.openssh pkgs.curl pkgs.hostname config.nix.package ];
    restartIfChanged = false;
    serviceConfig = {
      Type = "oneshot";
      User = user;
      Group = user;
      StateDirectory = "nix-flake-update";
      StateDirectoryMode = "0700";
      LoadCredential = "telegram:/var/lib/nix-auto-update/telegram.env";
      ExecStart = flakeUpdateScript;
    };
  };

  systemd.timers.nix-flake-update = {
    description = "Daily flake.lock update";
    wantedBy = [ "timers.target" ];
    timerConfig = {
      # Half an hour ahead of the rebuilds in hosts/*/auto-update.nix, so they apply today's lock.
      OnCalendar = "*-*-* 07:00:00 Asia/Tokyo";
      Persistent = true;
    };
  };
}
