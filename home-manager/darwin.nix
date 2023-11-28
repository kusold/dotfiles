{ config, lib, pkgs, pkgs-unstable, inputs, ... }: {
  # Home Manager apps aren't indexed by Spotlight
  # https://github.com/nix-community/home-manager/issues/1341
  home.activation = {
    # Makes apps show up in Spotlight
    # https://github.com/nix-community/home-manager/issues/1341#issuecomment-1791545015
    trampolineApps = let
      apps = pkgs.buildEnv {
        name = "home-manager-applications";
        paths = config.home.packages;
        pathsToLink = "/Applications";
      };
      mac-app-util = inputs.mac-app-util.packages.${pkgs.stdenv.system}.default;
    in lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      fromDir="${apps}/Applications/"
      toDir="$HOME/Applications/Home Manager Trampolines"
      ${mac-app-util}/bin/mac-app-util sync-trampolines "$fromDir" "$toDir"
    '';
  };

  # Hammerspoon is a macOS automation tool that allows you to write Lua scripts
  home.file."./.config/hammerspoon/" = {
   source = ../config/hammerspoon;
   recursive = true;
  };
}
