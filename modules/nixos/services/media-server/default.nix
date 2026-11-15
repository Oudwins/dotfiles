{
  pkgs,
  config,
  lib,
  inputs,
  ...
}:
{
  imports = [
    ./custom.nix
  ];
  config.my.media_server.enable = true;
}
