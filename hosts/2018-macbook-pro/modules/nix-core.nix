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
  nix.gc = {
    automatic = true;
    options = "--delete-older-than 1w";
  };

  # Nix automatically detects files in the store that have identical contents,
  # and replaces them with hard links to a single copy.
  nix.settings.auto-optimise-store = false;
}
