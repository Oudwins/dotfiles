{ config, ... }:
{
  imports = [
    ./base
    ./git
    ./shell
    ./nvim
    ./tmux
    ./ghostty
    ./agents
    ./executor
  ];

  services.executor = {
    enable = true;
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
}
