{ config, lib, ... }:

let
  cfg = config.services.cli-proxy-api;
in
{
  config = lib.mkIf cfg.enable {
    users.groups.cli-proxy-api = { };
    users.users.cli-proxy-api = {
      isSystemUser = true;
      group = "cli-proxy-api";
      home = cfg.stateDir;
    };
    systemd.tmpfiles.rules = [
      "d ${cfg.stateDir} 0700 cli-proxy-api cli-proxy-api - -"
    ];
    systemd.services.cli-proxy-api = {
      description = "CLIProxyAPI";
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];
      wantedBy = [ "multi-user.target" ];
      serviceConfig = {
        # Root prepares credentials; the launcher permanently drops UID/GID before exec.
        ExecStart = lib.getExe config.system.build.cli-proxy-api;
        Group = "cli-proxy-api";
        RuntimeDirectory = "cli-proxy-api";
        RuntimeDirectoryMode = "0750";
        RuntimeDirectoryPreserve = "restart";
        ReadWritePaths = [
          "/run/cli-proxy-api"
          cfg.stateDir
        ];
        ProtectSystem = "strict";
        NoNewPrivileges = true;
        LimitCORE = 0;
        # Upstream can exit successfully even when configuration loading fails.
        Restart = "always";
        RestartSec = 5;
        UMask = "0077";
      };
    };
  };
}
