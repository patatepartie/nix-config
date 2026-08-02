{ pkgs, ... }: {
  # Necessary for using flakes on this system.
  nix.settings.experimental-features = [ "nix-command" "flakes" ];

  nixpkgs.config.allowUnfree = true;

  # Make sure nix is the latest version in nixpkgs
  nix.package = pkgs.nix;

  # nix-index is a tool to quickly locate the package providing a certain file in nixpkgs.
  # Looks useful.
  programs.nix-index.enable = true;

  # do garbage collection weekly to keep disk usage low
  # scheduled Monday 9am (machine-local time) instead of the nix-darwin default of
  # Sunday 3:15am, which this laptop is reliably asleep for and so never actually ran
  nix.gc = {
    automatic = true;
    interval = [{ Hour = 9; Minute = 0; Weekday = 1; }];
    options = "--delete-older-than 7d";
  };

  # Nix automatically detects files in the store that have identical contents,
  # and replaces them with hard links to a single copy.
  nix.settings.auto-optimise-store = false;
}
