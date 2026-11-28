{
  config,
  configLib,
  lib,
  pkgs,
  isDarwin,
  ...
}:

let
  cfg = config.services.cli-proxy-api;
  user = if isDarwin then "_cliproxyapi" else "cli-proxy-api";
  runtimeDir = if isDarwin then "/private/var/run/cli-proxy-api" else "/run/cli-proxy-api";
  # The host only loads regular files named after the plugin ID, so copy rather than link.
  pluginDir = pkgs.runCommand "cli-proxy-api-plugins" { } (
    lib.concatStrings (
      lib.mapAttrsToList (
        id: plugin:
        let
          file = "${id}${pkgs.stdenv.hostPlatform.extensions.sharedLibrary}";
        in
        ''
          install -Dm444 ${plugin.package}/lib/${file} "$out/${file}"
        ''
      ) cfg.plugins
    )
  );
  pluginsConfig = pkgs.writeText "cli-proxy-api-plugins.json" (
    builtins.toJSON {
      enabled = true;
      dir = "${pluginDir}";
      configs = lib.mapAttrs (_: plugin: plugin.settings // { enabled = true; }) cfg.plugins;
    }
  );
  command = pkgs.writeShellScriptBin "cli-proxy-api" ''
    set -euo pipefail
    umask 077
    if [ "$(${pkgs.coreutils}/bin/id -u)" != 0 ]; then
      echo "Run with sudo: CLIProxyAPI uses a separate service account." >&2
      exit 1
    fi

    export WRITABLE_PATH=${lib.escapeShellArg cfg.stateDir}
    runtime_dir=${lib.escapeShellArg runtimeDir}
    ${
      if isDarwin then
        ''
          ${lib.getExe pkgs.python3} ${./ramdisk.py} "$runtime_dir"
        ''
      else
        ''
          ${pkgs.coreutils}/bin/mkdir -p "$runtime_dir"
          if [ "$(${pkgs.util-linux}/bin/findmnt -n -o FSTYPE -T "$runtime_dir")" != tmpfs ]; then
            echo "Refusing to write credentials: $runtime_dir is not on tmpfs." >&2
            exit 1
          fi
        ''
    }
    # Root owns the parent so the service cannot replace root's staging files.
    ${pkgs.coreutils}/bin/chown root:${user} "$runtime_dir"
    ${pkgs.coreutils}/bin/chmod 0750 "$runtime_dir"
    ${pkgs.coreutils}/bin/install -d -m 0700 -o ${user} -g ${user} "$WRITABLE_PATH" "$WRITABLE_PATH/auth"

    config_args=()
    explicit_config=false
    for arg in "$@"; do
      case "$arg" in
        -config|--config|-config=*|--config=*) explicit_config=true ;;
      esac
    done
    if [ "$explicit_config" = false ]; then
      secrets="$(${pkgs.coreutils}/bin/mktemp "$runtime_dir/.secrets.XXXXXX")"
      temporary_config="$(${pkgs.coreutils}/bin/mktemp "$runtime_dir/.config.XXXXXX")"
      trap '${pkgs.coreutils}/bin/rm -f "$secrets" "$temporary_config"' EXIT
      trap 'exit 1' HUP INT TERM
      # Only encrypted input and paths enter the Nix store. Decryption is runtime-only.
      ${
        if cfg.ageKeyFile != null then
          ''
            SOPS_AGE_KEY_FILE=${lib.escapeShellArg cfg.ageKeyFile} \
              ${lib.getExe pkgs.sops} --decrypt ${lib.escapeShellArg "${cfg.secretsFile}"} > "$secrets"
          ''
        else
          ''
            SOPS_AGE_KEY="$(${lib.getExe pkgs.ssh-to-age} -private-key -i ${lib.escapeShellArg cfg.sshKeyFile})" \
              ${lib.getExe pkgs.sops} --decrypt ${lib.escapeShellArg "${cfg.secretsFile}"} > "$secrets"
          ''
      }
      inputs=(${lib.escapeShellArg cfg.configFile} "$secrets")
      if ! ${lib.getExe pkgs.yq-go} eval-all --exit-status '
        ([.api-keys[]? | .[]? | select((.name | tag) != "!!str" or .name == "")] | length == 0) and
        ([.api-keys[]? | group_by(.name)[] | select(length > 1)] | length == 0)
      ' "''${inputs[@]}" > /dev/null; then
        echo "api-keys provider groups must have unique, nonempty names within each file." >&2
        exit 1
      fi
      # Index provider groups by name while merging, then restore their lists.
      # All other lists keep the normal replacement semantics. Then OAuth state
      # goes to the private state directory, and the shared client-key (which
      # Agent Vault injects for agents) joins the accepted client keys.
      # shellcheck disable=SC2016
      ${lib.getExe pkgs.yq-go} eval-all '
        # An empty api-keys key (e.g. a bare "api-keys:" in secrets.yaml) is null;
        # drop it so it does not replace the provider groups from the tracked config.
        (select(has("api-keys") and .api-keys == null) |= del(.api-keys)) |
        (with(select(has("api-keys"));
          .api-keys |= with_entries(.value |= ([.[] | {"key": .name, "value": .}] | from_entries))
        )) as $item ireduce ({}; . * $item) |
        with(select(has("api-keys"));
          .api-keys |= with_entries(.value |= ([to_entries[] | .value]))
        )
      ' "''${inputs[@]}"${
        lib.optionalString (cfg.plugins != { }) " | ${lib.getExe pkgs.yq-go} '.plugins *= load(\"${pluginsConfig}\")'"
      } | ${lib.getExe pkgs.yq-go} '.oauth.auth-dir = (strenv(WRITABLE_PATH) + "/auth") | with(select(has("client-key")); .access.api-keys = ((.access.api-keys // []) + [.client-key] | unique) | del(.client-key))' > "$temporary_config"
      ${pkgs.coreutils}/bin/chown ${user}:${user} "$temporary_config"
      ${pkgs.coreutils}/bin/mv -fT "$temporary_config" "$runtime_dir/config.yaml"
      ${pkgs.coreutils}/bin/rm -f "$secrets"
      trap - EXIT HUP INT TERM
      config_args=(--config "$runtime_dir/config.yaml")
    fi

    cd "$WRITABLE_PATH" || exit 1
    # discover is a subcommand rather than a flag.
    if [ "''${1-}" = discover ]; then
      shift
      exec ${lib.getExe pkgs.python3} ${./run-as-user.py} ${user} "$WRITABLE_PATH" ${lib.getExe cfg.package} discover "''${config_args[@]}" "$@"
    fi
    exec ${lib.getExe pkgs.python3} ${./run-as-user.py} ${user} "$WRITABLE_PATH" ${lib.getExe cfg.package} "''${config_args[@]}" "$@"
  '';
in
{
  options.services.cli-proxy-api = {
    enable = lib.mkEnableOption "CLIProxyAPI system service with RAM-only API keys";
    package = lib.mkOption {
      type = lib.types.package;
      default = pkgs.cli-proxy-api;
      description = "CLIProxyAPI package to use.";
    };
    configFile = lib.mkOption {
      type = lib.types.str;
      example = "/home/tmx/.cli-proxy-api/personal.yaml";
      description = "Mutable YAML configuration of the host's CLIProxyAPI profile, managed outside Nix (for example with Stow).";
    };
    secretsFile = lib.mkOption {
      type = lib.types.path;
      example = lib.literalExpression ''configLib.secretFile "sops/shared/cli-proxy-api-personal.yaml"'';
      description = "SOPS-encrypted YAML overrides: the host's CLIProxyAPI profile in nix-secrets. Never supply a plaintext file here.";
    };
    sshKeyFile = lib.mkOption {
      type = lib.types.str;
      default = "${config.users.users.tmx.home}/.ssh/id_ed25519";
      description = "SSH identity converted to an age key at runtime, unless ageKeyFile is set.";
    };
    ageKeyFile = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = "Optional root-owned age identity outside the Nix store, instead of the login user's SSH identity.";
    };
    stateDir = lib.mkOption {
      type = lib.types.str;
      default = "/var/lib/cli-proxy-api";
      description = "Private persistent directory for OAuth credentials, logs and management panel assets.";
    };
    plugins = lib.mkOption {
      default = { };
      description = "Plugins to load, keyed by plugin ID. Each package provides lib/<id>.so (.dylib on macOS); settings become plugins.configs.<id>.";
      type = lib.types.attrsOf (
        lib.types.submodule {
          options = {
            package = lib.mkOption {
              type = lib.types.package;
              description = "Package containing the plugin library.";
            };
            settings = lib.mkOption {
              type = lib.types.attrsOf lib.types.anything;
              default = { };
              description = "Plugin configuration. Reference secrets by file path; values end up in the Nix store.";
            };
          };
        }
      );
    };
    darwinUid = lib.mkOption {
      type = lib.types.int;
      default = 493;
      description = "UID and GID of the dedicated macOS service account; must be unused.";
    };
  };

  config = lib.mkIf cfg.enable (
    {
      environment.systemPackages = [ command ];
      system.build.cli-proxy-api = command;
    }
    // (
      if isDarwin then
        {
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
            # The Nix volume may not be mounted when launchd loads system daemons.
            ProgramArguments = [
              "/bin/sh"
              "-c"
              "/bin/wait4path /nix/store && exec ${lib.escapeShellArg (lib.getExe command)}"
            ];
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
        }
      else
        {
          users.groups.${user} = { };
          users.users.${user} = {
            isSystemUser = true;
            group = user;
            home = cfg.stateDir;
          };
          systemd.tmpfiles.rules = [
            "d ${cfg.stateDir} 0700 ${user} ${user} - -"
          ];
          systemd.services.cli-proxy-api = {
            description = "CLIProxyAPI";
            after = [ "network-online.target" ];
            wants = [ "network-online.target" ];
            wantedBy = [ "multi-user.target" ];
            serviceConfig = {
              # Root prepares credentials; the launcher permanently drops UID/GID before exec.
              ExecStart = lib.getExe command;
              Group = user;
              RuntimeDirectory = "cli-proxy-api";
              RuntimeDirectoryMode = "0750";
              RuntimeDirectoryPreserve = "restart";
              ReadWritePaths = [
                runtimeDir
                cfg.stateDir
              ];
              ProtectSystem = "strict";
              # The host copies plugins into $TMPDIR before loading them.
              PrivateTmp = true;
              NoNewPrivileges = true;
              LimitCORE = 0;
              # Upstream can exit successfully even when configuration loading fails.
              Restart = "always";
              RestartSec = 5;
              UMask = "0077";
            };
          };
        }
    )
  );
}
