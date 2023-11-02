{ pkgs, ... }: {
  home.username = "mkusold";
  home.homeDirectory = "/Users/mkusold";
  home.stateVersion = "23.05";
  programs.home-manager.enable = true;

  home.packages = [
    pkgs.ponysay
  ];

  programs.git = {
    enable = true;
    includes = [{ path = "~/.config/home-manager/config/git/config"; }];
  };

}
