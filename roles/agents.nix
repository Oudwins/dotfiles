# Coding agents on a workstation: the LLM proxy (CLIProxyAPI), the Executor MCP
# gateway, Agent Vault, the PR review server and agent CLIs. Import this role
# from a host and configure it there:
#
#   llmProxy.address = "192.168.1.50";              # use another machine's proxy
#   mcp-gateway.address = "https://…/mcp";          # use a remote Executor
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
    home-manager.users.${config.my.username}.imports = [ ../modules/home/common/agents ];
  }
  // lib.optionalAttrs (!isDarwin) {
    # OpenCode's prebuilt binaries need a dynamic loader.
    programs.nix-ld.enable = true;
  };
}
