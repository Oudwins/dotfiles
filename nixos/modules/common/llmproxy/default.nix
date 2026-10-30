{
  config,
  lib,
  ...
}:

let
  address = config.llmProxy.address;
in
{
  imports = [ ../cli-proxy-api ];

  options.llmProxy.address = lib.mkOption {
    type = lib.types.strMatching "[0-9a-fA-F:.]+";
    default = "127.0.0.1";
    example = "192.168.1.50";
    description = "Hosts-file address for llmproxy.tristanmayo.com. Loopback runs the local proxy; another IP selects a remote proxy and disables the local service.";
  };

  config.services.cli-proxy-api.enable = lib.mkDefault (
    builtins.elem address [
      "127.0.0.1"
      "::1"
    ]
  );
}
