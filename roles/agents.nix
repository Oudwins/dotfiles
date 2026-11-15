# Coding agents on a workstation: the LLM proxy (CLIProxyAPI), the Executor MCP
# gateway, Agent Vault, the PR review server and agent CLIs. Import this role
# from a host and configure it there:
#
#   agentServices.llmproxy.address = "https://tubby.<tailnet>.ts.net:8317"; # remote proxy
#   agentServices.executor.address = "https://executor.<tailnet>.ts.net/mcp"; # remote Executor
#
# Addresses must be hostnames (e.g. Tailscale MagicDNS), not IPs.
#
# Skills and commands live in agents/ and are linked by updateSymlinks.sh.
{
  config,
  lib,
  isDarwin,
  ...
}:

{
  imports = [
    ../modules/shared/agent-services
    ../modules/shared/cli-proxy-api
    (
      if isDarwin then
        ../modules/darwin/services/cli-proxy-api.nix
      else
        ../modules/nixos/services/cli-proxy-api
    )
    ../modules/shared/llmproxy
    ../modules/shared/mcp-gateway
  ];

  config = {
    home-manager.users.${config.my.username} = {
      imports = [ ../modules/home/common/agents ];
      services.agent-vault.ownerEmail = "${config.my.username}@${config.my.domain}";
    };
  }
  // lib.optionalAttrs (!isDarwin) {
    # OpenCode's prebuilt binaries need a dynamic loader.
    programs.nix-ld.enable = true;
  };
}
