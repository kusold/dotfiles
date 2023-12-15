{
  description = "Home Manager configuration";

  inputs = {
    # Default to using stable for most packages
    nixpkgs.url = "github:nixos/nixpkgs/nixos-23.11";
    nixpkgs-darwin.url = "github:nixos/nixpkgs/nixpkgs-23.11-darwin";
    # For packages that we want the latest, use unstable
    nixpkgs-unstable.url = "github:nixos/nixpkgs/nixpkgs-unstable";

    home-manager = {
      url = "github:nix-community/home-manager/release-23.11";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    home-manager-unstable = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs-unstable";
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
    # Runs System & Home Configurations
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
    darwinConfigurations."Mikes-MacBook-Air" = mkSystem "mikes-macbook-air" rec {
      system = "aarch64-darwin";
      user = "mike";
      # user = "";
      gui = true;
    };
    darwinConfigurations."mq-mmkusold" = mkSystem "mq-mmkusold" rec {
      system = "aarch64-darwin";
      user = "mkusold";
      gui = true;
    };

    # Allows for updating just the user `nix build .#<USER>`
    homeConfigurations.mike = home-manager.lib.homeManagerConfiguration {
      inherit nixpkgs;
      modules = [
        ./home-manager/mike/home.nix
      ];
    };
    homeConfigurations.mkusold = home-manager.lib.homeManagerConfiguration {
      inherit nixpkgs;
      modules = [
        ./home-manager/mkusold/home.nix
      ];
    };
  };

  

}
