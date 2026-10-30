{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.services.cli-proxy-api;
  isDarwin = pkgs.stdenv.hostPlatform.isDarwin;
  user = if isDarwin then "_cliproxyapi" else "cli-proxy-api";
  runtimeDir = if isDarwin then "/private/var/run/cli-proxy-api" else "/run/cli-proxy-api";
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
              ${lib.getExe pkgs.sops} --decrypt ${lib.escapeShellArg (toString cfg.secretsFile)} > "$secrets"
          ''
        else
          ''
            SOPS_AGE_KEY="$(${lib.getExe pkgs.ssh-to-age} -private-key -i ${lib.escapeShellArg cfg.sshKeyFile})" \
              ${lib.getExe pkgs.sops} --decrypt ${lib.escapeShellArg (toString cfg.secretsFile)} > "$secrets"
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
      # All other lists keep the normal replacement semantics.
      # shellcheck disable=SC2016
      ${lib.getExe pkgs.yq-go} eval-all '
        # An empty api-keys key (e.g. a bare "api-keys:" in secrets.yaml) is null;
        # drop it so it does not replace the provider groups from config.yaml.
        (select(has("api-keys") and .api-keys == null) |= del(.api-keys)) |
        (with(select(has("api-keys"));
          .api-keys |= with_entries(.value |= ([.[] | {"key": .name, "value": .}] | from_entries))
        )) as $item ireduce ({}; . * $item) |
        with(select(has("api-keys"));
          .api-keys |= with_entries(.value |= ([to_entries[] | .value]))
        )
      ' "''${inputs[@]}" | ${lib.getExe pkgs.yq-go} '.oauth.auth-dir = (strenv(WRITABLE_PATH) + "/auth")' > "$temporary_config"
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
      default = "${config.users.users.tmx.home}/.cli-proxy-api/config.yaml";
      description = "Mutable YAML configuration, managed outside Nix (for example with Stow).";
    };
    secretsFile = lib.mkOption {
      type = lib.types.path;
      default = ../../../secrets/cli-proxy-api.yaml;
      description = "SOPS-encrypted YAML overrides. Never supply a plaintext file here.";
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
    darwinUid = lib.mkOption {
      type = lib.types.int;
      default = 493;
      description = "UID and GID of the dedicated macOS service account; must be unused.";
    };
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages = [ command ];
    system.build.cli-proxy-api = command;
  };
}
