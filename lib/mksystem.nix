# This function creates a NixOS system based on our VM setup for a
# particular architecture.
{ nixpkgs, inputs }:

name:
{
  system,
  user,
  gui,
}:
let
  darwin = nixpkgs.lib.strings.hasInfix "darwin" system;
  in
let
  # The config files for this system.
  hostConfig = ../hosts/${name}.nix;
  homeConfig = ../home.nix;


  # NixOS vs nix-darwin functionst
  systemFunc = if darwin then inputs.nix-darwin.lib.darwinSystem else nixpkgs.lib.nixosSystem;
  home-manager = if darwin then inputs.home-manager.darwinModules else inputs.home-manager.nixosModules;

  # Linux vs Darwin Packages
  pkgs = if darwin then inputs.nixpkgs-darwin.legacyPackages.${system} else nixpkgs.legacyPackages.${system};
  pkgs-unstable = inputs.nixpkgs-unstable.legacyPackages.${system};
in systemFunc rec {
  inherit system;

  modules = [ 
    # Apply our overlays. Overlays are keyed by system type so we have
    # to go through and apply our system type. We do this first so
    # the overlays are available globally.
    # { nixpkgs.overlays = overlays; }

    hostConfig
    home-manager.home-manager {
      # home-manager.useGlobalPkgs = true;
      # home-manager.useUserPackages = true;
      home-manager.users.${user}.imports = [({config, lib, ... }: import homeConfig {
        pkgs = pkgs;
        pkgs-unstable = pkgs-unstable;
        gui = gui;
        inputs = inputs;
        config = config;
        lib = lib;
      })];
    }

    # We expose some extra arguments so that our modules can parameterize
    # better based on these values.
    {
      config._module.args = {
        currentSystem = system;
        currentSystemName = name;
        inputs = inputs;
      };
    }
  ];
}