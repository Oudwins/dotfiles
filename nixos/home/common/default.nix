{ ... }:
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
    mcpServers = {
      figma = {
        endpoint = "https://mcp.figma.com/mcp";
        authentication = "oauth2";
      };
      linear = {
        endpoint = "https://mcp.linear.app/mcp";
        authentication = "oauth2";
      };
      posthog = {
        endpoint = "https://mcp.posthog.com/mcp";
        authentication = "oauth2";
      };
    };
  };
}
