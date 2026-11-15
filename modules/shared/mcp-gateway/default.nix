{ config, lib, ... }:

{
  # Clients use http://127.0.0.1:28760/executor; Agent Vault adds the token.
  agentServices.executor = {
    local = "http://executor.localhost:4788/mcp";
    variable = "EXECUTOR_MCP_URL";
  };

  home-manager.users.${config.my.username}.services.executor.enable = lib.mkDefault (
    config.agentServices.executor.address == null
  );
}
