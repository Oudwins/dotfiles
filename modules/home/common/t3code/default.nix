# T3 Code server as a systemd user service, for hosts reached remotely (behind
# nginx). Workstations run the desktop app instead, which brings its own server.
{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.services.t3code;
in
{
  options.services.t3code = {
    enable = lib.mkEnableOption "T3 Code server";
    package = lib.mkOption {
      type = lib.types.package;
      default = pkgs.t3code;
      description = "T3 Code package.";
    };
    host = lib.mkOption {
      type = lib.types.str;
      default = "127.0.0.1";
      description = "Address the server listens on.";
    };
    port = lib.mkOption {
      type = lib.types.port;
      default = 3773;
      description = "Port the server listens on.";
    };
  };

  config = lib.mkIf cfg.enable {
    # `t3 pair`, `t3 auth` and friends talk to the running server.
    home.packages = [ cfg.package ];

    systemd.user.services.t3code = {
      Unit = {
        Description = "T3 Code server";
        After = [ "network-online.target" ];
        Wants = [ "network-online.target" ];
      };
      Service = {
        WorkingDirectory = config.home.homeDirectory;
        Environment = [ "T3CODE_HOME=${config.home.homeDirectory}/.t3" ];
        ExecStart = "${lib.getExe cfg.package} serve --host ${cfg.host} --port ${toString cfg.port} --no-browser";
        # As in the unit `t3 service install` writes.
        KillMode = "mixed";
        Restart = "always";
        RestartSec = 5;
      };
      Install.WantedBy = [ "default.target" ];
    };
  };
}
