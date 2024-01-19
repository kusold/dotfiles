{ config, lib, pkgs, modulesPath, ... }:
{
  
  system.autoUpgrade.enable = true;
  system.autoUpgrade.allowReboot = true;
  
  system.autoUpgrade.randomizedDelaySec = "45min";
  system.autoUpgrade.flake = "github:kusold/nix-config";
  system.autoUpgrade.dates = "daily";
  system.autoUpgrade.persistent = true;

  systemd.services."nixos-upgrade" = {
    onFailure = [ "healthchecks-monitor@nixos-upgrade-${config.networking.hostName}:failure.service" ];
    onSuccess = [ "healthchecks-monitor@nixos-upgrade-${config.networking.hostName}:success.service" ];
    wants = [ "multi-user.target" "healthchecks-monitor@nixos-upgrade-${config.networking.hostName}:start.service" ];
  };
}
