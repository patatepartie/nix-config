{ config, lib, pkgs, ... }:
let
  user = config.system.primaryUser;
  extensions = [
    # video
    "mp4" "m4v" "mov" "mkv" "avi" "wmv" "flv" "webm" "mpg" "mpeg" "ts" "m2ts" "3gp" "ogv"
    # audio
    "mp3" "m4a" "aac" "flac" "wav" "aiff" "ogg" "opus" "wma"
  ];
in
{
  # Outside the user's login session (e.g. in home-manager) duti silently does nothing.
  system.activationScripts.postActivation.text = ''
    if [ -d /Applications/VLC.app ]; then
      vlc_uid=$(id -u ${user})
      for ext in ${lib.concatStringsSep " " extensions}; do
        launchctl asuser "$vlc_uid" sudo -u ${user} ${pkgs.duti}/bin/duti -s org.videolan.vlc ".$ext" all || true
        if ! launchctl asuser "$vlc_uid" sudo -u ${user} ${pkgs.duti}/bin/duti -x "$ext" | grep -qx org.videolan.vlc; then
          echo "warning: could not make VLC the default app for .$ext" >&2
        fi
      done
    fi
  '';
}
