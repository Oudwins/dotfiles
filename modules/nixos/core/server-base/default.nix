{
  config,
  pkgs,
  configLib,
  lib,
  inputs,
  ...
}@args:
{
  imports = [
    ./hardware-acceleration.nix
  ];
  # CONFIG
  nix.settings.experimental-features = [
    "nix-command"
    "flakes"
  ];

  nixpkgs.config = {
    allowUnfree = true;
  };

  environment.systemPackages = with pkgs; [
    vim
    git
  ];

}
