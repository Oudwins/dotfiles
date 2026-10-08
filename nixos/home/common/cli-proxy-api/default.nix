{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.services.cli-proxy-api;
  command = pkgs.writeShellScriptBin "cli-proxy-api" ''
    set -e
    umask 077
    export WRITABLE_PATH=${lib.escapeShellArg cfg.stateDir}
    ${pkgs.coreutils}/bin/mkdir -p "$WRITABLE_PATH"

    config_args=()
    explicit_config=false
    for arg in "$@"; do
      case "$arg" in
        -config|--config|-config=*|--config=*) explicit_config=true ;;
      esac
    done
    if [ "$explicit_config" = false ]; then
      inputs=(${lib.escapeShellArg cfg.configFile})
      if [ -f ${lib.escapeShellArg cfg.secretsFile} ]; then
        inputs+=(${lib.escapeShellArg cfg.secretsFile})
      fi
      temporary_config="$(${pkgs.coreutils}/bin/mktemp "$WRITABLE_PATH/.config.XXXXXX")"
      trap '${pkgs.coreutils}/bin/rm -f "$temporary_config"' EXIT
      ${lib.getExe pkgs.yq-go} eval-all '. as $item ireduce ({}; . * $item)' "''${inputs[@]}" > "$temporary_config"
      ${pkgs.coreutils}/bin/mv -f "$temporary_config" "$WRITABLE_PATH/config.yaml"
      trap - EXIT
      config_args=(--config "$WRITABLE_PATH/config.yaml")
    fi

    cd "$WRITABLE_PATH" || exit 1
    # discover is a subcommand rather than a flag.
    if [ "''${1-}" = discover ]; then
      shift
      exec ${lib.getExe cfg.package} discover "''${config_args[@]}" "$@"
    fi
    exec ${lib.getExe cfg.package} "''${config_args[@]}" "$@"
  '';
in
{
  options.services.cli-proxy-api = {
    enable = lib.mkEnableOption "CLIProxyAPI user service";
    package = lib.mkOption {
      type = lib.types.package;
      default = pkgs.cli-proxy-api;
      description = "CLIProxyAPI package to use.";
    };
    configFile = lib.mkOption {
      type = lib.types.str;
      default = "${config.home.homeDirectory}/.cli-proxy-api/config.yaml";
      description = "Mutable YAML configuration, managed outside Nix (for example with Stow).";
    };
    secretsFile = lib.mkOption {
      type = lib.types.str;
      default = "${config.home.homeDirectory}/.cli-proxy-api/secrets.yaml";
      description = "Optional local YAML overrides, merged with configFile at launch without putting secrets in the Nix store.";
    };
    stateDir = lib.mkOption {
      type = lib.types.str;
      default = "${config.xdg.stateHome}/cli-proxy-api";
      description = "Writable directory for logs and management panel assets.";
    };
  };

  config = lib.mkIf cfg.enable {
    home.packages = [ command ];

    systemd.user.services.cli-proxy-api = lib.mkIf pkgs.stdenv.hostPlatform.isLinux {
      Unit = {
        Description = "CLIProxyAPI";
        After = [ "network-online.target" ];
        Wants = [ "network-online.target" ];
      };
      Service = {
        ExecStart = lib.getExe command;
        # Upstream can exit successfully even when configuration loading fails.
        Restart = "always";
        RestartSec = 5;
        UMask = "0077";
      };
      Install.WantedBy = [ "default.target" ];
    };

    launchd.agents.cli-proxy-api = lib.mkIf pkgs.stdenv.hostPlatform.isDarwin {
      enable = true;
      config = {
        ProgramArguments = [ (lib.getExe command) ];
        KeepAlive = true;
        RunAtLoad = true;
        ThrottleInterval = 5;
        ProcessType = "Background";
        StandardOutPath = "${config.home.homeDirectory}/Library/Logs/cli-proxy-api.log";
        StandardErrorPath = "${config.home.homeDirectory}/Library/Logs/cli-proxy-api.error.log";
      };
    };
  };
}
