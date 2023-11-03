{ pkgs, pkgs-unstable, ... }:
{
  # List packages installed in system profile. To search by name, run:
  # $ nix-env -qaP | grep wget
  environment.systemPackages =
    [ 
      pkgs-unstable.jetbrains.idea-ultimate
      pkgs.vim
      pkgs.vscode

      # required for neovim
      pkgs.luajit
      pkgs.nodePackages.diagnostic-languageserver
      pkgs.nodePackages.eslint
      pkgs.nodePackages.dockerfile-language-server-nodejs
      pkgs.sqls
      pkgs.gopls
      pkgs.docker-compose-language-service
      pkgs.nodePackages.bash-language-server
      pkgs.ansible-language-server
      pkgs.nodePackages.vscode-json-languageserver
      pkgs.nodePackages.typescript-language-server
      pkgs.nodePackages.yaml-language-server
      pkgs.nodejs_20
      pkgs.go
    ];

  fonts.fontDir.enable = true;
  fonts.fonts = with pkgs; [
    (nerdfonts.override { fonts = [ "FiraCode" "Hack" "JetBrainsMono" "SourceCodePro" "NerdFontsSymbolsOnly" ]; })
  ];

  environment.darwinConfig = "$HOME/.config/home-manager/darwin-configuration.nix";

  # Auto upgrade nix package and the daemon service.
  services.nix-daemon.enable = true;
  nix.package = pkgs.nix;

  nixpkgs.hostPlatform = "aarch64-darwin";

  system.keyboard.enableKeyMapping = true;
  system.keyboard.remapCapsLockToEscape = true;
  system.defaults.dock = {
    orientation = "right";
    magnification = true;
    largesize = 16;
    mru-spaces = false;
    show-recents = false;
  };

  # Create /etc/zshrc that loads the nix-darwin environment.
  programs.zsh.enable = true;  # default shell on catalina
  # programs.fish.enable = true;

  homebrew = {
    enable = true;
    casks = [
      "1password"
    ];
    masApps = {
      "Amphetamine" = 937984704;
    };
  };

  nixpkgs.config = {
    allowUnfree = true;
    allowUnfreePredicate = (_: true);
  };
#  nixpkgs.config.allowUnfreePredicate = pkg: builtins.elem (lib.getName pkg) [
#    "code"
#  ];

  users.users.mkusold = {
    name = "mkusold";
    home = "/Users/mkusold";
  };
  home-manager.users.mkusold = { pkgs, ... }: {
    home.stateVersion = "23.05";
    home.packages = [
      pkgs.ponysay
    ];
    programs.home-manager.enable = true;
    programs.git = {
      enable = true;
      includes = [{ path = "~/.config/home-manager/config/git/config"; }];
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
  };
}
