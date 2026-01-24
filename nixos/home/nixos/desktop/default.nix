{ config, pkgs, ... }:

{
  programs.brave = {
    enable = true;
    commandLineArgs = [
      "--password-store=basic"
    ];
  };

  programs.mpv = {
    enable = true;
    package = pkgs.mpv-unwrapped;
  };

  xdg.mimeApps.defaultApplications = {
    "video/x-matroska" = [ "mpv.desktop" ];
    "text/html" = [ "brave-browser.desktop" ];
    "x-scheme-handler/http" = [ "brave-browser.desktop" ];
    "x-scheme-handler/https" = [ "brave-browser.desktop" ];
  };

  programs.rofi = {
    enable = true;
    theme = config.home.homeDirectory + "/dotfiles/tmx/.config/rofi/themes/erebus.rasi";
    plugins = [
      pkgs.rofi-calc
      pkgs.rofi-emoji
    ];
    extraConfig = {
      kb-clear-line = "Control+c,Control+u";
      kb-row-up = "Up,Control+k,Shift+Tab";
      kb-row-down = "Down,Control+j,Tab";
      kb-accept-entry = "Return,KP_Enter,Control+y";
      kb-element-next = "";
      kb-remove-to-sol = "";
      kb-remove-to-eol = "";
      kb-mode-previous = "";
      kb-mode-next = "";
      kb-mode-complete = "";
      kb-secondary-copy = "";
    };
  };

  dconf.settings = {
    "org/gnome/desktop/background" = {
      picture-uri-dark = "file://${pkgs.nixos-artwork.wallpapers.nineish-dark-gray.src}";
    };
    "org/gnome/desktop/interface" = {
      color-scheme = "prefer-dark";
    };
  };

  gtk = {
    enable = true;
    theme = {
      name = "Adwaita-dark";
      package = pkgs.gnome-themes-extra;
    };
  };

  qt.enable = true;
  qt.platformTheme.name = "gtk";
  qt.style.name = "adwaita-dark";
  qt.style.package = pkgs.adwaita-qt;
}
