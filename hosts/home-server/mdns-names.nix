{ pkgs, ... }:

let
  # Each name reaches a service behind kamal-proxy, which routes by host name.
  names = [ "cash22" "transmission" "pata-track" ];
in
{
  systemd.services = builtins.listToAttrs (map (name: {
    name = "avahi-publish-${name}";
    value = {
      description = "Publish ${name}.local mDNS address";
      after = [ "avahi-daemon.service" "network-online.target" ];
      requires = [ "avahi-daemon.service" ];
      wants = [ "network-online.target" ];
      wantedBy = [ "multi-user.target" ];
      serviceConfig = {
        ExecStart = "${pkgs.avahi}/bin/avahi-publish -a -R ${name}.local 192.168.0.17";
        Restart = "on-failure";
        RestartSec = "5s";
      };
    };
  }) names);
}
