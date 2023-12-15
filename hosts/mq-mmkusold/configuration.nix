{ pkgs, inputs, currentSystemName, ... }:
{
  # List packages installed in system profile. To search by name, run:
  # $ nix-env -qaP | grep wget
  environment.systemPackages =
    [ 
      pkgs.vim
      

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
    iosevka
    monaspace
  ];

  environment.darwinConfig = "$HOME/.config/home-manager/hosts/${currentSystemName}.nix";

  # This kept triggering security alerts
  # A process attempted to stop or kill the Background Task Management Agent, possibly to establish persistence without user notification.
  # Auto upgrade nix package and the daemon service.
  #services.nix-daemon.enable = true;
  #nix.package = pkgs.nix;

  nixpkgs.hostPlatform = "aarch64-darwin";

  system.keyboard.enableKeyMapping = true;
  system.keyboard.remapCapsLockToEscape = true;
  system.defaults.CustomUserPreferences = {
  #defaults write org.hammerspoon.Hammerspoon MJConfigFile "~/.config/hammerspoon/init.lua"
    "org.hammerspoon.Hammerspoon" = {
      MJConfigFile = "~/.config/hammerspoon/init.lua";
    };
  };
  system.defaults.dock = {
    orientation = "right";
    magnification = true;
    largesize = 16;
    mru-spaces = false;
    show-recents = false;
  };
  system.defaults.NSGlobalDomain.ApplePressAndHoldEnabled = true;
  security.pam.enableSudoTouchIdAuth = true;

  # Create /etc/zshrc that loads the nix-darwin environment.
  programs.zsh.enable = true;  # default shell on catalina
  # programs.fish.enable = true;

  homebrew = {
    enable = true;
    casks = [
      "1password"
      "docker"
      "focus"
      "hammerspoon"
      "openlens"
      "qbserve"
      "vlc"
      "zoom"
    ];
    masApps = {
      "Amphetamine" = 937984704;
    };
  };

  nixpkgs.config = {
    allowUnfree = true;
    #allowUnfreePredicate = (_: true);
  };
#  nixpkgs.config.allowUnfreePredicate = pkg: builtins.elem (lib.getName pkg) [
#    "code"
#  ];

  users.users.mkusold = {
    name = "mkusold";
    home = "/Users/mkusold";
    openssh.authorizedKeys.keys = [
      "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABgQC9Gr/FM9ZbYxHm8pULpsvAhCsJj1AGYP+BVNU2hR1awY77KyOPu95elA2kfi2+0n0sl2gK9yeU2GwfS+L9SkZxEl5Tw8nzac1DZ07KU0GVnORkXMPjnkSKMtUKahmRYzAQCtgcflLhTDL5HAAcIhdFGGnnGtGscoYXqTaWkCf8mQTshIaG3XPGT1nxk2qJDPl8Svaw4RLnQ1hKZLR2BoJO911hhXnlWRpIp+3O+sYqglM63mHFtO6m4IeUwfmO9VF90TTysP2dAPrHXH1Yz1gYwg0JuaWohUs7DJM9255r13Mt++MKy5F+Owuv855Bl99xY3fB2TgZ9hDrQRZV8qJ9W7WvJZNWIuuCkfOfIBKIJNtx95qdGPN41FbHNX7rBwwVH/SHPpIDEfUeOW+80lL2xNIZINMQzFnsX6cqT1s+p7nu3bI5kSFydcEz1Of5CUTEVex2q3bErOxzDSNAVXgGy9gzSRsesAxI50cTswR8vU7YGQphrWN0tgduSxN3tcM="
    ];
  };
}
