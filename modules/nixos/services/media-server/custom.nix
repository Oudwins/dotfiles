{ pkgs, config, configLib, lib, ... }:

let
  # HOW TO TEST GLUETUN Connectivity to VPN
  #docker run --rm --network=container:gluetun alpine:3.18 sh -c "apk add wget && wget -qO- https://ipinfo.io" # Run a new container connecting to gluetun
  # connect to transmission_media container & test connectivity there
  #docker exec -it transmission_media bash
  #wget -qO- https://ipinfo.io
  # RESOURCES
  # - https://github.com/TechHutTV/homelab/tree/main/media#testing-gluetun-connectivity
  # - https://github.com/rasmus-kirk/nixarr
  # - https://nixarr.com/wiki/setup/
  # - https://trash-guides.info/
  mediaDir = "${config.my.services.baseDataDir}/media";
  downloadDir = "${mediaDir}/torrents";
  incompleteDir = "${mediaDir}/torrents/.incomplete";
  watchDir = "${mediaDir}/torrents/.watch";

  mediaGroup = "media";
  radarrPort = 7878;
  sonarrPort = 8989;
  bazarrPort = 6767;
  prowlarrPort = 9696;
  flareSolverPort = 8191;
  navidromePort = 4533;
  navidromeHost =
    "${config.my.services.media.navidrome.subdomain}.${config.my.server.location}.${config.my.domain}";
  # The published openapi.json is unversioned and changes on every docs deploy,
  # so bundle the spec from a pinned commit instead.
  openSubsonicSrc = pkgs.fetchFromGitHub {
    owner = "opensubsonic";
    repo = "opensubsonic.github.io";
    rev = "dfbfccf427c2dd33f6a9effd68a5de427c2aec83";
    hash = "sha256-ofDTYnmIt95HRGPnyuRoBIdPHv/rOoNrcdRx8AKBuhI=";
  };
  navidromeOpenapi = pkgs.runCommand "navidrome-openapi.json" {
    nativeBuildInputs = [ pkgs.redocly pkgs.jq ];
    REDOCLY_TELEMETRY = "off";
  } ''
    export HOME=$TMPDIR
    redocly bundle ${openSubsonicSrc}/openapi/openapi.json -o bundled.json
    jq '.servers = [{ "url": "https://${navidromeHost}" }]' bundled.json > $out
  '';
  lidarrPort = 8686;
  audiobookshelfPort = 13378;
  tld = "home";
  cfg = config.my.media_server;
  torrentUser = "torrenter";
  streamingUser = "streamer";
  musicStreamingUser = "streamermusic";
  bookStreamingUser = "streamerbooks";

  transmissionPort = 9091;
  transmissionPeerPort = 14454;
  transmissionConfigDir = "${mediaDir}/transmission-config";

  # Generate transmission settings.json
  transmissionSettings = pkgs.writeText "transmission-settings.json"
    (builtins.toJSON {
      "download-dir" = downloadDir;
      "incomplete-dir-enabled" = true;
      "incomplete-dir" = incompleteDir;
      "watch-dir-enabled" = true;
      "watch-dir" = watchDir;

      # RPC/Web UI settings
      "rpc-port" = transmissionPort;
      "rpc-whitelist-enabled" = true;
      "rpc-whitelist" = "127.0.0.1,::1,*.ts.net,*${config.my.domain},*";
      "rpc-host-whitelist" = "";
      "rpc-host-whitelist-enabled" = false;
      "rpc-authentication-required" = false;
      "rpc-bind-address" = "0.0.0.0";
      "rpc-enabled" = true;
      "rpc-url" = "/transmission/";

      # Security settings
      "blocklist-enabled" = true;
      "blocklist-url" =
        "https://github.com/Naunter/BT_BlockLists/raw/master/bt_blocklists.gz";
      "utp-enabled" = true;
      "encryption" = 1;
      "port-forwarding-enabled" = false;

      # Performance settings
      "download-queue-size" = 10;
      "cache-size-mb" = 50;

      # Ratio settings
      "ratio-limit" = 2;
      "ratio-limit-enabled" = true;
      "idle-seeding-limit-enabled" = true;
      "idle-seeding-limit" = 60 * 24; # 24h

      # Peer port
      "peer-port" = transmissionPeerPort;
    });

in {
  imports = [
    (configLib.relativeToRoot "modules/nixos/services/nginx")
    (configLib.relativeToRoot "modules/nixos/services/transmission")
    (configLib.relativeToRoot "modules/nixos/services/containers")
  ];

  options = {
    my.media_server.enable =
      lib.mkEnableOption "Serve and store media from this machine";
    my.media_server.export_metrics = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Export Prometheus metrics from media services";
    };
  };

  config = lib.mkIf cfg.enable {
    # Set up the users/groups
    users.groups = {
      "${torrentUser}" = {
        gid = 978; # needs to be explicitly defined to be able to reference it
      };
      "${streamingUser}" = { };
      "${musicStreamingUser}" = { };
      "${bookStreamingUser}" = { };
      "${mediaGroup}" = {
        members = [ "radarr" "sonarr" "bazarr" "zmitchell" streamingUser ];
      };
    };
    users.users = {
      "${torrentUser}" = {
        uid = 981;
        isSystemUser = true;
        group = "${torrentUser}";
        extraGroups = [ mediaGroup ];
      };
      "${musicStreamingUser}" = {
        isSystemUser = true;
        group = mediaGroup;
      };
      "${bookStreamingUser}" = {
        isSystemUser = true;
        group = mediaGroup;
      };
      "${streamingUser}" = {
        isSystemUser = true;
        group = "${streamingUser}";
        extraGroups = [ mediaGroup ]
          ++ (if config.my.hardwareAcceleration.enable then
            config.my.hardwareAcceleration.groups
          else
            [ ]); # gives streaming user (i.e jellyfin) access to hardware acceleration groups

      };
    };

    # Create the directories that the services will need with the correct permissions
    # TODO -> add music, books,
    systemd.tmpfiles.rules = [
      "d ${mediaDir} 0775 root ${mediaGroup} -"
      "d ${mediaDir}/library/Movies 0775 ${streamingUser} ${mediaGroup} -"
      "d ${mediaDir}/library/TV 0775 ${streamingUser} ${mediaGroup} -"
      "d ${mediaDir}/library/Audiobooks 0775 ${bookStreamingUser} ${mediaGroup} -"
      "d ${mediaDir}/library/Books 0775 ${bookStreamingUser} ${mediaGroup} -"
      "d ${mediaDir}/library/Music 0775 ${musicStreamingUser} ${mediaGroup} -"
      "d ${mediaDir}/torrents 0775 ${torrentUser} ${mediaGroup} -"
      "d ${mediaDir}/torrents/radarr 0775 ${torrentUser} ${mediaGroup} -"
      "d ${mediaDir}/torrents/sonarr 0775 ${torrentUser} ${mediaGroup} -"
      "d ${mediaDir}/torrents/bazarr 0775 ${torrentUser} ${mediaGroup} -"
      "d ${mediaDir}/torrents/lidarr 0775 ${torrentUser} ${mediaGroup} -"
      "d ${downloadDir} 0775 ${torrentUser} ${mediaGroup} -"
      "d ${incompleteDir} 0775 ${torrentUser} ${mediaGroup} -"
      "d ${watchDir} 0775 ${torrentUser} ${mediaGroup} -"
      "d ${transmissionConfigDir} 0775 ${torrentUser} ${torrentUser} -"
      "C ${transmissionConfigDir}/settings.json 0644 ${torrentUser} ${torrentUser} - ${transmissionSettings}"
    ];

    #########################################################
    # Jellyfin
    # /var/lib/jellyfin
    # runs on port 8096
    # TODO -> backups!
    #########################################################
    environment.systemPackages = with pkgs; [
      jellyfin
      jellyfin-web
      jellyfin-ffmpeg
    ];

    systemd.services.jellyfin.environment.LIBVA_DRIVER_NAME =
      lib.mkIf config.my.hardwareAcceleration.enable
      config.my.hardwareAcceleration.LIBVA_DRIVER_NAME;
    services.jellyfin = {
      enable = true;
      user = streamingUser;
      group = mediaGroup;
      # openFirewall = true;
    };

    services.nginx.virtualHosts."${config.my.services.media.jellyfin.subdomain}.${config.my.server.location}.${config.my.domain}" =
      let jellyfinPort = 8096;
      in {
        #enableACME = true;
        #forceSSL = true;
        useACMEHost = "${config.my.server.location}.${config.my.domain}";
        addSSL = true;
        locations."/" = {
          proxyPass = "http://localhost:${toString jellyfinPort}";
          proxyWebsockets = true; # Enable if needed
        };
      };

    my.dashboard.services.jellyfin = {
      label = "Jellyfin";
      description = "Watch stuff";
      url =
        "https://${config.my.services.media.jellyfin.subdomain}.${config.my.server.location}.${config.my.domain}";
      category = "media";
      icon = "jellyfin";
    };

    #########################################################
    # Jellyseerr
    # DB is sqlite3 db
    # /var/lib/jellyseerr/config
    # runs on port 5055
    # TODO -> backups!
    #########################################################

    services.jellyseerr = {
      enable = true;
      # openFirewall = true;
    };

    services.nginx.virtualHosts."${config.my.services.media.jellyseerr.subdomain}.${config.my.server.location}.${config.my.domain}" =
      let jellyseerrPort = 5055;
      in {
        #enableACME = true;
        #forceSSL = true;
        useACMEHost = "${config.my.server.location}.${config.my.domain}";
        addSSL = true;
        locations."/" = {
          proxyPass = "http://localhost:${toString jellyseerrPort}";
          proxyWebsockets = true; # Enable if needed
        };
      };

    my.dashboard.services.jellyseerr = {
      label = "Jellyseerr";
      description = "Request Movies and TV Shows";
      url =
        "https://${config.my.services.media.jellyseerr.subdomain}.${config.my.server.location}.${config.my.domain}";
      category = "media";
      icon = "jellyseerr";
    };

    #########################################################
    # Bazarr
    # DB is sqlite3 db
    # /var/lib/bazarr
    # runs on port 6767
    # Has some backup folder. Not sure what it does
    # TODO -> backups!
    #########################################################

    services.bazarr = {
      enable = true;
      group = mediaGroup;
      # openFirewall = true;
    };

    services.nginx.virtualHosts."${config.my.services.media.bazarr.subdomain}.${config.my.server.location}.${config.my.domain}" =
      {
        #enableACME = true;
        #forceSSL = true;
        useACMEHost = "${config.my.server.location}.${config.my.domain}";
        addSSL = true;
        locations."/" = {
          proxyPass = "http://localhost:${toString bazarrPort}";
          proxyWebsockets = true; # Enable if needed
        };
      };

    my.dashboard.services.bazarr = {
      label = "Bazarr";
      description = "Bazarr";
      url =
        "https://${config.my.services.media.bazarr.subdomain}.${config.my.server.location}.${config.my.domain}";
      category = "management";
      icon = "bazarr";
    };

    #########################################################
    # Sonarr
    # DB is sqlite3 db
    # /var/lib/sonarr/.config/NzbDrone
    # runs on port 8989
    # TODO -> backups!
    #########################################################

    services.sonarr = {
      # The package is broken at the moment
      enable = true;
      group = mediaGroup;
      # openFirewall = true;
    };

    services.nginx.virtualHosts."${config.my.services.media.sonarr.subdomain}.${config.my.server.location}.${config.my.domain}" =
      {
        #enableACME = true;
        #forceSSL = true;
        useACMEHost = "${config.my.server.location}.${config.my.domain}";
        addSSL = true;
        locations."/" = {
          proxyPass = "http://localhost:${toString sonarrPort}";
          proxyWebsockets = true; # Enable if needed
        };
      };

    my.dashboard.services.sonarr = {
      label = "Sonarr";
      description = "TV Shows";
      url =
        "https://${config.my.services.media.sonarr.subdomain}.${config.my.server.location}.${config.my.domain}";
      category = "management";
      icon = "sonarr";
    };

    #########################################################
    # Radarr
    # DB is sqlite3 db
    # /var/lib/radarr/.config/Radarr
    # runs on port 7878
    # TODO -> backups!
    #########################################################

    services.radarr = {
      enable = true;
      group = mediaGroup;
      # openFirewall = true;
    };

    services.nginx.virtualHosts."${config.my.services.media.radarr.subdomain}.${config.my.server.location}.${config.my.domain}" =
      {
        #enableACME = true;
        #forceSSL = true;
        useACMEHost = "${config.my.server.location}.${config.my.domain}";
        addSSL = true;
        locations."/" = {
          proxyPass = "http://localhost:${toString radarrPort}";
          proxyWebsockets = true; # Enable if needed
        };
      };

    my.dashboard.services.radarr = {
      label = "Radarr";
      description = "Movies";
      url =
        "https://${config.my.services.media.radarr.subdomain}.${config.my.server.location}.${config.my.domain}";
      category = "management";
      icon = "radarr";
    };

    #########################################################
    # Lidarr
    # DB is sqlite3 db
    # /var/lib/lidarr/.config/Lidarr
    # runs on port 7878
    # TODO -> backups!
    #########################################################
    services.lidarr = {
      enable = true;
      group = mediaGroup;
    };

    services.nginx.virtualHosts."${config.my.services.media.lidarr.subdomain}.${config.my.server.location}.${config.my.domain}" =
      {
        #enableACME = true;
        #forceSSL = true;
        useACMEHost = "${config.my.server.location}.${config.my.domain}";
        addSSL = true;
        locations."/" = {
          proxyPass = "http://localhost:${toString lidarrPort}";
          proxyWebsockets = true; # Enable if needed
        };
      };

    my.dashboard.services.lidarr = {
      label = "Lidarr";
      description = "Music";
      url =
        "https://${config.my.services.media.lidarr.subdomain}.${config.my.server.location}.${config.my.domain}";
      category = "management";
      icon = "lidarr";
    };

    #########################################################
    # Prowlarr
    # DB is sqlite3 db
    # /var/lib/prowlarr
    # runs on port 9696
    # TODO -> backups!
    # Indexes:
    # 1337x
    # YTS, Torrentdownoad, knaben, torlock
    # https://www.reddit.com/r/sonarr/comments/1jpas55/best_indexers_for_prowlarr/
    # Google for trackers
    # Public ones should be set to mannually sync
    #########################################################

    services.prowlarr = {
      enable = true;
      # openFirewall = true;
    };

    services.nginx.virtualHosts."${config.my.services.media.prowlarr.subdomain}.${config.my.server.location}.${config.my.domain}" =
      {
        #enableACME = true;
        #forceSSL = true;
        useACMEHost = "${config.my.server.location}.${config.my.domain}";
        addSSL = true;
        locations."/" = {
          proxyPass = "http://localhost:${toString prowlarrPort}";
          proxyWebsockets = true; # Enable if needed
        };
      };

    my.dashboard.services.prowlarr = {
      label = "Prowlarr";
      description = "Prowlarr";
      url =
        "https://${config.my.services.media.prowlarr.subdomain}.${config.my.server.location}.${config.my.domain}";
      category = "management";
      icon = "prowlarr";
    };

    # Flaresolver for bypassing cloudflare
    services.flaresolverr = {
      enable = true;
      port = flareSolverPort;
    };

    #########################################################
    # Recyclarr
    # Syncs TRaSH Guides quality definitions, profiles and
    # custom formats into Sonarr/Radarr (daily timer)
    # https://trash-guides.info/Recyclarr/
    # Templates: https://github.com/recyclarr/config-templates
    #########################################################

    # Sonarr/Radarr generate their API keys into config.xml; read them from there
    # so Recyclarr always uses the live keys
    systemd.services.recyclarr-api-keys = {
      description = "Export Sonarr and Radarr API keys for Recyclarr";
      requires = [ "sonarr.service" "radarr.service" ];
      after = [ "sonarr.service" "radarr.service" ];
      serviceConfig = {
        Type = "oneshot";
        UMask = "0077";
        RuntimeDirectory = "recyclarr-api-keys";
        RuntimeDirectoryPreserve = true;
      };
      script = ''
        extract() { sed -n 's:.*<ApiKey>\(.*\)</ApiKey>.*:\1:p' "$1/config.xml" | grep . > "$RUNTIME_DIRECTORY/$2"; }
        extract ${config.services.sonarr.dataDir} sonarr
        extract ${config.services.radarr.dataDir} radarr
      '';
    };

    systemd.services.recyclarr = {
      requires = [ "recyclarr-api-keys.service" ];
      after = [ "recyclarr-api-keys.service" ];
    };

    services.recyclarr = {
      enable = true;
      configuration = {
        # https://github.com/recyclarr/config-templates/blob/master/sonarr/templates/web-1080p.yml
        sonarr.sonarr-main = {
          base_url = "http://localhost:${toString sonarrPort}";
          api_key._secret = "/run/recyclarr-api-keys/sonarr";
          quality_definition.type = "series";
          quality_profiles = [{
            trash_id = "72dae194fc92bf828f32cde7744e51a1"; # WEB-1080p
            reset_unmatched_scores.enabled = true;
          }];
        };
        # https://github.com/recyclarr/config-templates/blob/master/radarr/templates/hd-bluray-web.yml
        radarr.radarr-main = {
          base_url = "http://localhost:${toString radarrPort}";
          api_key._secret = "/run/recyclarr-api-keys/radarr";
          quality_definition.type = "movie";
          quality_profiles = [{
            trash_id = "d1d67249d3890e49bc12e275d989a7e9"; # HD Bluray + WEB
            reset_unmatched_scores.enabled = true;
          }];
        };
      };
    };

    #########################################################
    # Navidrome
    #
    #########################################################
    services.navidrome = {
      enable = true;
      user = musicStreamingUser;
      group = mediaGroup;
      # Configured as per: https://www.navidrome.org/docs/usage/configuration-options/
      settings = { MusicFolder = "${mediaDir}/library/Music"; };
      # environmentFile = {};
    };

    services.nginx.virtualHosts."${navidromeHost}" = {
      #enableACME = true;
      #forceSSL = true;
      useACMEHost = "${config.my.server.location}.${config.my.domain}";
      addSSL = true;
      locations."= /openapi.json" = {
        alias = navidromeOpenapi;
        extraConfig = "default_type application/json;";
      };
      locations."/" = {
        proxyPass = "http://localhost:${toString navidromePort}";
        proxyWebsockets = true; # Enable if needed
      };
    };

    my.dashboard.services.navidrome = {
      label = "Navidrome";
      description = "Music Streaming Player (Spotify)";
      url =
        "https://${config.my.services.media.navidrome.subdomain}.${config.my.server.location}.${config.my.domain}";
      category = "media";
      icon = "navidrome";
    };

    #################################
    # AudioBooks
    #################################

    services.audiobookshelf = {
      enable = true;
      user = bookStreamingUser;
      group = mediaGroup;
      port = audiobookshelfPort;
    };

    services.nginx.virtualHosts."${config.my.services.media.audiobookshelf.subdomain}.${config.my.server.location}.${config.my.domain}" =
      {
        #enableACME = true;
        #forceSSL = true;
        useACMEHost = "${config.my.server.location}.${config.my.domain}";
        addSSL = true;
        locations."/" = {
          proxyPass = "http://localhost:${toString audiobookshelfPort}";
          proxyWebsockets = true; # Enable if needed
        };
      };

    my.dashboard.services.audiobookshelf = {
      label = "Audiobookshelf";
      description = "Audiobookshelf";
      url =
        "https://${config.my.services.media.audiobookshelf.subdomain}.${config.my.server.location}.${config.my.domain}";
      category = "media";
      icon = "audiobookshelf";
    };

    #################################
    # Service I didn't want to setup
    #################################
    # services.sabnzbd = {
    #   enable = true;
    #   group = mediaGroup;
    # };

    #########################################################
    # Transmission
    # Runs in container
    #########################################################
    sops.secrets."gluetun/env_file" = { };

    virtualisation.oci-containers.containers = let
      userId = toString config.users.users.${torrentUser}.uid;
      groupId = toString config.users.groups.${torrentUser}.gid;
      gluetunTag = "pr-3465";
      transmissionTag = "4.0.6";
    in {
      transmission_media = {
        autoStart = true;
        dependsOn = [ "gluetun" ];
        image =
          "linuxserver/transmission:${transmissionTag}"; # OCI/Docker image
        serviceName = "transmission_media";
        user = "${userId}:${groupId}";
        volumes =
          [ "${mediaDir}:${mediaDir}" "${transmissionConfigDir}:${"/config"}" ];

        environment = {
          PUID = userId;
          PGID = groupId;
          TZ = "Etc/UTC";
          WHITELIST = "127.0.0.1,::1,*.ts.net,*${config.my.domain},*";
          PEERPORT = toString transmissionPeerPort;
          HOST_WHITELIST = "localhost,127.0.0.1,::1,*.ts.net,*${config.my.domain},*";
          TRANSMISSION_WEB_HOME = "";
        };

        extraOptions = [
          "--cpu-shares=512"
          "--blkio-weight=300"
          "--network=container:gluetun"
        ];
      };

      gluetun = {
        autoStart = true;
        image = "ghcr.io/qdm12/gluetun:${gluetunTag}";
        serviceName = "gluetun";
        # Ports (host:container)
        ports = [
          "${toString transmissionPort}:${toString transmissionPort}" # Web UI
          "${toString transmissionPeerPort}:${toString transmissionPeerPort}"
        ];
        devices = [ "/dev/net/tun:/dev/net/tun" ];
        capabilities = { NET_ADMIN = true; };
        volumes = [ "/var/lib/gluetun:/gluetun" ];
        environmentFiles = [ config.sops.secrets."gluetun/env_file".path ];
      };
    };

    # Required for gluetun
    boot.kernelModules = [ "tun" ];

    # Always prioritize other services wrt. I/O
    # No longer needed since we are running inside a container
    # systemd.services.transmission.serviceConfig.IOSchedulingPriority = 7;

    services.nginx.virtualHosts."${
      "trans"
    }.${config.my.server.location}.${config.my.domain}" = {
      #enableACME = true;
      #forceSSL = true;
      useACMEHost = "${config.my.server.location}.${config.my.domain}";
      addSSL = true;
      locations."/" = {
        proxyPass = "http://localhost:${toString transmissionPort}";
        proxyWebsockets = true; # Enable if needed
      };
    };

    my.dashboard.services.transmission_media = {
      label = "Transmission Media";
      description = "Torrent client for media";
      url =
        "https://${"trans"}.${config.my.server.location}.${config.my.domain}";
      category = "management";
      icon = "transmission";
    };

  };
}
