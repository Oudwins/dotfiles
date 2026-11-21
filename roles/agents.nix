# Coding agents on a workstation: the LLM proxy (CLIProxyAPI), the Executor MCP
# gateway, Agent Vault, the PR review server and agent CLIs. This role is the
# only place these modules are imported and wired together. Import it from a
# host and, to use another machine's service instead of the local one, set:
#
#   agents.llmproxy.address = "https://tubby.<tailnet>.ts.net:8317"; # remote proxy
#   agents.executor.address = "https://executor.<tailnet>.ts.net/mcp"; # remote Executor
#
# Skills and commands live in agents/ and are linked by updateSymlinks.sh.
{
  config,
  configLib,
  lib,
  pkgs,
  isDarwin,
  ...
}:

let
  cfg = config.agents;
  user = config.my.username;
  ownerEmail = "${user}@${config.my.domain}";
  # Agent Vault rejects IP-based service hosts, so the host must contain a letter.
  host = "[A-Za-z0-9.-]*[A-Za-z][A-Za-z0-9.-]*(:[0-9]+)?";
  address =
    pattern: example:
    lib.mkOption {
      type = lib.types.nullOr (lib.types.strMatching "https?://${host}${pattern}");
      default = null;
      inherit example;
      description = "Remote endpoint to use instead of the local service, which is then disabled. Must be a hostname such as a Tailscale MagicDNS name, not an IP.";
    };
  # Agents reach each service through Agent Vault's router at
  # http://127.0.0.1:28760/<name>, which injects its credential. The entries in
  # home-files/tmx/.config/agent-vault/config.json read these variables.
  services = {
    # The port matches home-files/tmx/.cli-proxy-api/config.yaml.
    llmproxy = {
      local = "http://llmproxy.localhost:8317";
      variable = "LLM_PROXY_URL";
    };
    executor = {
      local = "http://executor.localhost:4788/mcp";
      variable = "EXECUTOR_MCP_URL";
    };
  };
  anyRemote = lib.any (name: cfg.${name}.address != null) (lib.attrNames services);
  endpoint =
    name: if cfg.${name}.address == null then services.${name}.local else cfg.${name}.address;
  origin = url: builtins.head (builtins.match "(https?://[^/]+).*" url);
  agentVaultConfig = lib.importJSON ../home-files/tmx/.config/agent-vault/config.json;
in
{
  imports = [ ../modules/shared/cli-proxy-api ];

  options.agents = {
    # The router forwards subpaths only to targets without a path.
    llmproxy.address = address "/?" "https://tubby.example.ts.net:8317";
    executor.address = address "(/[^?#]*)?" "https://executor.example.ts.net/mcp";
    # Needs executor/cloudflare-token in the user's sops file.
    executor.cloudflare.enable = lib.mkEnableOption "the Cloudflare MCP in Executor, authenticated with an API token";
  };

  config = {
    # LLM proxy
    services.cli-proxy-api.enable = lib.mkDefault (cfg.llmproxy.address == null);

    home-manager.users.${user} =
      { config, ... }:
      {
        imports = [
          ../modules/home/common/executor
          ../modules/home/common/agent-vault
          ../modules/home/common/pr-review-server
          ../modules/home/common/npm-global
          ../modules/home/common/t3code
        ];

        # Agent Vault
        services.agent-vault = {
          enable = true;
          inherit ownerEmail;
          ownerPasswordFile = config.sops.secrets."agent-vault/owner-password".path;
          environment = lib.mapAttrs' (
            name: service: lib.nameValuePair service.variable (endpoint name)
          ) services;
          # MagicDNS names resolve into Tailscale's CGNAT and IPv6 ranges, which
          # Agent Vault blocks unless allowlisted.
          networkAllowlist = lib.mkIf anyRemote [
            "100.64.0.0/10"
            "fd7a:115c:a1e0::/48"
          ];
        };
        sops.secrets."agent-vault/owner-password" = { };
        # The same key CLIProxyAPI accepts; Agent Vault injects it into llmproxy requests.
        sops.secrets."cli-proxy-api/client-key" = {
          sopsFile = configLib.secretFile "sops/shared/cli-proxy-api.yaml";
          key = "client-key";
        };

        # Executor MCP gateway
        sops.secrets."executor/token" = { };
        sops.secrets."executor/cloudflare-token" = lib.mkIf cfg.executor.cloudflare.enable { };
        services.executor = {
          enable = lib.mkDefault (cfg.executor.address == null);
          authTokenFile = config.sops.secrets."executor/token".path;
          dataDir = "${config.home.homeDirectory}/.executor";
          scopeDir = "${config.home.homeDirectory}/.executor";
          mcpServers = {
            # Figma only allows MCP OAuth for allowlisted clients, and gates dynamic
            # client registration on the client_name string, so we register as
            # "Claude Code". This way Executor's own redirect URI gets registered,
            # which borrowing a static allowlisted client_id cannot do.
            figma_mcp = {
              name = "Figma MCP";
              description = "Figma MCP";
              endpoint = "https://mcp.figma.com/mcp";
              authentication = "oauth2";
              oauthClients.default = {
                authorizationUrl = "https://www.figma.com/oauth/mcp";
                tokenUrl = "https://api.figma.com/v1/oauth/token";
                registrationEndpoint = "https://api.figma.com/v1/oauth/mcp/register";
                clientName = "Claude Code";
                scopes = [ "mcp:connect" ];
                resource = "https://mcp.figma.com/mcp";
              };
            };
            linear_mcp = {
              name = "Linear MCP";
              description = "Linear MCP";
              endpoint = "https://mcp.linear.app/mcp";
              authentication = "oauth2";
            };
            posthog_mcp = {
              name = "Posthog MCP";
              description = "Posthog MCP";
              endpoint = "https://mcp.posthog.com/mcp";
              authentication = "oauth2";
            };
          }
          // lib.optionalAttrs cfg.executor.cloudflare.enable {
            cloudflare_mcp = {
              name = "Cloudflare MCP";
              description = "Cloudflare MCP";
              endpoint = "https://mcp.cloudflare.com/mcp";
              # Executor runs its own code mode, so take Cloudflare's tools directly.
              queryParams.codemode = "false";
              authentication = "bearer";
              tokenFile = config.sops.secrets."executor/cloudflare-token".path;
            };
          };
        };

        # PR review server
        services.pr-review-server.enable = true;

        # Dashboard links follow each service to its remote address when one is set.
        my.dashboard.services = {
          agent-vault = {
            label = "Agent Vault";
            description = "Credentials for coding agents";
            url = "http://127.0.0.1:${toString agentVaultConfig.serverPort}";
            category = "agents";
            icon = "mdi-safe";
          };
          executor = {
            label = "Executor";
            description = "MCP gateway";
            url = origin (endpoint "executor");
            category = "agents";
            icon = "mdi-hub";
          };
          llmproxy = {
            label = "LLM proxy";
            description = "CLIProxyAPI management";
            url = "${lib.removeSuffix "/" (endpoint "llmproxy")}/management.html";
            category = "agents";
            icon = "mdi-robot";
          };
        };

        # Agent CLIs update too often to pin, so npm installs them into ~/.npm when
        # missing; update with `npm update -g`.
        programs.npm-global.packages = {
          "@anthropic-ai/claude-code" = { };
          "@openai/codex" = { };
          "opencode-ai" = { };
          "@earendil-works/pi-coding-agent".flags = [ "--ignore-scripts" ];
        };

        # OpenCode's stable runtime gates Responses WebSockets behind this flag.
        home.sessionVariables.OPENCODE_EXPERIMENTAL_WEBSOCKETS = "1";
        home.packages = with pkgs; [
          jq
          bun
          btca
          jsonc2json
          # Opencode for code linting
          typescript-language-server
          glab
        ];

        # Local AI
        # ollama
        # ollama run qwen3:8b
        # ''
        #   ram  model
        #   8–16GB qwen3:4b
        #   16–24GB qwen3:8b
        #   32–36GB qwen3:14b or qwen3:32b
        #
        #   ---
        #   Setup
        #   -----
        #   OLLAMA_CONTEXT_LENGTH=32768 ollama serve
        #   ollama run qwen3:8b # only first time. To pull the model. You can also do ollama pull {model}
        #   ollama run qwen3-coder:30b
        # '';
      };
  }
  // lib.optionalAttrs (!isDarwin) {
    # Local endpoints use .localhost names; macOS resolves them itself.
    networking.extraHosts = lib.concatMapStrings (
      service: "127.0.0.1 ${builtins.head (builtins.match "https?://([^/:]+).*" service.local)}\n"
    ) (lib.attrValues services);
    # OpenCode's prebuilt binaries need a dynamic loader.
    programs.nix-ld.enable = true;
  };
}
