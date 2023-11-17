{ config, lib, pkgs, modulesPath, ... }:
{
  # Set your time zone.
  time.timeZone = "America/Denver";

  system.autoUpgrade.rebootWindow.upper = "05:00";
  system.autoUpgrade.rebootWindow.lower = "01:00";
}