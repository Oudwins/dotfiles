{
  config,
  pkgs,
  lib,
  ...
}:
# ! Configure Dashboard
let
  services = builtins.attrValues config.my.dashboard.services;
in
{
  options.my.dashboard = lib.mkOption {
    type = lib.types.submodule {
      options = {
        enable = lib.mkEnableOption "";
        services = lib.mkOption {
          type = lib.types.attrsOf (
            lib.types.submodule {
              options = {
                icon = lib.mkOption {
                  type = lib.types.str;
                  default = "";
                };
                label = lib.mkOption {
                  type = lib.types.str;
                };
                url = lib.mkOption {
                  type = lib.types.str;
                };
                description = lib.mkOption {
                  type = lib.types.str;
                  default = "";
                };
                category = lib.mkOption {
                  type = lib.types.enum [
                    "system"
                    "apps"
                    "media"
                    "management"
                  ];
                };
              };
            }
          );
        };
      };
    };
    default = { };
  };

}
