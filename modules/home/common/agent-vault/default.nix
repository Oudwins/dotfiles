{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.services.agent-vault;
  runner = pkgs.agent-vault-service.override { agent-vault = cfg.package; };
  modes = {
    agent-vault = "server";
    agent-vault-credentials = "credentials";
    executor-router = "router";
  };
  arguments =
    mode:
    if mode == "router" then
      [
        "${pkgs.executor-router}/bin/executor-router"
        cfg.configFile
      ]
    else
      [
        "${runner}/bin/agent-vault-service"
        mode
        "--config"
        cfg.configFile
      ];
  environment = {
    AGENT_VAULT_TELEMETRY = "false";
    AGENT_VAULT_NETWORK_ALLOWLIST = "127.0.0.1/32,::1/128";
  }
  // cfg.environment;
in
{
  options.services.agent-vault = {
    enable = lib.mkEnableOption "Agent Vault, credential helper, MCP router and proxied coding-agent launchers";
    package = lib.mkOption {
      type = lib.types.package;
      default = pkgs.agent-vault;
      description = "Agent Vault package.";
    };
    configFile = lib.mkOption {
      type = lib.types.str;
      default = "${config.home.homeDirectory}/.config/agent-vault/config.json";
      description = "Stow-managed configuration for proxy ports, credential sources and upstream services.";
    };
    environment = lib.mkOption {
      type = lib.types.attrsOf lib.types.str;
      default = { };
      description = "Service environment, including the machine's Executor endpoint.";
    };
  };

  config = lib.mkIf cfg.enable {
    home.packages = [
      cfg.package
      runner
      pkgs.agent-vault-clients
      pkgs.executor-router
    ];

    home.sessionPath = [ "${pkgs.agent-vault-clients}/bin" ];
    # The agents remain manually installed under ~/.npm. These launchers take
    # precedence even on macOS, where the shell prepends that npm directory.
    programs.zsh.envExtra = lib.mkAfter ''
      export PATH="${pkgs.agent-vault-clients}/bin:$PATH"
    '';
    programs.bash.bashrcExtra = lib.mkAfter ''
      export PATH="${pkgs.agent-vault-clients}/bin:$PATH"
    '';

    systemd.user.services = lib.mkIf pkgs.stdenv.hostPlatform.isLinux (
      lib.mapAttrs (name: mode: {
        Unit = {
          Description = name;
          After = [
            "network-online.target"
          ]
          ++ lib.optional (mode == "credentials") "agent-vault.service"
          ++ lib.optional (mode == "router") "agent-vault-credentials.service";
          Wants = [
            "network-online.target"
          ]
          ++ lib.optional (mode == "router") "agent-vault-credentials.service";
        }
        // lib.optionalAttrs (mode == "credentials") { PartOf = [ "agent-vault.service" ]; };
        Service = {
          ExecStart = lib.escapeShellArgs (arguments mode);
          Environment = lib.mapAttrsToList (key: value: "${key}=${value}") environment;
          Restart = "always";
          RestartSec = 5;
          UMask = "0077";
        };
        Install.WantedBy = [ "default.target" ];
      }) modes
    );

    launchd.agents = lib.mkIf pkgs.stdenv.hostPlatform.isDarwin (
      lib.mapAttrs (name: mode: {
        enable = true;
        config = {
          ProgramArguments = arguments mode;
          EnvironmentVariables = environment;
          KeepAlive = true;
          RunAtLoad = true;
          ThrottleInterval = 5;
          ProcessType = "Background";
          StandardOutPath = "${config.home.homeDirectory}/Library/Logs/${name}.log";
          StandardErrorPath = "${config.home.homeDirectory}/Library/Logs/${name}.error.log";
        };
      }) modes
    );
  };
}
