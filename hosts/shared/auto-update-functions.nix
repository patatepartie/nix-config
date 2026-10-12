{ pkgs, envFile, checkoutPath }:

let
  telegramNotify = import ./telegram-notify.nix { inherit pkgs; };
  unknownWarnings = import ./unknown-warnings.nix { inherit pkgs; };
  acceptedWarnings = "${checkoutPath}/hosts/shared/accepted-warnings.txt";
in
''
  log() { echo "$(date '+%Y-%m-%d %H:%M:%S') $*"; }

  notify() {
    ${telegramNotify} ${envFile} "$1" || log "Telegram notification failed"
  }

  notify_failure() {
    notify "nix auto-update failed on $HOSTNAME: $1"
  }

  report_warnings() {
    local warnings
    warnings=$(${unknownWarnings} "$1" ${acceptedWarnings})
    if [ -n "$warnings" ]; then
      notify "nix auto-update on $HOSTNAME printed warnings that are not in hosts/shared/accepted-warnings.txt ($BEFORE -> $AFTER):"$'\n'"$warnings"
    fi
  }
''
