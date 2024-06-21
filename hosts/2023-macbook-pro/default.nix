{ nix-darwin, home-manager, nix-homebrew, ... }:

nix-darwin.lib.darwinSystem {
  system = "aarch64-darwin";

  modules = [
    ./modules/nix-core.nix
    ./modules/system.nix

    nix-homebrew.darwinModules.nix-homebrew {
      nix-homebrew = {
        # Install Homebrew under the default prefix
        enable = true;

        # Apple Silicon Only: Also install Homebrew under the default Intel prefix for Rosetta 2
        enableRosetta = true;

        # User owning the Homebrew prefix
        user = "cyrilledru";
      };
    }

    ./modules/apps.nix
    ./modules/host-users.nix

    home-manager.darwinModules.home-manager
    {
      home-manager.useGlobalPkgs = true;
      home-manager.useUserPackages = true;
      home-manager.users."cyrilledru" = import ./home.nix;

      # Optionally, use home-manager.extraSpecialArgs to pass
      # arguments to home.nix
    }
  ];
}
