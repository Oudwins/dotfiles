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
    ./arr-sso.nix
  ];
  config.my.media_server.enable = true;
}
