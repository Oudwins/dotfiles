{ config, configLib, pkgs, ... }@args:
let
  user = "nextcloud";
  group = "nextcloud";
in
{
  imports = [
    ./backup.nix
    ./docs/collabora
    (configLib.relativeToRoot "modules/nixos/services/nginx")
  ];
  # File's location -> /var/lib/nextcloud
  # WARNING. if reinstalling you should manually remove the /var/lib/nextcloud dir. Otherwise some options will not actually update from first install
  sops.secrets."nextcloud/admin_pass" = { owner = "nextcloud"; };

  # These are served by nextcloud. Folder with my RPG books. These should be backed up separately! NOT CURRENTLY BACKED UP!
  systemd.tmpfiles.rules =
    let dataDir = "/srv/rpgs";
    in [
      #Type Path                      Mode UID     GID      Age Argument
      "d    ${dataDir}                0755 ${user} ${group} -   -"
    ];

  services.nginx.virtualHosts."${config.my.services.nextcloud.subdomain}.${config.my.server.location}.${config.my.domain}" =
    {
      default = true;
      useACMEHost = "${config.my.server.location}.${config.my.domain}";
      addSSL = true;
    };

  services.nextcloud = {
    enable = true;
    package = pkgs.nextcloud33;
    hostName =
      "${config.my.services.nextcloud.subdomain}.${config.my.server.location}.${config.my.domain}";
    # hostName = "localhost";
    # config
    https = true;
    config = {
      overwriteProtocol = "https";
      adminuser =
        "${config.my.username}"; # root by default. not sure changing this actually works
      adminpassFile =
        config.sops.secrets."nextcloud/admin_pass".path; # /run/secrets/"nextcloud/admin_pass"

      dbtype = "pgsql"; # this doesn't work unless you setup a pg instance
      dbuser = "nextcloud";
      dbhost = "/run/postgresql"; # nextcloud will add /.s.PGSQL.5432 by itself
      dbname = "nextcloud";
      dbpassFile = config.sops.secrets."nextcloud/admin_pass".path;
    };

    # extra apps
    extraAppsEnable = true;
    extraApps = {
      inherit (config.services.nextcloud.package.packages.apps)
        contacts calendar mail tasks bookmarks
        # collabora office
        richdocuments
        # onlyoffice # Couldn't get this to work.
        ;
    };
    # settings
    maxUploadSize = "16G";
    phpOptions."opcache.interned_strings_buffer" = "16";
    settings = {
      log_type = "file";
      default_phone_region = "ES";
      maintenance_window_start = "20"; # UTC
      trusted_domains = [
        "${config.my.services.nextcloud.subdomain}.${config.my.server.location}.${config.my.domain}"
        "*.ts.net"
        "${config.my.services.nextcloud.subdomain}.${config.my.domain}"
      ];
      trusted_proxies = [
        "127.0.0.1"
        "localhost"
        "::1"
        "${config.my.services.nextcloud.subdomain}.${config.my.domain}"
      ];
      # ensures thrash and versions are deleted after a while. Otherwise nextcloud could keep the data around until it feels you "need" to delete it
      trashbin_retention_obligation = "30,60";
      version_retention_obligation = "30,180";
    };

    # infra
    configureRedis = true;

    # users only available with third party extension see docs
    # environment.etc."
    # nextcloud-user-pass
    #   ".text = "
    #   12345678910
    #   ";
    #       # ensureUsers = {
    #       #     h = {
    #       #       email = "
    #   h@localhost";
    #       passwordFile = "/etc/nextcloud-user-pass";
    #     };
    # };
  };

  # for ffmpeg thumbnail support
  environment.systemPackages = [ pkgs.ffmpeg ];

  services.postgresql = {
    enable = true;
    ensureDatabases = [ "nextcloud" ];
    ensureUsers = [{
      name = "nextcloud";
      #ensurePermissions."DATABASE nextcloud" = "ALL PRIVILEGES"; # option doesn't exist
      ensureDBOwnership = true;
    }];
  };
  # ensure Postgres users/databases exist before Nextcloud installs
  systemd.services."nextcloud-setup" = {
    requires = [ "postgresql-setup.service" "systemd-tmpfiles-setup.service" ];
    after = [ "postgresql-setup.service" "systemd-tmpfiles-setup.service" ];
  };

  my.dashboard.services.nextcloud = {
    label = "Nextcloud";
    description = "Personal cloud storage";
    url =
      "https://${config.my.services.nextcloud.subdomain}.${config.my.server.location}.${config.my.domain}";
    category = "apps";
    icon = "nextcloud";
  };
}
