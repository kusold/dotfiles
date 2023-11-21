
{ config, pkgs, pkgs-unstable, lib, ... }:
{
  # Create group for NFS
  config.users.groups.media = {
    gid = 101337;
  };

  config.users.users.media = {
    uid = 101337;
    isSystemUser = true;
    createHome = false;
    group = "media";
  };
  
  config.environment.systemPackages = with pkgs; [ 
    cifs-utils 
  ];
  config.fileSystems."/mnt/storage/Media" = {
      device = "//192.168.20.10/Media";
      fsType = "cifs";
      options = let
        # this line prevents hanging on network split
        automount_opts = "x-systemd.automount,noauto,x-systemd.idle-timeout=60,x-systemd.device-timeout=5s,x-systemd.mount-timeout=5s";
        permission_opts = "uid=101337,gid=101337,forceuid,forcegid,file_mode=0664,dir_mode=0775";
        credenital_opts = "credentials=${config.age.secrets.smb-media-credentials.path}";
        additional_opts = "noexec";
      in ["${automount_opts},${permission_opts},${credenital_opts},${additional_opts}"];
  };

  config.system.activationScripts.makePlexTranscodeDir = lib.stringAfter [ "var" ] ''
    mkdir -p /dev/shm/transcodes
  '';

  # config.services.plex = {
  #   enable = true;
  #   package = pkgs-unstable.plex;
  #   openFirewall = true;
  #   user = "media";
  #   group = "media";
  # };
  config.virtualisation.oci-containers.containers.plex = {
    #image = "plexinc/pms-docker";
    image = "lscr.io/linuxserver/plex";
    extraOptions = [
      "--network=host"
      "--device=/dev/dri:/dev/dri"
    ];
    volumes = [
      "/mnt/storage/Media:/mnt/storage/Media"
      "/var/lib/plex/Plex\ Media\ Server:/config"
      "/dev/shm:/transcode"
    ];
    #user = "101337:101337";
    ports = [
      "32400:32400/tcp"
    ];
    autoStart = true;
    environment = {
      TZ = "Etc/UTC";
      PUID = "101337";
      PGID = "101337";
      VERSION = "docker";
    };
  };
}
