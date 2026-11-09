{ config, lib, ... }:

let
  address = config.mcp-gateway.address;
  isLoopback =
    builtins.match "https?://(127\\.0\\.0\\.1|localhost|executor\\.localhost|\\[::1])(:[0-9]+)?(/.*)?" address
    != null;
in
{
  options.mcp-gateway.address = lib.mkOption {
    type = lib.types.strMatching "https?://[^/]+(/.*)?";
    default = "http://executor.localhost:4788/mcp";
    example = "https://executor.example.com/mcp";
    description = "Upstream Executor endpoint for Caddy's /executor route, forwarded through Agent Vault. Use a hostname because Agent Vault rejects IP-based service definitions. A loopback host runs local Executor; any other host selects a remote Executor and disables the local service. Client MCP URLs stay unchanged.";
  };

  config = {
    home-manager.users.tmx = {
      services.executor.enable = lib.mkDefault isLoopback;
      services.agent-vault.environment.EXECUTOR_MCP_URL = address;
    };
  };
}
