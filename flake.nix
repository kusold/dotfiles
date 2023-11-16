{
  description = "Home Manager configuration";

  inputs = {
    # Default to using stable for most packages
    nixpkgs.url = "github:nixos/nixpkgs/nixos-23.05";
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
    agenix.url = "github:ryantm/agenix";
  };

  outputs = { nixpkgs, nixpkgs-unstable, nixpkgs-darwin, nix-darwin, home-manager, mac-app-util, ... }@inputs: let
    #arch = "x86_64-darwin";
#    arch = "aarch64-darwin";
#    pkgs = nixpkgs.legacyPackages.${arch};
#    pkgs-unstable = nixpkgs-unstable.legacyPackages.${arch};

    mkSystem = import ./lib/mksystem.nix {
      inherit nixpkgs inputs;
    };
  in {
    
    nixosConfigurations."nix" = mkSystem "nix" rec {
      system = "x86_64-linux";
      user = "mike";
      gui = false;
    };
    nixosConfigurations."mallard" = mkSystem "mallard" rec {
      system = "x86_64-linux";
      user = "mike";
      gui = false;
    };
    nixosConfigurations."mikes-desktop" = mkSystem "mikes-desktop" rec {
      system = "x86_64-linux";
      user = "mike";
      gui = true;
    };
    nixosConfigurations."yuki" = mkSystem "yuki" rec {
      system = "x86_64-linux";
      user = "mike";
      gui = true;
    };
    darwinConfigurations."mq-mmkusold" = mkSystem "mq-mmkusold" rec {
      system = "aarch64-darwin";
      user = "mkusold";
      gui = true;
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
  };
}
