{ inputs, nix-darwin, home-manager, nix-homebrew, homebrew-core, homebrew-cask, homebrew-gascity, homebrew-circleci, ... }:
let
  username = "cyrilledru";
in

nix-darwin.lib.darwinSystem {
  system = "aarch64-darwin";

  specialArgs = { inherit username; };

  modules = [
    ./modules/nix-core.nix
    ./modules/system.nix
    ./modules/auto-update.nix

    nix-homebrew.darwinModules.nix-homebrew {
      nix-homebrew = {
        # WORKAROUND: nix-homebrew's generated bin/brew never exports
        # HOMEBREW_ORIGINAL_BREW_FILE, which the brew it launches reads with a
        # hard ENV.fetch, so every brew call aborts and `just switch` dies at
        # "setting up Homebrew". Must be a literal path: extraEnv values are
        # escapeShellArg'd, so "$HOMEBREW_BREW_FILE" would not expand.
        # zhaofengli/nix-homebrew#187. Reverting the brew-src pin does NOT fix
        # this; see agents/instructions/troubleshooting.md before touching it.
        extraEnv.HOMEBREW_ORIGINAL_BREW_FILE = "/opt/homebrew/bin/brew";

        # Install Homebrew under the default prefix
        enable = true;

        # Apple Silicon Only: Also install Homebrew under the default Intel prefix for Rosetta 2
        enableRosetta = true;

        # User owning the Homebrew prefix
        user = username;

        taps = {
          "homebrew/homebrew-core" = homebrew-core;
          "homebrew/homebrew-cask" = homebrew-cask;
          "gastownhall/homebrew-gascity" = homebrew-gascity;
          "circleci-public/homebrew-circleci" = homebrew-circleci;
        };

        autoMigrate = true;

        trust.taps = [ "gastownhall/gascity" "circleci-public/circleci" ];
      };
    }

    ./modules/apps
    ./modules/host-users.nix

    home-manager.darwinModules.home-manager
    {
      home-manager.useGlobalPkgs = true;
      home-manager.useUserPackages = true;
      home-manager.backupFileExtension = "backup";
      home-manager.users.${username} = import ./home.nix;
      home-manager.extraSpecialArgs = {
        inherit username;
      };
    }
  ];
}
