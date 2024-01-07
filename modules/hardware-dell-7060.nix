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
}