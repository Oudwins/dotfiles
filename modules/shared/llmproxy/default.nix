{ config, lib, ... }:

let
  address = config.agentServices.llmproxy.address;
in
{
  # Clients use http://127.0.0.1:28760/llmproxy; Agent Vault adds the client key.
  # The port matches home-files/tmx/.cli-proxy-api/config.yaml.
  agentServices.llmproxy = {
    local = "http://llmproxy.localhost:8317";
    variable = "LLM_PROXY_URL";
  };

  services.cli-proxy-api.enable = lib.mkDefault (address == null);

  assertions = [
    {
      # The router forwards subpaths only to targets without a path.
      assertion = address == null || builtins.match "https?://[^/]+/?" address != null;
      message = "agentServices.llmproxy.address must not include a path.";
    }
  ];
}
