{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.services.mcp-auth-proxy;
  # Strategy commands (gcloud, jq, ...) run with the service's environment, and
  # launchd/systemd user units start with a minimal PATH.
  servicePath = lib.concatStringsSep ":" [
    "/run/current-system/sw/bin"
    "/etc/profiles/per-user/${config.home.username}/bin"
    "${config.home.profileDirectory}/bin"
    "/usr/bin"
    "/bin"
    "/usr/sbin"
    "/sbin"
  ];
in
{
  options.services.mcp-auth-proxy = {
    enable = lib.mkEnableOption "mcp-auth-proxy user service";
    package = lib.mkOption {
      type = lib.types.package;
      default = pkgs.mcp-auth-proxy;
      description = "mcp-auth-proxy package to use.";
    };
    configFile = lib.mkOption {
      type = lib.types.str;
      default = "${config.home.homeDirectory}/.mcp-auth-proxy/config.yaml";
      description = "YAML configuration holding the listen address, allowedHosts and strategies, managed outside Nix (with Stow). The listen port lives there.";
    };
    environment = lib.mkOption {
      type = lib.types.attrsOf lib.types.str;
      default = { };
      description = "Extra environment for the service, such as values the config reads with \${env:NAME}.";
    };
  };

  config = lib.mkIf cfg.enable {
    home.packages = [ cfg.package ];

    systemd.user.services.mcp-auth-proxy = lib.mkIf pkgs.stdenv.hostPlatform.isLinux {
      Unit = {
        Description = "mcp-auth-proxy";
        After = [ "network-online.target" ];
        Wants = [ "network-online.target" ];
      };
      Service = {
        ExecStart = "${lib.getExe cfg.package} http -c ${lib.escapeShellArg cfg.configFile}";
        Environment = [ "PATH=${servicePath}" ] ++ lib.mapAttrsToList (name: value: "${name}=${value}") cfg.environment;
        Restart = "always";
        RestartSec = 5;
      };
      Install.WantedBy = [ "default.target" ];
    };

    launchd.agents.mcp-auth-proxy = lib.mkIf pkgs.stdenv.hostPlatform.isDarwin {
      enable = true;
      config = {
        ProgramArguments = [
          (lib.getExe cfg.package)
          "http"
          "-c"
          cfg.configFile
        ];
        EnvironmentVariables = { PATH = servicePath; } // cfg.environment;
        KeepAlive = true;
        RunAtLoad = true;
        ThrottleInterval = 5;
        ProcessType = "Background";
        StandardOutPath = "${config.home.homeDirectory}/Library/Logs/mcp-auth-proxy.log";
        StandardErrorPath = "${config.home.homeDirectory}/Library/Logs/mcp-auth-proxy.error.log";
      };
    };
  };
}
