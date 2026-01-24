{ config, pkgs, ... }:

{
  services.displayManager = {
    sddm.enable = true;
    defaultSession = "none+awesome";
  };
  services.xserver = {
    enable = true;
    windowManager.awesome = {
      enable = true;
      luaModules = with pkgs.luaPackages; [
        luarocks
        luadbi-mysql
      ];
    };
    xkb = {
      layout = "us,es";
      variant = "";
    };
  };

  services.autorandr.enable = true;
  programs.dconf.enable = true;
  programs.light.enable = true;

  programs.thunar.enable = true;
  programs.thunar.plugins = [ pkgs.xfce.thunar-archive-plugin ];
  programs.xfconf.enable = true;

  console = {
    packages = [ pkgs.terminus_font ];
    font = "${pkgs.terminus_font}/share/consolefonts/ter-i22b.psf.gz";
    useXkbConfig = true;
  };

  fonts = {
    packages = with pkgs; [
      noto-fonts
      noto-fonts-cjk-sans
      noto-fonts-color-emoji
      font-awesome
      source-han-sans
      source-han-sans
      source-han-serif
      nerd-fonts.meslo-lg
    ];
    fontconfig = {
      enable = true;
      defaultFonts = {
        monospace = [ "Meslo LG M regular Nerd Font Complete Mono" ];
        serif = [
          "noto Serif"
          "Source Han Serif"
        ];
        sansSerif = [
          "Noto Sans"
          "Source Han Sans"
        ];
      };
    };
  };

  environment.systemPackages = with pkgs; [
    awesome
    adwaita-icon-theme
  ];
}
