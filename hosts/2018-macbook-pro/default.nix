{ nixpkgs, nix-darwin, home-manager, nix-homebrew, homebrew-core, homebrew-cask, homebrew-bundle, ... }:
let
  username = "cyrilledru";
in

nix-darwin.lib.darwinSystem {
  system = "x86_64-darwin";

  specialArgs = { inherit username; };
  pkgs = import nixpkgs { system = "x86_64-darwin"; };

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
        # /usr/local because this Intel host enables no other prefix.
        extraEnv.HOMEBREW_ORIGINAL_BREW_FILE = "/usr/local/bin/brew";

        # Install Homebrew under the default prefix
        enable = true;

        # User owning the Homebrew prefix
        user = username;

        taps = {
          "homebrew/homebrew-core" = homebrew-core;
          "homebrew/homebrew-cask" = homebrew-cask;
          "homebrew/homebrew-bundle" = homebrew-bundle;
        };

        mutableTaps = false;
      };
    }

    ./modules/apps
    ./modules/host-users.nix

    home-manager.darwinModules.home-manager
    {
      home-manager.useGlobalPkgs = true;
      home-manager.useUserPackages = true;
      home-manager.users.${username} = import ./home.nix;
      home-manager.extraSpecialArgs = { inherit username; };

      # Optionally, use home-manager.extraSpecialArgs to pass
      # arguments to home.nix
    }
  ];
}
