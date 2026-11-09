{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.services.pr-review-server;
  # The server shells out to gh, and launchd/systemd user units start with a
  # minimal PATH.
  servicePath = lib.concatStringsSep ":" [
    "/run/current-system/sw/bin"
    "/etc/profiles/per-user/${config.home.username}/bin"
    "${config.home.profileDirectory}/bin"
    "/usr/bin"
    "/bin"
  ];
  args = [
    (lib.getExe cfg.package)
    "-addr"
    "127.0.0.1:${toString cfg.port}"
  ];
in
{
  options.services.pr-review-server = {
    enable = lib.mkEnableOption "pr-review-server user service";
    package = lib.mkOption {
      type = lib.types.package;
      default = pkgs.pr-review-server;
      description = "pr-review-server package to use.";
    };
    port = lib.mkOption {
      type = lib.types.port;
      default = 7457;
      description = "Loopback port the pr-review-doc pages are served on.";
    };
  };

  config = lib.mkIf cfg.enable {
    systemd.user.services.pr-review-server = lib.mkIf pkgs.stdenv.hostPlatform.isLinux {
      Unit.Description = "pr-review-server";
      Service = {
        ExecStart = lib.escapeShellArgs args;
        Environment = [ "PATH=${servicePath}" ];
        Restart = "always";
        RestartSec = 5;
      };
      Install.WantedBy = [ "default.target" ];
    };

    launchd.agents.pr-review-server = lib.mkIf pkgs.stdenv.hostPlatform.isDarwin {
      enable = true;
      config = {
        ProgramArguments = args;
        EnvironmentVariables.PATH = servicePath;
        KeepAlive = true;
        RunAtLoad = true;
        ThrottleInterval = 5;
        ProcessType = "Background";
        StandardOutPath = "${config.home.homeDirectory}/Library/Logs/pr-review-server.log";
        StandardErrorPath = "${config.home.homeDirectory}/Library/Logs/pr-review-server.error.log";
      };
    };
  };
}
