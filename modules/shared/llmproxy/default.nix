{
  config,
  lib,
  pkgs,
  isDarwin,
  ...
}:

let
  address = config.llmProxy.address;
  hostname = "llmproxy.${config.my.domain}";
in
{
  options.llmProxy.address = lib.mkOption {
    type = lib.types.strMatching "[0-9a-fA-F:.]+";
    default = "127.0.0.1";
    example = "192.168.1.50";
    description = "Hosts-file address for llmproxy.<my.domain>. Loopback runs the local proxy; another IP selects a remote proxy and disables the local service.";
  };

  config = {
    services.cli-proxy-api.enable = lib.mkDefault (
      builtins.elem address [
        "127.0.0.1"
        "::1"
      ]
    );
  }
  // (
    if isDarwin then
      {
        # nix-darwin has no networking.hosts option; preserve other hosts-file entries.
        system.activationScripts.postActivation.text = ''
          ${pkgs.python3}/bin/python3 ${./update-hosts.py} ${hostname} ${lib.escapeShellArg address}
          /usr/bin/dscacheutil -flushcache
          /usr/bin/killall -HUP mDNSResponder || true
        '';
      }
    else
      { networking.hosts.${address} = [ hostname ]; }
  );
}
