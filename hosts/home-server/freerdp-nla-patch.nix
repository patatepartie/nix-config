{ config, lib, pkgs, ... }:

# FreeRDP 3.32.x sends the NLA early-auth result before the client's credentials, so Windows App hangs at "Securing connection".
# The fix is merged upstream after 3.32.1: https://github.com/FreeRDP/FreeRDP/issues/13549
# Temporary: once the notice below arrives and Windows App still connects, delete this file and its import in default.nix.
let
  fixedIn = "3.32.2";
  thisFile = "hosts/home-server/freerdp-nla-patch.nix";

  envFile = "/var/lib/nix-auto-update/telegram.env";

  message = "${config.networking.hostName} now runs FreeRDP ${pkgs.freerdp.version} without the NLA patch: check Windows App still connects, then delete ${thisFile}";

  telegramNotify = import ../shared/telegram-notify.nix { inherit pkgs; };

  noticeScript = pkgs.writeShellScript "freerdp-nla-patch-notice" ''
    exec ${telegramNotify} ${envFile} "${message}"
  '';
in
{
  nixpkgs.overlays = [
    (final: prev: {
      gnome-remote-desktop = prev.gnome-remote-desktop.override {
        freerdp =
          if final.lib.versionOlder prev.freerdp.version fixedIn then
            prev.freerdp.overrideAttrs (old: {
              patches = (old.patches or [ ]) ++ [
                (final.fetchpatch {
                  url = "https://github.com/FreeRDP/FreeRDP/commit/cbb6a73d1281fa9e4084c24f07ed0c9ad171f125.patch";
                  hash = "sha256-TepDYv+GZlE45Vb9TMjPFPhrGKKWPi49VKggN5vAvEE=";
                })
              ];
            })
          else
            final.lib.warn "FreeRDP ${prev.freerdp.version} no longer gets the NLA patch; check Windows App still connects, then delete ${thisFile}" prev.freerdp;
      };
    })
  ];

  systemd.services.freerdp-nla-patch-notice = lib.mkIf (!lib.versionOlder pkgs.freerdp.version fixedIn) {
    description = "Tell the owner that FreeRDP no longer gets the NLA patch";
    wantedBy = [ "multi-user.target" ];
    wants = [ "network-online.target" ];
    after = [ "network-online.target" ];
    serviceConfig = {
      Type = "oneshot";
      # The "-" keeps a failed send from failing the nixos-rebuild switch that starts this unit.
      ExecStart = "-${noticeScript}";
    };
  };
}
