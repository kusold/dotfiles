# Dell Optiplex 7060 MFF
# Core i7-8700T
# 32GB RAM
# 256GB minimum NVMe SSD

{ config, lib, pkgs, inputs, ... }:
{
  hardware.enableRedistributableFirmware = true;

  imports = [
    # Update CPU microcode
    inputs.nixos-hardware.nixosModules.common-cpu-intel
    # Allows for GPU Hardware Acceleration
    inputs.nixos-hardware.nixosModules.common-gpu-intel
    # Enable Trim
    inputs.nixos-hardware.nixosModules.common-pc-ssd
  ];

  # Enable Intel Quick Sync Video
  # https://wiki.archlinux.org/title/intel_graphics
  boot.kernelParams = [ "i915.enable_guc=2" ];
  hardware.opengl = {
    enable = true;
    extraPackages = with pkgs; [
      intel-media-driver
      intel-compute-runtime
    ];
  };

  environment.systemPackages = with pkgs; [
    intel-gpu-tools # intel_gpu_top lets you see gpu utilization
  ];
}