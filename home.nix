{ pkgs, ... }: {
  home.username = "mkusold";
  home.homeDirectory = "/Users/mkusold";
  home.stateVersion = "23.11";
  programs.home-manager.enable = true;

  home.packages = [
    pkgs.ponysay
  ];
}
