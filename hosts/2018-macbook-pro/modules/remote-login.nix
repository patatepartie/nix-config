{ username, ... }: {
  services.openssh = {
    enable = true;
    extraConfig = ''
      PasswordAuthentication no
      KbdInteractiveAuthentication no
    '';
  };

  users.users.${username}.openssh.authorizedKeys.keys = [
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIIO1sgmPAy6+wWxxTebvzf3K4k5/jQHEnwHfHrOzV+Gm cyril@be-spoke.io"
  ];
}
