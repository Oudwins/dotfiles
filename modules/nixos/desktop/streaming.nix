{ lib, pkgs, ... }:

{
  programs.obs-studio = {
    enable = true;
    enableVirtualCamera = true;
  };

  boot.extraModprobeConfig = lib.mkForce ''
    options v4l2loopback devices=1 video_nr=0 card_label="AAA Photo Camera" exclusive_caps=1
  '';

  environment.systemPackages = [ pkgs.v4l-utils ];
}
