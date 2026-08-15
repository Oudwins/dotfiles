{
  config,
  lib,
  pkgs,
  ...
}:

let
  inherit (lib)
    mkEnableOption
    mkIf
    mkOption
    types
    ;
  cfg = config.services.executor;

  mcpServerType = types.submodule (
    { name, ... }:
    {
      options = {
        name = mkOption {
          type = types.str;
          default = name;
          description = "Display name shown by Executor.";
        };

        description = mkOption {
          type = types.str;
          default = name;
          description = "Description shown by Executor.";
        };

        transport = mkOption {
          type = types.enum [
            "remote"
            "stdio"
          ];
          default = "remote";
          description = "MCP transport used to connect to the server.";
        };

        endpoint = mkOption {
          type = types.nullOr types.str;
          default = null;
          description = "Remote MCP endpoint.";
        };

        remoteTransport = mkOption {
          type = types.enum [
            "auto"
            "streamable-http"
            "sse"
          ];
          default = "auto";
          description = "Remote MCP transport preference.";
        };

        authentication = mkOption {
          type = types.enum [
            "none"
            "oauth2"
          ];
          default = "none";
          description = "Authentication method offered when connecting the MCP server.";
        };

        headers = mkOption {
          type = types.attrsOf types.str;
          default = { };
          description = "Non-secret HTTP headers stored in the Nix store.";
        };

        queryParams = mkOption {
          type = types.attrsOf types.str;
          default = { };
          description = "Non-secret query parameters stored in the Nix store.";
        };

        command = mkOption {
          type = types.nullOr types.str;
          default = null;
          description = "Executable used by a stdio MCP server.";
        };

        args = mkOption {
          type = types.listOf types.str;
          default = [ ];
          description = "Arguments passed to a stdio MCP server.";
        };

        cwd = mkOption {
          type = types.nullOr types.str;
          default = null;
          description = "Working directory for a stdio MCP server.";
        };

        environment = mkOption {
          type = types.attrsOf types.str;
          default = { };
          description = "Non-secret environment variables stored in the Nix store.";
        };

        secretEnvironmentVariables = mkOption {
          type = types.listOf types.str;
          default = [ ];
          description = "Environment variable names whose values are configured through Executor.";
        };
      };
    }
  );

  authTemplate =
    server:
    if server.transport == "stdio" && server.secretEnvironmentVariables != [ ] then
      [
        {
          slug = "stdio_env";
          kind = "stdio_env";
          vars = server.secretEnvironmentVariables;
        }
      ]
    else
      [
        {
          slug = server.authentication;
          kind = server.authentication;
        }
      ];

  fileIntegration =
    slug: server:
    {
      kind = "mcp";
      inherit (server) transport name;
      namespace = slug;
    }
    // lib.optionalAttrs (server.transport == "remote") {
      inherit (server) endpoint remoteTransport;
      headers = server.headers;
      queryParams = server.queryParams;
    }
    // lib.optionalAttrs (server.transport == "stdio") {
      inherit (server) command args;
      env = server.environment;
    }
    // lib.optionalAttrs (server.transport == "stdio" && server.cwd != null) {
      inherit (server) cwd;
    };

  apiServer =
    slug: server:
    let
      authenticationTemplate = authTemplate server;
      serverConfig =
        if server.transport == "remote" then
          {
            transport = "remote";
            inherit (server)
              endpoint
              remoteTransport
              headers
              queryParams
              ;
            inherit authenticationTemplate;
          }
        else
          {
            transport = "stdio";
            inherit (server) command args;
            env = server.environment;
            inherit authenticationTemplate;
          }
          // lib.optionalAttrs (server.cwd != null) { inherit (server) cwd; };
      addPayload = {
        inherit slug;
        inherit (server) transport name description;
      }
      // lib.optionalAttrs (server.transport == "remote") {
        inherit (server)
          endpoint
          remoteTransport
          headers
          queryParams
          ;
        inherit authenticationTemplate;
      }
      // lib.optionalAttrs (server.transport == "stdio") {
        inherit (server) command args;
        env = server.environment;
        envVars = server.secretEnvironmentVariables;
      }
      // lib.optionalAttrs (server.transport == "stdio" && server.cwd != null) {
        inherit (server) cwd;
      };
    in
    {
      inherit slug addPayload serverConfig;
      needsDefaultConnection =
        server.authentication == "none" && server.secretEnvironmentVariables == [ ];
    };

  desiredServers = lib.mapAttrsToList apiServer cfg.mcpServers;
  executorConfig = pkgs.writeText "executor.jsonc" (
    builtins.toJSON {
      name = "home-manager";
      integrations = lib.mapAttrsToList fileIntegration cfg.mcpServers;
    }
  );
  reconcileConfig = pkgs.writeText "executor-managed-mcps.json" (
    builtins.toJSON { servers = desiredServers; }
  );

  executorCommand = pkgs.writeShellScriptBin "executor" ''
    export EXECUTOR_DATA_DIR=${lib.escapeShellArg cfg.dataDir}
    export EXECUTOR_SCOPE_DIR=${lib.escapeShellArg "${config.xdg.configHome}/executor"}
    export EXECUTOR_DISABLE_ANALYTICS=1
    export EXECUTOR_DISABLE_UPDATE_CHECK=1
    exec ${lib.getExe cfg.package} "$@"
  '';

  reconcile = pkgs.writeShellApplication {
    name = "executor-reconcile";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.curl
      pkgs.jq
    ];
    text = ''
      api_base=${lib.escapeShellArg "http://${cfg.host}:${toString cfg.port}"}
      data_dir=${lib.escapeShellArg cfg.dataDir}
      desired=${lib.escapeShellArg reconcileConfig}
      managed_file="$data_dir/managed-mcps.json"

      ready=0
      for _ in {1..60}; do
        if curl --silent --fail "$api_base/api/health" >/dev/null; then
          ready=1
          break
        fi
        sleep 1
      done

      if [[ "$ready" != 1 ]]; then
        echo "Executor did not become ready at $api_base" >&2
        exit 1
      fi

      token="$(jq --exit-status --raw-output .token "$data_dir/server-control/auth.json")"

      request() {
        curl \
          --silent \
          --show-error \
          --fail-with-body \
          --header "Authorization: Bearer $token" \
          --header "Content-Type: application/json" \
          "$@"
      }

      while IFS= read -r server; do
        slug="$(jq --raw-output .slug <<<"$server")"
        current="$(request "$api_base/api/mcp/servers/$slug")"

        if [[ "$current" == null ]]; then
          payload="$(jq --compact-output .addPayload <<<"$server")"
          request \
            --request POST \
            --data-binary "$payload" \
            "$api_base/api/mcp/servers" >/dev/null
        else
          payload="$(jq --compact-output '{ config: .serverConfig }' <<<"$server")"
          request \
            --request POST \
            --data-binary "$payload" \
            "$api_base/api/mcp/servers/$slug/config" >/dev/null
        fi

        if [[ "$(jq --raw-output .needsDefaultConnection <<<"$server")" == true ]]; then
          payload="$(jq --compact-output '{ owner: "org", name: "default", integration: .slug, template: "none" }' <<<"$server")"
          request \
            --request POST \
            --data-binary "$payload" \
            "$api_base/api/connections" >/dev/null
        fi
      done < <(jq --compact-output '.servers[]' "$desired")

      if [[ -f "$managed_file" ]]; then
        while IFS= read -r slug; do
          if ! jq --exit-status --arg slug "$slug" 'any(.servers[]; .slug == $slug)' "$desired" >/dev/null; then
            request --request DELETE "$api_base/api/mcp/servers/$slug" >/dev/null
          fi
        done < <(jq --raw-output '.[]' "$managed_file")
      fi

      mkdir -p "$data_dir"
      next_managed="$(mktemp "$data_dir/.managed-mcps.XXXXXX")"
      jq '[.servers[].slug]' "$desired" >"$next_managed"
      mv "$next_managed" "$managed_file"
    '';
  };

  serviceEnvironment = {
    EXECUTOR_DATA_DIR = cfg.dataDir;
    EXECUTOR_SCOPE_DIR = "${config.xdg.configHome}/executor";
    EXECUTOR_SUPERVISED = "1";
    EXECUTOR_DISABLE_ANALYTICS = "1";
    EXECUTOR_DISABLE_UPDATE_CHECK = "1";
  };
in
{
  options.services.executor = {
    enable = mkEnableOption "Executor MCP gateway";

    package = mkOption {
      type = types.package;
      default = pkgs.executor;
      defaultText = lib.literalExpression "pkgs.executor";
      description = "Executor package to use.";
    };

    host = mkOption {
      type = types.str;
      default = "127.0.0.1";
      description = "Address on which Executor listens.";
    };

    port = mkOption {
      type = types.port;
      default = 4788;
      description = "Port on which Executor listens.";
    };

    dataDir = mkOption {
      type = types.str;
      default = "${config.xdg.dataHome}/executor";
      description = "Mutable Executor database and authentication directory.";
    };

    mcpServers = mkOption {
      type = types.attrsOf mcpServerType;
      default = { };
      description = "MCP servers managed declaratively by Executor.";
    };
  };

  config = mkIf cfg.enable {
    assertions = lib.flatten (
      lib.mapAttrsToList (slug: server: [
        {
          assertion = builtins.match "^[a-z0-9][a-z0-9_-]*$" slug != null;
          message = "services.executor.mcpServers.${slug}: the name must be a lowercase slug";
        }
        {
          assertion = server.transport != "remote" || server.endpoint != null;
          message = "services.executor.mcpServers.${slug}.endpoint must be set for a remote MCP server";
        }
        {
          assertion = server.transport != "stdio" || server.command != null;
          message = "services.executor.mcpServers.${slug}.command must be set for a stdio MCP server";
        }
        {
          assertion = server.transport != "stdio" || server.authentication == "none";
          message = "services.executor.mcpServers.${slug}.authentication is only supported for remote MCP servers";
        }
      ]) cfg.mcpServers
    );

    home.packages = [ executorCommand ];
    xdg.configFile."executor/executor.jsonc".source = executorConfig;

    systemd.user.services.executor = mkIf pkgs.stdenv.hostPlatform.isLinux {
      Unit = {
        Description = "Executor MCP gateway";
        After = [ "network-online.target" ];
        Wants = [ "network-online.target" ];
      };
      Service = {
        ExecStart = "${lib.getExe cfg.package} daemon run --foreground --hostname ${cfg.host} --port ${toString cfg.port}";
        ExecStartPost = "${lib.getExe reconcile}";
        Environment = lib.mapAttrsToList (name: value: "${name}=${value}") serviceEnvironment;
        Restart = "on-failure";
        RestartSec = 5;
      };
      Install.WantedBy = [ "default.target" ];
    };

    launchd.agents.executor = mkIf pkgs.stdenv.hostPlatform.isDarwin {
      enable = true;
      config = {
        ProgramArguments = [
          (lib.getExe cfg.package)
          "daemon"
          "run"
          "--foreground"
          "--hostname"
          cfg.host
          "--port"
          (toString cfg.port)
        ];
        EnvironmentVariables = serviceEnvironment;
        KeepAlive = true;
        ProcessType = "Background";
        RunAtLoad = true;
      };
    };

    launchd.agents.executor-reconcile = mkIf pkgs.stdenv.hostPlatform.isDarwin {
      enable = true;
      config = {
        ProgramArguments = [ (lib.getExe reconcile) ];
        KeepAlive.SuccessfulExit = false;
        ProcessType = "Background";
        RunAtLoad = true;
        ThrottleInterval = 5;
      };
    };
  };
}
