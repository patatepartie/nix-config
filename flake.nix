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

    nix-homebrew = {
      url = "github:zhaofengli-wip/nix-homebrew";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    homebrew-core = {
      url = "github:homebrew/homebrew-core";
      flake = false;
    };
    homebrew-cask = {
      url = "github:homebrew/homebrew-cask";
      flake = false;
    };
  };

  outputs = { nixpkgs, nix-darwin, home-manager, nix-homebrew, homebrew-core, homebrew-cask, ... }@inputs: {
    darwinConfigurations = {
      "Cyrils-2018-MacBook-Pro" = import ./hosts/2018-macbook-pro { inherit inputs nix-darwin home-manager; };
      "Cyrils-MacBook-Pro" = import ./hosts/2023-macbook-pro { inherit inputs nix-darwin home-manager nix-homebrew homebrew-core homebrew-cask; };
    };

    nixosConfigurations = {
      home-server = import ./hosts/home-server { inherit inputs nixpkgs home-manager; };
    };
  };
}
