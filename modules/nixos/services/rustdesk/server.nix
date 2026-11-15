{ config, lib, pkgs, ... }:

{ 

  # TODO. This has been left mid way through. Finish it
  # I don't really need a server because I'm using tailscale.
  # So this maybe should go on the external server not home lab.
  # References:
  # https://discourse.nixos.org/t/rustdesk-systemd-service-config/34281
  # https://mynixos.com/search?q=services.rustdesk

  services.rustdesk-server = {
    enable = true;
    openFirewall = true;
    relay = {
      enable = true;
  #       documentation = [ 
  #   "https://rustdesk.com/docs/en/self-host/rustdesk-server-oss/install/"
  #   "https://github.com/techahold/rustdeskinstall/blob/43df6297a9b8b5ff0f3e05ec4bd6e0f4c7281f88/install.sh"
  # ];
    };
    signal = {
      enable = true;
    };
  };
}
