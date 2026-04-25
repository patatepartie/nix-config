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
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    nix-darwin = {
      url = "github:LnL7/nix-darwin/master";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    nixpkgs-azure.url = "github:nixos/nixpkgs/d6c71932130818840fc8fe9509cf50be8c64634f";

    nix-homebrew = {
      url = "github:zhaofengli/nix-homebrew";
      # Override pinned brew 5.1.1 with 5.1.7 to support new `depends_on :macos`
      # cask syntax (bulk-migrated upstream 2026-04-24). Drop once nix-homebrew
      # merges https://github.com/zhaofengli/nix-homebrew/pull/133.
      inputs.brew-src.url = "github:Homebrew/brew/5.1.7";
    };

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
