{ config, lib, ... }:

let
  cfg = config.services.cli-proxy-api;
  user = "_cliproxyapi";
in
{
  config = lib.mkIf cfg.enable {
    users.knownUsers = [ user ];
    users.knownGroups = [ user ];
    users.groups.${user}.gid = cfg.darwinUid;
    users.users.${user} = {
      uid = cfg.darwinUid;
      gid = cfg.darwinUid;
      home = cfg.stateDir;
      isHidden = true;
    };
    launchd.daemons.cli-proxy-api.serviceConfig = {
      ProgramArguments = [ (lib.getExe config.system.build.cli-proxy-api) ];
      KeepAlive = true;
      RunAtLoad = true;
      ThrottleInterval = 5;
      ProcessType = "Background";
      Umask = 63;
      SoftResourceLimits.Core = 0;
      HardResourceLimits.Core = 0;
      StandardOutPath = "/var/log/cli-proxy-api.log";
      StandardErrorPath = "/var/log/cli-proxy-api.error.log";
    };
  };
}
