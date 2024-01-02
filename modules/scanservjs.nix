
{ config, pkgs, pkgs-unstable, lib, ... }: let
  scanservjs = (pkgs.callPackage ../pkgs/scanservjs.nix {});
in {
  # Create group for NFS
  # config.users.groups.media = {
  #   gid = 101337;
  # };

  # config.users.users.media = {
  #   uid = 101337;
  #   isSystemUser = true;
  #   createHome = false;
  #   group = "media";
  # };
  
  config.environment.systemPackages = with pkgs; [ 
    cifs-utils 
  ];
  
  config.age.secrets.smb-scannerpi-credentials.file = ../secrets/smb-scannerpi-credentials.age;
  config.fileSystems."/mnt/paperless/consume" = {
      device = "//192.168.10.10/Filing Cabinet/consume";
      fsType = "cifs";
      options = let
        # this line prevents hanging on network split
        automount_opts = "x-systemd.automount,noauto,x-systemd.idle-timeout=60,x-systemd.device-timeout=5s,x-systemd.mount-timeout=5s";
        permission_opts = "uid=105001,gid=3003,forceuid,forcegid,file_mode=0664,dir_mode=0775";
        credenital_opts = "credentials=${config.age.secrets.smb-scannerpi-credentials.path}";
        additional_opts = "noexec";
      in ["${automount_opts},${permission_opts},${credenital_opts},${additional_opts}"];
  };

  # sane controls the scanner
  config.hardware.sane = {
    enable = true;
    # Fujitsu ScanSnap
    drivers.scanSnap.enable = true;
    # not necessary, but useful for debugging
    netConf = "localhost";
  };

  # saned exposes the scanner over the network to the hosts
  # that match the cidrs in the extraConfig. Launches a socket
  # that listens on port 6566
  config.services.saned = {
    enable = true;
    extraConfig = ''
    connect_timeout = 60

    localhost
    # Docker Network
    #172.16.0.0/12
    # Podman Network
    10.88.0.0/16
    host.containers.internal
    '';
  };

  # saned.socket
  config.networking.firewall.allowedTCPPorts = [ 6566 ];

  # saned launches as user scanner. In order for it to share the printer, the usb device
  # must be readable by that same group. Find idVender and idProduct with lsusb.
  config.services.udev = {
    enable = true;
    extraRules = ''
    SUBSYSTEMS=="usb", ATTRS{idVendor}=="04c5", ATTRS{idProduct}=="1632", GROUP="scanner"
    '';
  };

  # TODO: figure out a better way to add users to the scanner group
  # users.users.summit.extraGroups = [ "scanner" "lp" ];

  config.virtualisation.oci-containers.containers.scanservjs = {
    image = "sbs20/scanservjs:latest";
    extraOptions = [
      # "--privileged"
      # "--device=/dev/bus/usb/002/005:/dev/bus/usb/002/005"
    ];
    environment = {
      SANED_NET_HOSTS = "10.88.0.1";
    };
    volumes = [
      # TODO: Map to network share!
      "/mnt/paperless/consume:/var/lib/scanservjs/output"
    ];
    #user = "101337:101337";
    ports = [
      "8080:8080/tcp"
    ];
    autoStart = true;
  };
}
