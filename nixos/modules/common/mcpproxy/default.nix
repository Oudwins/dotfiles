{ config, lib, ... }:

{
  options.mcpProxy.address = lib.mkOption {
    type = lib.types.strMatching "[0-9a-fA-F:.]+";
    default = "127.0.0.1";
    example = "192.168.1.50";
    description = "Hosts-file address for mcp.tristanmayo.com. Loopback runs local Executor; another IP selects remote Executor and disables the local service.";
  };

  config.home-manager.users.tmx.services.executor.enable = lib.mkDefault (
    builtins.elem config.mcpProxy.address [ "127.0.0.1" "::1" ]
  );
}
