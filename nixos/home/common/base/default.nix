{ config, ... }:

{
  home.username = "tmx";
  home.homeDirectory = "/home/tmx";

  programs.home-manager.enable = true;
}
