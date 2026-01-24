{ config, pkgs, ... }:

{
  users.groups.tmx = { };
  users.groups.users = { };
  users.users.tmx = {
    isNormalUser = true;
    group = "tmx";
    description = "tmx";
    initialPassword = "pass";
    extraGroups = [
      "tmx"
      "users"
      "networkmanager"
      "wheel"
      "libvirtd"
      "docker"
      "video"
      "davfs2"
    ];
    packages = with pkgs; [
      nitrogen
      pkgs.nixfmt-rfc-style
    ];
  };
}
