{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.services.executor;
in
{
  options.services.executor = {
    enable = lib.mkEnableOption "Executor daemon";

    package = lib.mkPackageOption pkgs "executor" { };

    user = lib.mkOption {
      type = lib.types.str;
      default = "executor";
      description = "User to run the Executor daemon as.";
    };

    group = lib.mkOption {
      type = lib.types.str;
      default = "executor";
      description = "Group to run the Executor daemon as.";
    };

    dataDir = lib.mkOption {
      type = lib.types.str;
      default = "/var/lib/executor";
      description = "Directory where Executor stores daemon state, auth, and logs.";
    };

    scopeDir = lib.mkOption {
      type = lib.types.str;
      default = "/var/lib/executor";
      description = "Executor daemon scope directory.";
    };

    port = lib.mkOption {
      type = lib.types.port;
      default = 4789;
      description = "Loopback port for the supervised Executor service.";
    };

    openFirewall = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Open the Executor service port in the firewall.";
    };
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages = [ cfg.package ];

    users.groups = lib.mkIf (cfg.group == "executor") {
      executor = { };
    };

    users.users = lib.mkIf (cfg.user == "executor") {
      executor = {
        isSystemUser = true;
        group = cfg.group;
        home = cfg.dataDir;
      };
    };

    systemd.tmpfiles.rules = [
      "d ${cfg.dataDir} 0700 ${cfg.user} ${cfg.group} - -"
    ];

    systemd.services.executor = {
      description = "Executor daemon";
      wantedBy = [ "multi-user.target" ];
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];

      environment = {
        EXECUTOR_SUPERVISED = "1";
        EXECUTOR_DATA_DIR = cfg.dataDir;
        EXECUTOR_SCOPE_DIR = cfg.scopeDir;
        EXECUTOR_SERVICE_VERSION = cfg.package.version;
        HOME = cfg.dataDir;
        PORT = toString cfg.port;
      };

      serviceConfig = {
        User = cfg.user;
        Group = cfg.group;
        ExecStart = "${lib.getExe cfg.package} daemon run --foreground";
        Restart = "on-failure";
        RestartSec = 5;
        WorkingDirectory = cfg.dataDir;
      };
    };

    networking.firewall.allowedTCPPorts = lib.mkIf cfg.openFirewall [ cfg.port ];
  };
}
