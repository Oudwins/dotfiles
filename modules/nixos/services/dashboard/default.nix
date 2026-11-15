{
  config,
  pkgs,
  lib,
  ...
}:
{
  imports = [
    ./homepage.nix
    ./dashboardConfig.nix
  ];
  config.my.dashboard.enable = true;
}
