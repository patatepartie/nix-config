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
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    # nixpkgs 26.11+ dropped x86_64-darwin; pin 2018 MBP to last supported stable branch.
    # nix-darwin master enforces nixpkgs version match, so we need paired stable branches for both.
    # Permanent, unlike the other pins here: upstream is not bringing x86_64-darwin back, so there
    # is no trigger to drop this. It ends when the 2018 MBP is retired or moved to x86_64-linux.
    # Until then that host is frozen on 26.05 and stops getting updates once the branch goes EOL.
    nixpkgs-x86-darwin.url = "github:nixos/nixpkgs/nixpkgs-26.05-darwin";
    nix-darwin = {
      url = "github:LnL7/nix-darwin/master";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    nix-darwin-x86 = {
      url = "github:LnL7/nix-darwin/nix-darwin-26.05";
      inputs.nixpkgs.follows = "nixpkgs-x86-darwin";
    };
    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    home-manager-x86 = {
      url = "github:nix-community/home-manager/release-26.05";
      inputs.nixpkgs.follows = "nixpkgs-x86-darwin";
    };

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

    homebrew-gascity = {
      url = "github:gastownhall/homebrew-gascity";
      flake = false;
    };

    homebrew-circleci = {
      url = "github:circleci-public/homebrew-circleci";
      flake = false;
    };
  };

  outputs = { nixpkgs, nixpkgs-x86-darwin, nix-darwin, nix-darwin-x86, home-manager, home-manager-x86, nix-homebrew, homebrew-core, homebrew-cask, homebrew-bundle, homebrew-gascity, homebrew-circleci, ... }@inputs: {
    darwinConfigurations = {
      "Cyrils-2018-MacBook-Pro" = import ./hosts/2018-macbook-pro {
        inherit inputs nix-homebrew homebrew-core homebrew-cask homebrew-bundle;
        nixpkgs = nixpkgs-x86-darwin;
        nix-darwin = nix-darwin-x86;
        home-manager = home-manager-x86;
      };
      "Cyrils-MacBook-Pro" = import ./hosts/2023-macbook-pro { inherit inputs nix-darwin home-manager nix-homebrew homebrew-core homebrew-cask homebrew-bundle homebrew-gascity homebrew-circleci; };
    };

    nixosConfigurations = {
      home-server = import ./hosts/home-server { inherit inputs nixpkgs home-manager; };
    };
  };
}
