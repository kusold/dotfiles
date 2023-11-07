{
  description = "Home Manager configuration";

  inputs = {
    # Default to using stable for most packages
    nixpkgs.url = "github:nixos/nixpkgs/nixpkgs-23.05";
    nixpkgs-darwin.url = "github:nixos/nixpkgs/nixpkgs-23.05-darwin";
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

    mac-app-util.url = "github:hraban/mac-app-util";
  };

  outputs = { nixpkgs, nixpkgs-unstable, nix-darwin, home-manager, mac-app-util, ... }@inputs: let
    #arch = "x86_64-darwin";
#    arch = "aarch64-darwin";
#    pkgs = nixpkgs.legacyPackages.${arch};
#    pkgs-unstable = nixpkgs-unstable.legacyPackages.${arch};
  in {
    nixosConfigurations."nix" = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      modules = [
        ./nix-configuration.nix
      ];
      specialArgs = {
        inherit pkgs-unstable;
        inherit inputs;
      };
    };

#    defaultPackage.${arch} =
#      home-manager.defaultPackage.${arch};
#
#    inherit pkgs;
#    darwinConfigurations."mq-mmkusold" = nix-darwin.lib.darwinSystem {
#      system = "aarch64-darwin";
#      modules = [
#        inputs.home-manager.darwinModules.home-manager
#        ./darwin-configuration.nix
#      ];
#      specialArgs = {
#        inherit pkgs-unstable;
#        inherit inputs;
#      };
#    };
#  };
}
