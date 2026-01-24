{ config, ... }:

{
  services = {
    syncthing = {
      enable = true;
      extraOptions = [
        "--home=/home/tmx/.config/syncthing"
        "--no-default-folder"
      ];
    };
    redshift = {
      enable = true;
      temperature = {
        day = 5700;
        night = 3500;
      };
      tray = true;
      dawnTime = "05:00";
      duskTime = "21:00";
    };
    udiskie = {
      enable = true;
      notify = false;
      tray = "never";
    };
    flameshot = {
      enable = true;
      settings = {
        General = {
          disabledTrayIcon = true;
          showStartupLaunchMessage = false;
          savePath = config.home.homeDirectory + "/Downloads/";
          saveAsFileExtension = ".jpg";
          showHelp = false;
        };
      };
    };
    espanso = {
      enable = true;
      waylandSupport = false;
      x11Support = true;
      configs = {
        default = {
          search_shortcut = "off";
          search_trigger = ":search";
          show_notifications = false;
        };
      };
    };
  };
}
