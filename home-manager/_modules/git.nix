{ config, lib, pkgs, pkgs-unstable, gui, darwin, inputs, ... }@args: {
  programs.git = {
    enable = true;
    includes = [{ path = "~/.config/home-manager/config/git/config"; }];
  };
}