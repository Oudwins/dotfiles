{ config, pkgs, ... }:

{
  services.teamviewer.enable = true;

  services.flatpak.enable = true;
  xdg.portal = {
    enable = true;
    extraPortals = [ pkgs.xdg-desktop-portal-gtk ];
    config.common.default = "*";
  };

  services.printing.enable = true;
  services.avahi = {
    enable = true;
    nssmdns4 = true;
    openFirewall = true;
  };
  services.printing.drivers = [
    pkgs.gutenprint
    pkgs.cnijfilter2
  ];

  services.pulseaudio.enable = false;
  security.rtkit.enable = true;
  services.pipewire = {
    enable = true;
    alsa.enable = true;
    alsa.support32Bit = true;
    pulse.enable = true;
  };

  services.tailscale = {
    enable = true;
    package = pkgs.unstable.tailscale;
  };

  services.ratbagd.enable = true;

  environment.systemPackages = with pkgs; [
    gutenprint
    cnijfilter2
    alsa-utils
    pulseaudio
    unstable.tailscale
    eddie
  ];
}
