{ config, lib, pkgs, modulesPath, ... }:
{
  
  system.autoUpgrade.enable = true;
  system.autoUpgrade.allowReboot = true;
  
  system.autoUpgrade.randomizedDelaySec = "45min";
  system.autoUpgrade.flake = "github:kusold/dotfiles/master";
  system.autoUpgrade.dates = "daily";
  system.autoUpgrade.persistent = true;
}
