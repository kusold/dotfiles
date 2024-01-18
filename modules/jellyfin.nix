{ config, pkgs, pkgs-unstable, lib, ... }:
{
  environment.systemPackages = [
    pkgs.jellyfin
    pkgs.jellyfin-web
    pkgs.jellyfin-ffmpeg
  ];

  services.jellyfin = {
    enable = true;
    openFirewall = true;
    group = "media";
  };

  ###
  # Jellyplex-Watched syncs Watch Status between Jellyfin and Plex
  ###
  users.groups.jellyplexwatched = {
    gid = 8090;
  };
  users.users.jellyplexwatched = {
    uid = 8090;
    isSystemUser = true;
    createHome = false;
    group = "jellyplexwatched";
  };

  age.secrets.jellyplex-watched-env = {
    file = ../secrets/app-jellyplex-watched.age;
    # jellyplex-watched uses python-dotenv. That library attempts to open the .env file win RW mode.
    mode = "770";
    owner = "${config.users.users.jellyplexwatched.name}";
    group = "${config.users.groups.jellyplexwatched.name}";
  };

  virtualisation.oci-containers.containers."jellyplex-watched" = {
    image = "luigi311/jellyplex-watched:latest";
    volumes = [
      "${config.age.secrets.jellyplex-watched-env.path}:/app/.env"
    ];
    user = "${toString config.users.users.jellyplexwatched.uid}:${toString config.users.groups.jellyplexwatched.gid}";
    autoStart = true;
    # environmentFiles = [
      # config.age.secrets.jellyplex-watched-env.path
    # ];
    environment = {
      ## Do not mark any shows/movies as played and instead just output to log if they would of been marked.
      DRYRUN = "False";
      ## If set to true then the script will only run once and then exit
      RUN_ONLY_ONCE = "False";
      DEBUG = "False";
      DEBUG_LEVEL = "debug";
      # Specify a different version because we are setting the user on the container
      LOGFILE = "/tmp/log.log";
      MARKFILE = "/tmp/mark.log";
      ## How often to run the script in seconds
      # SLEEP_DURATION = "3600";
      ## Max threads for processing
      MAX_THREADS = "32";
      SSL_BYPASS = "True";
      SYNC_FROM_PLEX_TO_JELLYFIN = "True";
      SYNC_FROM_JELLYFIN_TO_PLEX = "False";
      SYNC_FROM_PLEX_TO_PLEX = "True";
      SYNC_FROM_JELLYFIN_TO_JELLYFIN = "True";
      #USER_MAPPING = { "testuser2": "testuser3", "testuser1":"testuser4" }
    #   TZ = "Etc/UTC";
    #   PUID = "101337";
    #   PGID = "101337";
    #   VERSION = "docker";
    };
  };
}
