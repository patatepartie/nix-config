{
  description = "My systems";

  # the nixConfig here only affects the flake itself, not the system configuration!
  nixConfig = {
    experimental-features = [ "nix-command" "flakes" ];

    substituters = [
      "https://cache.nixos.org"
    ];
  };

  inputs = {
    # Specify the source of Home Manager and Nixpkgs.
    # Pinned to a master rev containing the fix from nixpkgs PR #513971
    # (issue #513543): the autoconf 2.73 / C23 stdenv-darwin migration
    # broke zsh's `zsh_cv_sys_sigsuspend` probe, defining
    # BROKEN_POSIX_SIGSUSPEND and compiling the racy sigprocmask+pause
    # fallback in Src/signals.c. Tmux-spawned zsh hung on every `$(...)`.
    # Bump back to nixos-unstable once the channel advances past a504cf27.
    nixpkgs.url = "github:nixos/nixpkgs/c491dc050f21c536f3084c4d9975dd5e1be804d0";
    nix-darwin = {
      url = "github:LnL7/nix-darwin/master";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    nixpkgs-azure.url = "github:nixos/nixpkgs/d6c71932130818840fc8fe9509cf50be8c64634f";

    nix-homebrew.url = "github:zhaofengli/nix-homebrew";

    homebrew-core = {
      url = "github:homebrew/homebrew-core";
      flake = false;
    };
    homebrew-cask = {
      url = "github:homebrew/homebrew-cask";
      flake = false;
    };
    homebrew-bundle = {
      url = "github:homebrew/homebrew-bundle";
      flake = false;
    };
  };

  outputs = { nixpkgs, nix-darwin, home-manager, nix-homebrew, homebrew-core, homebrew-cask, homebrew-bundle, ... }@inputs: {
    darwinConfigurations = {
      "Cyrils-2018-MacBook-Pro" = import ./hosts/2018-macbook-pro { inherit inputs nix-darwin home-manager nix-homebrew homebrew-core homebrew-cask homebrew-bundle; };
      "Cyrils-MacBook-Pro" = import ./hosts/2023-macbook-pro { inherit inputs nix-darwin home-manager nix-homebrew homebrew-core homebrew-cask homebrew-bundle; };
    };

    nixosConfigurations = {
      home-server = import ./hosts/home-server { inherit inputs nixpkgs home-manager; };
    };
  };
}
