# Edit this configuration file to define what should be installed on
# your system.  Help is available in the configuration.nix(5) man page
# and in the NixOS manual (accessible by running `nixos-help`).

{ config, pkgs, inputs, ... }:

{
  imports =
    [ # Include the results of the hardware scan.
      ./hardware-configuration.nix
      ../../modules/linux.nix
      ../../modules/nix.nix
      ../../modules/base-pkgs.nix
      ../../modules/autoupgrade.nix
      ../../modules/time-utc.nix
      ../../modules/tailscale.nix

      ../../modules/plex.nix
      ../../modules/jellyfin.nix
      #../../modules/yt-dlp.nix
    ];

  # Read from /persist because that's available on boot for impermanence
  age.identityPaths = [ "/persist/etc/ssh/ssh_host_ed25519_key" ];

  age.secrets.github-access-token.file = ../../secrets/github-access-token.age;
  age.secrets.smb-media-credentials.file = ../../secrets/smb-media-credentials.age;
  age.secrets.watchlist.file = ../../secrets/watchlist.txt.age;
  age.secrets.user-mike-hashed-passwd.file = ../../secrets/user-mike-hashed-passwd.age;


  environment.persistence."/persist" = {
    files = [
      "/etc/adjtime"
      "/etc/ssh/ssh_host_ed25519_key"
      "/etc/ssh/ssh_host_ed25519_key.pub"
      "/etc/ssh/ssh_host_rsa_key"
      "/etc/ssh/ssh_host_rsa_key.pub"
      "/etc/machine-id"
    ];
    directories = [
      "/var/lib/containers/"
      "/var/lib/jellyfin/"
      "/var/lib/nixos/"
      "/var/lib/plex/"
      "/var/lib/tailscale/"
    ];
    hideMounts = true;
  };
  users.mutableUsers = false;

  # Use the systemd-boot EFI boot loader.
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  networking.hostName = "mallard"; # Define your hostname.

  # Define a user account. Don't forget to set a password with ‘passwd’.
  users.users.mike = {
    isNormalUser = true;
    extraGroups = [ "wheel" ]; # Enable ‘sudo’ for the user.
    packages = with pkgs; [
      tree
    ];
    hashedPasswordFile = "${config.age.secrets.user-mike-hashed-passwd.path}";
    openssh.authorizedKeys.keys = let
      authorizedKeys = pkgs.fetchurl {
        url = "https://github.com/kusold.keys";
        sha256 = "7Wt+i5OWJAVLKnZu8BoDgRHqQL0APJIBU5TSQ5TbsQE=";
      };
      in pkgs.lib.splitString "\n" (builtins.readFile authorizedKeys);
  };

  # List packages installed in system profile. To search, run:
  # $ nix search wget
  # environment.systemPackages = with pkgs; [
  #   vim # Do not forget to add an editor to edit configuration.nix! The Nano editor is also installed by default.
  #   wget
  # ];

  services.openssh.settings.PermitRootLogin = "yes";

  # This value determines the NixOS release from which the default
  # settings for stateful data, like file locations and database versions
  # on your system were taken. It's perfectly fine and recommended to leave
  # this value at the release version of the first install of this system.
  # Before changing this value read the documentation for this option
  # (e.g. man configuration.nix or on https://nixos.org/nixos/options.html).
  system.stateVersion = "23.05"; # Did you read the comment?

}

