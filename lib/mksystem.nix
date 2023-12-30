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




  # Get the proper versions depending on if it is darwin or linux.
  systemFunc = if darwin then inputs.nix-darwin.lib.darwinSystem else nixpkgs.lib.nixosSystem;
  home-manager = if darwin then inputs.home-manager.darwinModules else inputs.home-manager.nixosModules;
  agenix = if darwin then inputs.agenix.darwinModules else inputs.agenix.nixosModules;
  darwin-pkgs = import inputs.nixpkgs-darwin {
    system = system;
    config.allowUnfree = true;
  };
  pkgs = if darwin then darwin-pkgs else import nixpkgs {
    system = system;
    config.allowUnfree = true;
    config.packageOverrides = pkgs: {
      vaapiIntel = pkgs.vaapiIntel.override { enableHybridCodec = true; };
    };
  };
  pkgs-unstable = import inputs.nixpkgs-unstable {
    system = system;
    config.allowUnfree = true;
    config.permittedInsecurePackages = [
      "googleearth-pro-7.3.4.8248"
    ];
  };
  lib = pkgs.lib;

  # The config files for this system.
  hostConfig = ../hosts/${name}/configuration.nix;
  homeConfig = ../home-manager/${user}/home.nix;

in systemFunc rec {
  inherit system;

  modules = [
    # Apply our overlays. Overlays are keyed by system type so we have
    # to go through and apply our system type. We do this first so
    # the overlays are available globally.
    # { nixpkgs.overlays = overlays; }
    # { nixpkgs.config.allowUnfree = true; }
    hostConfig
    agenix.default
    {
      environment.systemPackages = [
        inputs.agenix.packages."${system}".default
      ];
    }

    # We expose some extra arguments so that our modules can parameterize
    # better based on these values.
    {
      config._module.args = {
        currentSystem = system;
        currentSystemName = name;
        inputs = inputs;
        pkgs-unstable = pkgs-unstable;
      };
    }
  ] ++ lib.optionals(user != "") [
    home-manager.home-manager {
      home-manager.useGlobalPkgs = true;
      home-manager.useUserPackages = true;
      home-manager.users.${user}.imports = [({config, lib, ... }: import homeConfig {
        pkgs = pkgs;
        pkgs-unstable = pkgs-unstable;
        gui = gui;
        inputs = inputs;
        config = config;
        lib = lib;
        darwin = darwin;
      })];
    }
  ];
}
