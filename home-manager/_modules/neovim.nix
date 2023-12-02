{ config, lib, pkgs, pkgs-unstable, gui, darwin, inputs, ... }@args: {
  programs.neovim = {
    enable = true;
    defaultEditor = true;
    viAlias = true;
    vimAlias = true;
    vimdiffAlias = true;
  };

  home.packages = with pkgs; [
    # Needed for various plugins to compile
    gcc
    gnumake
    go
    nodejs_20
    unzip
  ];

  home.file."./.config/nvim/" = {
    #  source = ../../config/nvim;
     source = config.lib.file.mkOutOfStoreSymlink "${config.home.homeDirectory}/.config/home-manager/config/nvim";
     recursive = false;
    };
    #home.file."./.config/nvim/lazy-lock.json" = {
    # source = config.lib.file.mkOutOfStoreSymlink "${config.home.homeDirectory}/.config/home-manager/config/nvim/lazy-lock.rw.json";
    # recursive = false;
    #};
}