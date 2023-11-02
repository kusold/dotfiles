{ pkgs, ... }:
{
  # List packages installed in system profile. To search by name, run:
  # $ nix-env -qaP | grep wget
  environment.systemPackages =
    [ 
      pkgs.vim
      pkgs.vscode
    ];

  environment.darwinConfig = "$HOME/.config/home-manager/darwin-configuration.nix";

  # Auto upgrade nix package and the daemon service.
  services.nix-daemon.enable = true;
  nix.package = pkgs.nix;

  nixpkgs.hostPlatform = "aarch64-darwin";

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
  };
}
