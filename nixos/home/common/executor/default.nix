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

  oauthClientType = types.submodule {
    options = {
      authorizationUrl = mkOption {
        type = types.str;
        description = "OAuth authorization endpoint.";
      };

      tokenUrl = mkOption {
        type = types.str;
        description = "OAuth token endpoint.";
      };

      clientId = mkOption {
        type = types.nullOr types.str;
        default = null;
        description = "OAuth client ID for a pre-registered client.";
      };

      clientSecret = mkOption {
        type = types.nullOr types.str;
        default = null;
        description = "OAuth client secret stored in the Nix store.";
      };

      registrationEndpoint = mkOption {
        type = types.nullOr types.str;
        default = null;
        description = "RFC 7591 dynamic client registration endpoint. When set, Executor registers its own client instead of using fixed credentials.";
      };

      clientName = mkOption {
        type = types.nullOr types.str;
        default = null;
        description = "Client name sent during dynamic client registration.";
      };

      scopes = mkOption {
        type = types.listOf types.str;
        default = [ ];
        description = "OAuth scopes requested during dynamic client registration.";
      };

      resource = mkOption {
        type = types.nullOr types.str;
        default = null;
        description = "OAuth resource indicator.";
      };
    };
  };

  # Executor's register-dynamic endpoint ignores the requested slug and derives
  # one from the registration endpoint's host, e.g. api.figma.com becomes
  # dcr-api-figma-com.
  dcrClientSlug =
    endpoint:
    let
      withoutScheme = lib.removePrefix "https://" (lib.removePrefix "http://" endpoint);
      host = lib.head (lib.splitString "/" withoutScheme);
    in
    "dcr-" + lib.concatStringsSep "-" (lib.splitString "." host);

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

        oauthClients = mkOption {
          type = types.attrsOf oauthClientType;
          default = { };
          description = "Fixed OAuth clients registered for this MCP server.";
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
      oauthClientPayloads = lib.mapAttrsToList (name: client: {
        owner = "org";
        slug = "${slug}-${name}";
        grant = "authorization_code";
        inherit (client)
          authorizationUrl
          tokenUrl
          clientId
          clientSecret
          resource
          ;
        originIntegration = slug;
      }) (lib.filterAttrs (_: client: client.registrationEndpoint == null) server.oauthClients);
      oauthDcrClientPayloads = lib.mapAttrsToList (name: client: {
        owner = "org";
        slug = dcrClientSlug client.registrationEndpoint;
        inherit (client)
          registrationEndpoint
          authorizationUrl
          tokenUrl
          clientName
          scopes
          resource
          ;
        originIntegration = slug;
      }) (lib.filterAttrs (_: client: client.registrationEndpoint != null) server.oauthClients);
    in
    {
      inherit
        slug
        addPayload
        serverConfig
        oauthClientPayloads
        oauthDcrClientPayloads
        ;
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
    export EXECUTOR_SCOPE_DIR=${lib.escapeShellArg cfg.scopeDir}
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

        while IFS= read -r oauth_client; do
          request \
            --request POST \
            --data-binary "$oauth_client" \
            "$api_base/api/oauth/clients" >/dev/null
        done < <(jq --compact-output '.oauthClientPayloads[]' <<<"$server")

        while IFS= read -r oauth_client; do
          request \
            --request POST \
            --data-binary "$oauth_client" \
            "$api_base/api/oauth/clients/register-dynamic" >/dev/null
        done < <(jq --compact-output '.oauthDcrClientPayloads[]' <<<"$server")
      done < <(jq --compact-output '.servers[]' "$desired")

      managed_servers='[]'
      managed_oauth_clients='[]'
      legacy_managed=0
      if [[ -f "$managed_file" ]]; then
        if jq --exit-status 'type == "array"' "$managed_file" >/dev/null; then
          managed_servers="$(jq --compact-output '.' "$managed_file")"
          legacy_managed=1
        else
          managed_servers="$(jq --compact-output '.servers // []' "$managed_file")"
          managed_oauth_clients="$(jq --compact-output '.oauthClients // []' "$managed_file")"
        fi
      fi

      oauth_clients="$(request "$api_base/api/oauth/clients")"
      while IFS= read -r slug; do
        if ! jq --exit-status --arg slug "$slug" 'any(.servers[]; .slug == $slug)' "$desired" >/dev/null; then
          request --request DELETE "$api_base/api/mcp/servers/$slug" >/dev/null

          if [[ "$legacy_managed" == 1 ]]; then
            while IFS= read -r oauth_client_slug; do
              request \
                --request DELETE \
                --data-binary '{"owner":"org"}' \
                "$api_base/api/oauth/clients/$oauth_client_slug" >/dev/null
            done < <(jq --raw-output --arg prefix "$slug-" '.[] | select(.slug | startswith($prefix)) | .slug' <<<"$oauth_clients")
          fi
        fi
      done < <(jq --raw-output '.[]' <<<"$managed_servers")

      while IFS= read -r oauth_client_slug; do
        if ! jq --exit-status --arg slug "$oauth_client_slug" \
          'any(.servers[] | (.oauthClientPayloads[], .oauthDcrClientPayloads[]); .slug == $slug)' \
          "$desired" >/dev/null; then
          request \
            --request DELETE \
            --data-binary '{"owner":"org"}' \
            "$api_base/api/oauth/clients/$oauth_client_slug" >/dev/null
        fi
      done < <(jq --raw-output '.[]' <<<"$managed_oauth_clients")

      mkdir -p "$data_dir"
      next_managed="$(mktemp "$data_dir/.managed-mcps.XXXXXX")"
      jq '{
        servers: [.servers[].slug],
        oauthClients: [.servers[].oauthClientPayloads[].slug] + [.servers[].oauthDcrClientPayloads[].slug]
      }' "$desired" >"$next_managed"
      mv "$next_managed" "$managed_file"
    '';
  };

  serviceEnvironment = {
    EXECUTOR_DATA_DIR = cfg.dataDir;
    EXECUTOR_SCOPE_DIR = cfg.scopeDir;
    EXECUTOR_SUPERVISED = "1";
    EXECUTOR_DISABLE_ANALYTICS = "1";
    EXECUTOR_DISABLE_UPDATE_CHECK = "1";
  };

  launchdCommand = pkgs.writeShellApplication {
    name = "executor-service";
    text = ''
      ${lib.getExe cfg.package} daemon run \
        --foreground \
        --hostname ${lib.escapeShellArg cfg.host} \
        --port ${toString cfg.port} &
      daemon_pid=$!

      # Invoked indirectly by the signal traps below.
      # shellcheck disable=SC2329
      cleanup() {
        kill "$daemon_pid" 2>/dev/null || true
        wait "$daemon_pid" 2>/dev/null || true
      }
      trap cleanup EXIT INT TERM

      ${lib.getExe reconcile}

      status=0
      wait "$daemon_pid" || status=$?
      trap - EXIT INT TERM
      exit "$status"
    '';
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

    # DEFAULT PORT
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

    scopeDir = mkOption {
      type = types.str;
      default = "${config.xdg.configHome}/executor";
      description = "Directory identifying the Executor workspace.";
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
        {
          assertion = server.oauthClients == { } || server.authentication == "oauth2";
          message = "services.executor.mcpServers.${slug}.oauthClients requires authentication = \"oauth2\"";
        }
      ]
      ++ lib.flatten (
        lib.mapAttrsToList (cname: client: [
          {
            assertion =
              (client.registrationEndpoint == null && client.clientId != null && client.clientSecret != null)
              || (client.registrationEndpoint != null && client.clientId == null && client.clientSecret == null);
            message = "services.executor.mcpServers.${slug}.oauthClients.${cname}: set exactly one of clientId/clientSecret (fixed client) or registrationEndpoint (dynamic registration)";
          }
        ]) server.oauthClients
      )) cfg.mcpServers
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
        ProgramArguments = [ (lib.getExe launchdCommand) ];
        EnvironmentVariables = serviceEnvironment;
        KeepAlive = true;
        ProcessType = "Background";
        RunAtLoad = true;
      };
    };
  };
}
