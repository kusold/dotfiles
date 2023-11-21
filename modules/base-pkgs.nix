
{ config, pkgs, ... }:
{
  environment.systemPackages = with pkgs; [
    git
    htop
    vim
  ];
}
