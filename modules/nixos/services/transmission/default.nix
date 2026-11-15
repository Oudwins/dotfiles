{
  config,
  configLib,
  lib,
  pkgs,
  ...
}:

let
  port = 9092; # This is not the default because this way I can use the default for transmission that connects to media server. Makes config easier
  peerPort = 51413;
in
{

  imports = [
    (configLib.relativeToRoot "modules/nixos/services/nginx")
  ];

  services.transmission = {
    enable = true;
    package = pkgs.transmission_4;
    settings = {
      download-dir = "/srv/torrents/";
      incomplete-dir = "/srv/torrents-incomplete/";
      incomplete-dir-enabled = true;
      #rpc-whitelist = "127.0.0.1,192.168.1.*";
      # rpc-whitelist = "127.0.0.1,::1";
      rpc-authentication-required = false;
      rpc-port = port; # web ui port. RPC = webui
      rpc-whitelist-enabled = true;
      rpc-whitelist = "localhost:*,127.0.0.1,::1,*.ts.net,*${config.my.domain}";
      rpc-host-whitelist = "*";
      rpc-bind-address = "0.0.0.0"; # web server

      blocklist-enabled = true;
      blocklist-url = "https://github.com/Naunter/BT_BlockLists/raw/master/bt_blocklists.gz";
      utp-enabled = true;
      # peers (used for connecting to peers)
      peer-port = peerPort;
    };
    openPeerPorts = true; # allow incoming connections from peers
  };

  systemd.tmpfiles.rules =
    let
      user = "transmission";
      group = "transmission";
      downloadDir = config.services.transmission.settings.download-dir;
      incompleteDir = config.services.transmission.settings.incomplete-dir;
    in
    [
      #Type Path                      Mode UID     GID      Age Argument
      "d    ${downloadDir}            0755 ${user} ${group} -   -"
      "d    ${incompleteDir}          0755 ${user} ${group} -   -"

    ];

  services.nginx.virtualHosts."${config.my.services.transmission.subdomain}.${config.my.server.location}.${config.my.domain}" =
    {
      #enableACME = true;
      #forceSSL = true;
      useACMEHost = "${config.my.server.location}.${config.my.domain}";
      addSSL = true;
      locations."/" = {
        proxyPass = "http://localhost:${toString port}";
        proxyWebsockets = true; # Enable if needed
      };
    };

  my.dashboard.services.transmission = {
    label = "Transmission";
    description = "Torrent client";
    url = "https://${config.my.services.transmission.subdomain}.${config.my.server.location}.${config.my.domain}";
    category = "management";
    icon = "transmission";
  };
}
