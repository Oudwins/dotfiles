{
  config,
  pkgs,
  configLib,
  lib,
  inputs,
  ...
}@args:
{
  options.my.hardwareAcceleration = lib.mkOption {
    type = lib.types.submodule {
      options = {
        enable = lib.mkEnableOption "";
        LIBVA_DRIVER_NAME = lib.mkOption {
          type = lib.types.str;
          default = "iHD";
        };
        groups = lib.mkOption {
          type = lib.types.listOf lib.types.str;
          default = configLib.users.filterOutMissingGroups config [
            "video"
            "render"
            "input"
          ];
        };
      };
    };
    default = { };
  };
}
