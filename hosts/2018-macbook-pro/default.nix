{ nix-darwin, home-manager, ... }:

nix-darwin.lib.darwinSystem {
  system = "x86_64-darwin";

  modules = [
    ./modules/nix-core.nix
    ./modules/system.nix
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
