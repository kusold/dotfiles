{ config, pkgs, ... }:

{
  imports =
    [ # Include the results of the hardware scan.
      ./hardware-configuration.nix
      ../../modules/linux.nix
      ../../modules/base-pkgs.nix
      ../../modules/autoupgrade.nix
      ../../modules/time-utc.nix
    ];

  nix.settings.experimental-features = [ "nix-command" "flakes" ];

  # Use the GRUB 2 boot loader.
  boot.loader.grub.enable = true;
  # Define on which hard drive you want to install Grub.
  boot.loader.grub.device = "/dev/vda"; # or "nodev" for efi only

  networking.hostName = "nix"; # Define your hostname.

  # Set your time zone.
  time.timeZone = "America/Denver";

  environment.systemPackages = with pkgs; [
    git
    vim # Do not forget to add an editor to edit configuration.nix! The Nano editor is also installed by default.
    wget
  ];

  services.qemuGuest.enable = true;

  # This value determines the NixOS release from which the default
  # settings for stateful data, like file locations and database versions
  # on your system were taken. It's perfectly fine and recommended to leave
  # this value at the release version of the first install of this system.
  # Before changing this value read the documentation for this option
  # (e.g. man configuration.nix or on https://nixos.org/nixos/options.html).
  system.stateVersion = "23.05"; # Did you read the comment?
  
    # Define a user account. Don't forget to set a password with ‘passwd’.
  users.users.mike = {
    isNormalUser = true;
    extraGroups = [ "wheel", "docker" ]; # Enable ‘sudo’ for the user.
    packages = with pkgs; [
      tree
    ];
    openssh.authorizedKeys.keys = let
      authorizedKeys = pkgs.fetchurl {
        url = "https://github.com/kusold.keys";
        sha256 = "7Wt+i5OWJAVLKnZu8BoDgRHqQL0APJIBU5TSQ5TbsQE=";
      };
      in pkgs.lib.splitString "\n" (builtins.readFile authorizedKeys);
  };
  
  virtualisation.docker.enable = true;
}