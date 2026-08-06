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
    # WORKAROUND: nix-homebrew (even at HEAD) still pins brew-src to 6.0.13,
    # which lags the InstallSteps DSL that current homebrew-core formulae use.
    # Formulae keep adopting new DSL features faster than nix-homebrew bumps
    # brew, so this recurs with a different method/keyword each time. So far:
    # 6.0.14 added `configure_clang_system` (needed by llvm); 6.0.15 adds the
    # `overwrite:` keyword to `symlink`, without which openssl@3 and every
    # formula depending on it fail to read with
    # "homebrew/core/openssl@3: unknown keyword: :overwrite".
    # These are examples, not the whole problem — expect a new one next time.
    # This pin is load-bearing: without it `just switch` broke continuously.
    # Do NOT remove it, do NOT make it follow nix-homebrew's own brew-src, and
    # do NOT auto-track brew's latest tag — tracking latest is equivalent to
    # having no pin at all. Bump it BY HAND, only after verifying the target
    # tag actually adds the missing DSL feature; procedure in
    # agents/instructions/troubleshooting.md ("formula unreadable").
    # Expect this to stay for a long time. It is "temporary" only in the sense
    # that Homebrew's InstallSteps DSL migration will eventually settle; the
    # exit condition (nix-homebrew bumping its own brew-src past this ref) has
    # already failed to arrive twice, and upstream is further behind than we
    # are. Do not treat a bump as progress toward removal — re-check the
    # condition before assuming it: `agents/scripts/flake-input-freshness.sh
    # nix-homebrew`, then inspect that repo's flake.nix brew-src ref and
    # confirm it is >= the ref below.
    nix-homebrew.inputs.brew-src.url = "github:Homebrew/brew/6.0.15";

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

  outputs = { nixpkgs, nix-darwin, home-manager, nix-homebrew, homebrew-core, homebrew-cask, homebrew-bundle, homebrew-gascity, homebrew-circleci, ... }@inputs: {
    darwinConfigurations = {
      "Cyrils-2018-MacBook-Pro" = import ./hosts/2018-macbook-pro { inherit inputs nix-darwin home-manager nix-homebrew homebrew-core homebrew-cask homebrew-bundle; };
      "Cyrils-MacBook-Pro" = import ./hosts/2023-macbook-pro { inherit inputs nix-darwin home-manager nix-homebrew homebrew-core homebrew-cask homebrew-bundle homebrew-gascity homebrew-circleci; };
    };

    nixosConfigurations = {
      home-server = import ./hosts/home-server { inherit inputs nixpkgs home-manager; };
    };
  };
}
