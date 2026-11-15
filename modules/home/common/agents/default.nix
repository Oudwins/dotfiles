# Agent CLIs and the per-user agent services (Executor, Agent Vault, PR review
# server). roles/agents.nix imports this for the main user.
{ config, configLib, pkgs, ... }:
{
  imports = [
    ../executor
    ../agent-vault
    ../pr-review-server
  ];

  # We don't install opencode, claude code or codex here because these packages are updated a lot so would prefer to just install manually
  # opencode: npm i -g opencode-ai
  # pi: npm install -g --ignore-scripts @earendil-works/pi-coding-agent

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

  services.agent-vault.enable = true;
  services.pr-review-server.enable = true;

  sops.secrets."executor/token" = { };
  # The same key CLIProxyAPI accepts (see modules/shared/cli-proxy-api); Agent
  # Vault injects it into llmproxy requests.
  sops.secrets."cli-proxy-api/client-key" = {
    sopsFile = configLib.secretFile "sops/shared/cli-proxy-api.yaml";
    key = "client-key";
  };

  services.executor = {
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
    };
  };

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
}
