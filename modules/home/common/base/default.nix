{ pkgs, ... }:

{
  programs.home-manager.enable = true;

  # Runs the repo's justfile (switch, deploy, bootstrap, secrets…).
  home.packages = [ pkgs.just ];
}
