{ pkgs }:

# Sends a message ($2) with the bot credentials of an env file ($1), and does nothing when that file is absent.
pkgs.writeShellScript "telegram-notify" ''
  set -euo pipefail

  [ -f "$1" ] || exit 0
  source "$1"

  ${pkgs.curl}/bin/curl -sf --connect-timeout 10 --max-time 30 --retry 5 --retry-all-errors "https://api.telegram.org/bot$TELEGRAM_BOT_TOKEN/sendMessage" \
    -d chat_id="$TELEGRAM_CHAT_ID" \
    --data-urlencode text="$2" > /dev/null
''
