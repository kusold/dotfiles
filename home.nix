{ config, lib, pkgs, pkgs-unstable, gui, inputs, ... }: {
    # Home Manager apps aren't indexed by Spotlight
    # https://github.com/nix-community/home-manager/issues/1341
   #home.activation = {
   #  # Makes apps show up in Spotlight
   #  # https://github.com/nix-community/home-manager/issues/1341#issuecomment-1791545015
   #  trampolineApps = let
   #    apps = pkgs.buildEnv {
   #      name = "home-manager-applications";
   #      paths = config.home.packages;
   #      pathsToLink = "/Applications";
   #    };
   #    mac-app-util = inputs.mac-app-util.packages.${pkgs.stdenv.system}.default;
   #  in lib.hm.dag.entryAfter [ "writeBoundary" ] ''
   #    fromDir="${apps}/Applications/"
   #    toDir="$HOME/Applications/Home Manager Trampolines"
   #    ${mac-app-util}/bin/mac-app-util sync-trampolines "$fromDir" "$toDir"
   #'';
   #};
    home.stateVersion = "23.05";
    home.packages = [
      pkgs.awscli2
      pkgs.bat
      pkgs.gh
      pkgs.htop
      pkgs.jq
      pkgs.k9s
      pkgs.ponysay
      pkgs.restic
      pkgs.ripgrep
      pkgs.ssh-copy-id
      pkgs.tree
      pkgs.unar
      
      pkgs.wget
      pkgs-unstable.yt-dlp
      pkgs.shellcheck
    ] ++ lib.optionals (gui) [
        pkgs-unstable.jetbrains.idea-ultimate
        pkgs.vscode
    ];
    programs.home-manager.enable = true;
    programs.git = {
      enable = true;
      includes = [{ path = "~/.config/home-manager/config/git/config"; }];
    };
    
    programs.kitty = {
      enable = if gui then true else false; # Yes, this could just be gui, but I'm still playing with how I want to structure this.
      darwinLaunchOptions = [
        "--single-instance"
      ];
      font.name = "FiraCode Nerd Font";
      font.size = 11;
      theme = "Dark One Nuanced";
      settings = {
        update_check_interval = 0;
        tab_bar_edge = "top";
        tab_bar_style = "powerline";
        macos_quit_when_last_window_closed = true;
        confirm_os_window_close = 0;
      };
    };
    programs.neovim = {
      enable = true;
      defaultEditor = true;
      viAlias = true;
      vimAlias = true;
      vimdiffAlias = true;
    };
    home.file."./.config/nvim/" = {
     source = ./config/nvim;
     recursive = true;
    };
    programs.zsh = {
      enable = true;
      # dotDir doesn't allow me to manage that directory myself
      #dotDir = ".config/zsh";
      initExtraFirst = ''
        export ZDOTDIR=~/.config/zsh
        . $ZDOTDIR/.zshenv
        . $ZDOTDIR/.zlogin
        . $ZDOTDIR/.zprofile
      '';
      initExtraBeforeCompInit = ''
        . $ZDOTDIR/.zshrc
      '';
    };
    home.file."./.config/zsh/" = {
     source = ./config/zsh;
     recursive = true;
    };

    home.file."./.config/hammerspoon/" = {
     source = ./config/hammerspoon;
     recursive = true;
    };

    home.file."./bin/" = {
     source = ./bin;
     recursive = true;
    };
}