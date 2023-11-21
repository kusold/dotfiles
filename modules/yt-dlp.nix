# FILEPATH: /Users/mike/Development/dotfiles/modules/yt-dlp.nix

{ config, lib, pkgs-unstable, ... }:
{
  systemd.timers."yt-dlp" = {
  wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = "daily";
      Persistent = true;
      Unit = "yt-dlp.service";
    };
  };

  systemd.services."yt-dlp" = {
    script = ''
      set -eu
      ${pkgs-unstable.yt-dlp}/bin/yt-dlp --help
      echo "${config.age.secrets.watchlist.path}";
    '';
    serviceConfig = {
      Type = "oneshot";
      User = "media";
    };
  };
}
