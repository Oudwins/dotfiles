{
  config,
  lib,
  pkgs,
  ...
}:
let
  port = 8384;
  domain = "${config.my.services.syncthing.subdomain}.${config.my.server.location}.${config.my.domain}";
  protocol = "https://";
in
{

  # WARNING TO CONNECT THE SYNCTHING FOLDER WITH NEXTCLOUD SEE THIS TUTORIAL:
  # https://itcamefromtheinternet.com/blog/how-to-setup-nextcloud-syncthing/#step-8-add-syncthing-folder-to-nextcloud
  # One can also configure direct connection to the server via adding custom IP for server like so:
  # tcp://<Device's tailscale IP>:22000

  # secrets
  sops.secrets."syncthing/key.pem" = {
    owner = "nginx";
    group = "nginx";
  };
  sops.secrets."syncthing/cert.pem" = {
    owner = "nginx";
    group = "nginx";
  };

  # users.users.syncthing = {
  #   isSystemUser = true;
  #   extraGroups = [ "nginx" ];
  # };

  systemd.tmpfiles.rules =
    let
      user = "nginx";
      group = "nginx";
      dataDir = "/srv/syncthing";
    in
    [
      #Type Path                      Mode UID     GID      Age Argument
      "d    ${dataDir}                0755 ${user} ${group} -   -"

    ];

  services.syncthing = {
    enable = true;
    user = "nginx";
    key = config.sops.secrets."syncthing/key.pem".path;
    cert = config.sops.secrets."syncthing/cert.pem".path;
    guiAddress = "0.0.0.0:8384"; # this allows us to access the gui outside localhost
    overrideDevices = true; # removes devices not defined in the settings
    settings = {
      devices = {
        "nixos" = {
          id = "GMKOKJR-2OLBQX5-KJK4POQ-4GOH4FG-3PRF4TR-GAZCOVG-ASFRNZU-2G25CAO";
        };
        "android" = {
          id = "IIWFNSD-AYRYTXC-XOCK2TM-ZXBYENR-LPI4W2A-W234XI2-KMYIUBM-3XVZNQY";
        };
        "androidv2" = {
          id = "Y6TFEFI-KINOLQO-QHYWAQV-JMKW36K-WBKFFWF-UMHPFIZ-ZSVGIJW-I2ELFAK";
        };
        "tower" = {
          id = "H57ONCX-N7P6OCI-U7Y5HQY-US52OXX-JJWI2QE-3PWCIFW-I3CQP4D-T5UW5QF";
        };
      };
      folders = {
        "notes" = {
          path = "/srv/syncthing/notes";
          devices = [
            "nixos"
            "tower"
            "androidv2"
          ];
          versioning = {
            type = "staggered";
            # fsPath = "/syncthing/backup";
            params = {
              cleanInterval = "7200";
              maxAge = "31536000";
            };
          };
        };
        "images" = {
          path = "/srv/syncthing/images";
          devices = [
            "nixos"
            "androidv2"
          ];
          versioning = {
            type = "staggered";
            # fsPath = "/syncthing/backup";
            params = {
              cleanInterval = "7200";
              maxAge = "31536000";
            };
          };
        };
      };
    };
  };

  systemd.services.syncthing.environment.STNODEFAULTFOLDER = "true"; # Don't create default ~/Sync folder

  services.nginx.virtualHosts."${domain}" = {
    useACMEHost = "${config.my.server.location}.${config.my.domain}";
    addSSL = true;
    locations."/" = {
      proxyPass = "http://localhost:${toString port}";
      proxyWebsockets = true; # Enable if needed
    };
  };
  my.dashboard.services.syncthing = {
    label = "Syncthing";
    description = "File synchronization";
    url = "${protocol}${domain}";
    category = "apps";
    icon = "syncthing";
  };
}
