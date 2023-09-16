{
  description = "My systems";

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
  };

  outputs = { nixpkgs, nix-darwin, home-manager, ... }@inputs: {
    darwinConfigurations = {
      "cyrils-2018-macbook-pro" = import ./hosts/2018-macbook-pro { inherit inputs nix-darwin home-manager; };
    };

    nixosConfigurations = {
      home-server = import ./hosts/home-server { inherit inputs nixpkgs home-manager; };
    };
  };
}
