# Dell Optiplex 7060 MFF
# Core i7-8700T
# 32GB RAM
# 256GB minimum NVMe SSD

{ config, lib, pkgs, modulesPath, ... }:
{
  hardware.enableRedistributableFirmware = true;
  hardware.cpu.intel.updateMicrocode = lib.mkDefault config.hardware.enableRedistributableFirmware;

  # Hardware acceleration
  hardware.opengl = {
    enable = true;
    extraPackages = with pkgs; [
      intel-media-driver # LIBVA_DRIVER_NAME=iHD
      # Copied from https://github.com/NixOS/nixos-hardware/blob/b689465d0c5d88e158e7d76094fca08cc0223aad/common/gpu/intel/default.nix
      (if (lib.versionOlder (lib.versions.majorMinor lib.version) "23.11") then vaapiIntel else intel-vaapi-driver)
      #vaapiIntel         # LIBVA_DRIVER_NAME=i965 (older but works better for Firefox/Chromium)
      vaapiVdpau
      libvdpau-va-gl
    ];
  };
}