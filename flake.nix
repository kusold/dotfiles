{
  description = "Home Manager configuration";

  inputs = {
    # Default to using stable for most packages
    nixpkgs.url = "github:nixos/nixpkgs/nixpkgs-23.05-darwin";
    # For packages that we want the latest, use unstable
    nixpkgs-unstable.url = "github:nixos/nixpkgs/nixpkgs-unstable";

    home-manager = {
      url = "github:nix-community/home-manager/release-23.05";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    nix-darwin = {
      url = "github:LnL7/nix-darwin/master";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { nixpkgs, nix-darwin, home-manager, ... }: let
    #arch = "x86_64-darwin";
    arch = "aarch64-darwin";
  in {
    defaultPackage.${arch} =
      home-manager.defaultPackage.${arch};

    darwinConfigurations."mq-mmkusold" = nix-darwin.lib.darwinSystem {
      modules = [
        home-manager.darwinModules.home-manager
        ./darwin-configuration.nix
      ];
    };
  };
}
