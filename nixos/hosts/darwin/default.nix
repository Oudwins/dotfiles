{ config, lib, pkgs, ... }:

{
  imports = [
    ../../modules/darwin
    ../../modules/common/llmproxy
    ../../modules/common/mcp-gateway
    # ./config-files/aerospace.nix
  ];
  # services.aerospace.enable = false;

  users.users.tmx.home = "/Users/tmx";
  home-manager.backupFileExtension = "backup";
  system.stateVersion = 6;
  system.primaryUser = "tmx";

  # nix-darwin has no networking.hosts option; preserve other hosts-file entries.
  system.activationScripts.postActivation.text = ''
    ${pkgs.python3}/bin/python3 ${../../modules/common/llmproxy/update-hosts.py} llmproxy.tristanmayo.com ${lib.escapeShellArg config.llmProxy.address}
    /usr/bin/dscacheutil -flushcache
    /usr/bin/killall -HUP mDNSResponder || true
  '';
}
