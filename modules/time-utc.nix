{ config, lib, pkgs, modulesPath, ... }:
{
  time.timeZone = "Etc/UTC";

  system.autoUpgrade.rebootWindow.upper = "08:00";
  system.autoUpgrade.rebootWindow.lower = "00:00";
}