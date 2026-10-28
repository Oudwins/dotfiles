{ config, lib, ... }:

let
  address = config.mcp-gateway.address;
  isLoopback = builtins.match "https?://(127\\.0\\.0\\.1|localhost|\\[::1])(:[0-9]+)?(/.*)?" address != null;
in
{
  options.mcp-gateway.address = lib.mkOption {
    type = lib.types.strMatching "https?://[^/]+(/.*)?";
    default = "http://127.0.0.1:4788/mcp";
    example = "https://executor.example.com/mcp";
    description = "Executor MCP endpoint that mcp-auth-proxy forwards to. A loopback host runs local Executor; any other host selects a remote Executor and disables the local service.";
  };

  config.home-manager.users.tmx = {
    services.executor.enable = lib.mkDefault isLoopback;
    # Read by ${env:EXECUTOR_MCP_URL} in ~/.mcp-auth-proxy/config.yaml. The service gets it
    # directly; the session variable covers stdio and `check`, which load the same config.
    services.mcp-auth-proxy.environment.EXECUTOR_MCP_URL = address;
    home.sessionVariables.EXECUTOR_MCP_URL = address;
  };
}
