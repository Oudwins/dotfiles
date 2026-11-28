{ config
, configLib
, lib
, pkgs
, ...
}:
let
  cfg = config.my.wordpressLiteSpeed;
  docker = config.virtualisation.oci-containers.backend;
  dockerBin = "${pkgs.${docker}}/bin/${docker}";
  containerRuntimeService = "${docker}.service";

  litespeedName = "wordpress-litespeed";
  redisName = "wordpress-litespeed-redis";

  adminConfDir = "${cfg.dataDir}/lsws/admin-conf";
  sitesDir = "${cfg.dataDir}/sites";
  logsDir = "${cfg.dataDir}/logs";
  redisDataDir = "${cfg.dataDir}/redis/data";
  serverNetworkName = cfg.networkName;

  siteInfos = lib.mapAttrs
    (
      name: site:
        let
          mysqlName = "wordpress-ls-${name}-mysql";
          phpmyadminName = "wordpress-ls-${name}-phpmyadmin";
          networkName = "wordpress_litespeed_${name}";
          databaseDir =
            if builtins.length (lib.attrNames cfg.sites) == 1 then
              "${cfg.dataDir}/data/db"
            else
              "${cfg.dataDir}/data/${name}/db";
          siteRoot = "${sitesDir}/${site.domain}";
          siteHtmlDir = "${siteRoot}/html";
          siteLogsDir = "${siteRoot}/logs";
          extraDomainNames = lib.optionals (site.wwwAlias && !(lib.hasPrefix "www." site.domain)) [
            "www.${site.domain}"
          ];
          vhDomains = lib.concatStringsSep "," ([ site.domain ] ++ extraDomainNames);
        in
        {
          inherit
            name
            site
            mysqlName
            phpmyadminName
            networkName
            databaseDir
            siteRoot
            siteHtmlDir
            siteLogsDir
            extraDomainNames
            vhDomains
            ;

          mysqlService = "${mysqlName}.service";
          phpmyadminService = "${phpmyadminName}.service";
          acmeService = "acme-${site.domain}.service";
        }
    )
    cfg.sites;

  siteList = lib.sort (a: b: a.name < b.name) (lib.attrValues siteInfos);
  primarySite = if siteList == [ ] then null else builtins.head siteList;

  mysqlContainerNames = map (siteInfo: siteInfo.mysqlName) siteList;
  mysqlServices = map (siteInfo: siteInfo.mysqlService) siteList;
  acmeServices = map (siteInfo: siteInfo.acmeService) siteList;
  siteDomains = map (siteInfo: siteInfo.site.domain) siteList;
  phpMyAdminPorts = map (siteInfo: siteInfo.site.phpMyAdminPort) siteList;
  listenerKeyFile =
    if cfg.hostAcme.enable && primarySite != null then
      "/etc/ssl/host-acme/${primarySite.site.domain}/key.pem"
    else
      "/usr/local/lsws/admin/conf/webadmin.key";
  listenerCertFile =
    if cfg.hostAcme.enable && primarySite != null then
      "/etc/ssl/host-acme/${primarySite.site.domain}/fullchain.pem"
    else
      "/usr/local/lsws/admin/conf/webadmin.crt";

  dockerTemplateFile = pkgs.writeText "wordpress-litespeed-docker.conf" ''
            allowSymbolLink           1
            enableScript              1
            restrained                1
            setUIDMode                2
            vhRoot 	/var/www/vhosts/$VH_NAME/
            configFile $SERVER_ROOT/conf/vhosts/$VH_NAME/vhconf.conf

            virtualHostConfig  {
              docRoot                 $VH_ROOT/html/
              enableGzip              1

              errorlog  {
                useServer             1
              }

              accesslog $SERVER_ROOT/logs/$VH_NAME.access.log {
                useServer             0
                rollingSize           10M
                keepDays              7
                compressArchive       1
              }

              index  {
                useServer             0
                indexFiles            index.html, index.php
                autoIndex             0
                autoIndexURI          /_autoindex/default.php
              }

              expires  {
                enableExpires         1
              }

              accessControl  {
                allow                 *
              }

              context / {
                location              $DOC_ROOT/
                allowBrowse           1

                rewrite  {
            RewriteFile .htaccess
                }
              }

          rewrite  {
            enable                1
            autoLoadHtaccess      1
            logLevel              0
            rules                 <<<END_rules
    RewriteCond %{HTTP_HOST} ^www\.$VH_NAME$ [NC]
    RewriteRule ^(.*)$ https://$VH_NAME%{REQUEST_URI} [R=301,L]
    RewriteCond %{HTTPS} !=on
    RewriteRule ^(.*)$ https://%{HTTP_HOST}%{REQUEST_URI} [R=301,L]
    END_rules
          }${lib.optionalString cfg.hostAcme.enable ''

            vhssl  {
              keyFile               /etc/ssl/host-acme/$VH_NAME/key.pem
              certFile              /etc/ssl/host-acme/$VH_NAME/fullchain.pem
              certChain             1
            }''}
            }
  '';

  dockerMembers = lib.concatMapStringsSep "\n"
    (siteInfo: ''
      member ${siteInfo.site.domain} {
        vhDomain              ${siteInfo.vhDomains}
      }'')
    siteList;

  httpdConfigFile = pkgs.writeText "wordpress-litespeed-httpd_config.conf" ''
        #
        # PLAIN TEXT CONFIGURATION FILE
        #

        # If not set, will use host name as serverName
        serverName
        user                             nobody
        group                            nogroup
        priority                         0
        autoRestart                      1
        chrootPath                       /
        enableChroot                     0
        inMemBufSize                     60M
        swappingDir                      /tmp/lshttpd/swap
        autoFix503                       1
        gracefulRestartTimeout           300
        mime                             conf/mime.properties
        showVersionNumber                0
        adminEmails                      root@localhost
        indexFiles                       index.html, index.php
        disableWebAdmin                  0

        errorlog logs/error.log {
                logLevel             DEBUG
                debugLevel           0
                rollingSize          10M
                enableStderrLog      1
        }

        accessLog logs/access.log {
                rollingSize          10M
                keepDays             30
                compressArchive      0
                logReferer           1
                logUserAgent         1
        }

        expires {
            enableExpires           1
            expiresByType           image/*=A604800,text/css=A604800,application/x-javascript=A604800,application/javascript=A604800,font/*=A604800,application/x-font-ttf=A604800
        }

        tuning{
            maxConnections               10000
            maxSSLConnections            10000
            connTimeout                  300
            maxKeepAliveReq              10000
            smartKeepAlive               0
            keepAliveTimeout             5
            sndBufSize                   0
            rcvBufSize                   0
            gzipStaticCompressLevel      6
            gzipMaxFileSize              10M
            eventDispatcher              best
            maxCachedFileSize            4096
            totalInMemCacheSize          20M
            maxMMapFileSize              256K
            totalMMapCacheSize           40M
            useSendfile                  1
            fileETag                     28
            SSLCryptoDevice              null
            maxReqURLLen                 32768
            maxReqHeaderSize             65536
            maxReqBodySize               2047M
            maxDynRespHeaderSize         32768
            maxDynRespSize               2047M
            enableGzipCompress           1
            enableBrCompress             4
            enableDynGzipCompress        1
            gzipCompressLevel            6
            brStaticCompressLevel        6
            compressibleTypes            default
            gzipAutoUpdateStatic         1
            gzipMinFileSize              300

            quicEnable                   1
            quicShmDir                   /dev/shm

        }

        accessDenyDir{
            dir                  /
            dir                  /etc/*
            dir                  /dev/*
            dir                  conf/*
            dir                  admin/conf/*
        }

        fileAccessControl{
            followSymbolLink                            1
            checkSymbolLink                             0
            requiredPermissionMask                      000
            restrictedPermissionMask                    000
        }

        perClientConnLimit{
            staticReqPerSec                          0
            dynReqPerSec                             0
            outBandwidth                             0
            inBandwidth                              0
            softLimit                                10000
            hardLimit                                10000
            gracePeriod                              15
            banPeriod                                300
        }

        CGIRLimit{
            maxCGIInstances                         20
            minUID                                  11
            minGID                                  10
            priority                                0
            CPUSoftLimit                            10
            CPUHardLimit                            50
            memSoftLimit                            2047M
            memHardLimit                            2047M
            procSoftLimit                           400
            procHardLimit                           450
        }

        accessControl{
    	allow                                   ALL
    	deny
        }

        extProcessor lsphp{
            type                            lsapi
            address                         uds://tmp/lshttpd/lsphp.sock
            maxConns                        10
            env                             PHP_LSAPI_CHILDREN=10
            env                             LSAPI_AVOID_FORK=200M
            initTimeout                     60
            retryTimeout                    0
            persistConn                     1
            pcKeepAliveTimeout
            respBuffer                      0
            autoStart                       1
            path                            fcgi-bin/lsphp
            backlog                         100
            instances                       1
            priority                        0
            memSoftLimit                    0
            memHardLimit                    0
            procSoftLimit                   1400
            procHardLimit                   1500
        }

        scriptHandler{
            add lsapi:lsphp  php
        }

        railsDefaults{
            binPath
            railsEnv                 1
            maxConns                 1
            env                      LSAPI_MAX_IDLE=60
            initTimeout              60
            retryTimeout             0
            pcKeepAliveTimeout       60
            respBuffer               0
            backlog                  50
            runOnStartUp             3
            extMaxIdleTime           300
            priority                 3
            memSoftLimit             0
            memHardLimit             0
            procSoftLimit            500
            procHardLimit            600
        }

        wsgiDefaults{
            binPath
            railsEnv                 1
            maxConns                 5
            env                      LSAPI_MAX_IDLE=60
            initTimeout              60
            retryTimeout             0
            pcKeepAliveTimeout       60
            respBuffer               0
            backlog                  50
            runOnStartUp             3
            extMaxIdleTime           300
            priority                 3
            memSoftLimit             0
            memHardLimit             0
            procSoftLimit            500
            procHardLimit            600
        }

        nodeDefaults{
            binPath
            railsEnv                 1
            maxConns                 5
            env                      LSAPI_MAX_IDLE=60
            initTimeout              60
            retryTimeout             0
            pcKeepAliveTimeout       60
            respBuffer               0
            backlog                  50
            runOnStartUp             3
            extMaxIdleTime           300
            priority                 3
            memSoftLimit             0
            memHardLimit             0
            procSoftLimit            500
            procHardLimit            600
        }

        virtualHost Example{
            vhRoot                   Example/
            allowSymbolLink          1
            enableScript             1
            restrained               1
            maxKeepAliveReq
            smartKeepAlive
            setUIDMode               0
            chrootMode               0
            configFile               conf/vhosts/Example/vhconf.conf
        }

        listener Default{
            address                  *:8088
            secure                   0
            map                      Example *
        }

        vhTemplate centralConfigLog{
            templateFile             conf/templates/ccl.conf
            listeners                Default
        }

        vhTemplate EasyRailsWithSuEXEC{
            templateFile             conf/templates/rails.conf
            listeners                Default
        }

        module cache {
            ls_enabled          1

            checkPrivateCache   1
            checkPublicCache    1
            maxCacheObjSize     10000000
            maxStaleAge         200
            qsCache             1
            reqCookieCache      1
            respCookieCache     1
            ignoreReqCacheCtrl  1
            ignoreRespCacheCtrl 0

            enableCache         0
            expireInSeconds     3600
            enablePrivateCache  0
            privateExpireInSeconds 3600

        }

        listener HTTP {
          address                 *:80
          secure                  0
        }

        listener HTTPS {
          address                 *:443
          secure                  1
          keyFile                 ${listenerKeyFile}
          certFile                ${listenerCertFile}
        }

        vhTemplate docker {
          templateFile            conf/templates/docker.conf
          listeners               HTTP, HTTPS
        ${dockerMembers}
          note                    docker

          member localhost {
            vhDomain              localhost, *
          }
        }
  '';

  containerServices = [
    "${litespeedName}.service"
    "${redisName}.service"
  ]
  ++ lib.concatMap
    (siteInfo: [
      siteInfo.mysqlService
      siteInfo.phpmyadminService
    ])
    siteList;

  litespeedVolumes = [
    "${adminConfDir}:/usr/local/lsws/admin/conf"
    "${sitesDir}:/var/www/vhosts"
    "${logsDir}:/usr/local/lsws/logs"
    "${httpdConfigFile}:/usr/local/lsws/conf/httpd_config.conf:ro"
    "${dockerTemplateFile}:/usr/local/lsws/conf/templates/docker.conf:ro"
  ]
  ++ lib.optionals cfg.hostAcme.enable [
    "/var/lib/acme:/etc/ssl/host-acme:ro"
  ];

  siteBootstrap = lib.concatMapStringsSep "\n\n"
    (
      siteInfo:
      let
        site = siteInfo.site;
        secretEnvFile = toString site.secretEnvFile;
        siteScheme = if cfg.hostAcme.enable then "https" else "http";
      in
      ''
        load_site_secret_env ${lib.escapeShellArg secretEnvFile}
        wait_for_mysql ${siteInfo.mysqlName} "$MYSQL_ROOT_PASSWORD"
        wait_for_redis

        if ! ${dockerBin} exec ${litespeedName} sh -c ${lib.escapeShellArg "test -f /var/www/vhosts/${site.domain}/html/wp-config.php"}; then
          ${dockerBin} exec \
            --env MYSQL_PASSWORD="$MYSQL_PASSWORD" \
            ${litespeedName} sh -c ${lib.escapeShellArg ''
              mkdir -p /var/www/vhosts/${site.domain}/html /var/www/vhosts/${site.domain}/logs

              if [ ! -f /var/www/vhosts/${site.domain}/html/wp-load.php ]; then
                wp core download --allow-root --path=/var/www/vhosts/${site.domain}/html
              fi

              wp config create \
                --allow-root \
                --path=/var/www/vhosts/${site.domain}/html \
                --dbname=${site.database.name} \
                --dbuser=${site.database.user} \
                --dbpass="$MYSQL_PASSWORD" \
                --dbhost=${siteInfo.mysqlName}
            ''}
        fi

        ${dockerBin} exec \
          --env MYSQL_PASSWORD="$MYSQL_PASSWORD" \
          ${litespeedName} sh -c ${lib.escapeShellArg ''
            wp config set DB_NAME ${site.database.name} --allow-root --path=/var/www/vhosts/${site.domain}/html --type=constant
            wp config set DB_USER ${site.database.user} --allow-root --path=/var/www/vhosts/${site.domain}/html --type=constant
            wp config set DB_PASSWORD "$MYSQL_PASSWORD" --allow-root --path=/var/www/vhosts/${site.domain}/html --type=constant
            wp config set DB_HOST ${siteInfo.mysqlName} --allow-root --path=/var/www/vhosts/${site.domain}/html --type=constant
            wp config set LITESPEED_CONF true --raw --allow-root --path=/var/www/vhosts/${site.domain}/html --type=constant
            wp config set LITESPEED_CONF__OBJECT true --raw --allow-root --path=/var/www/vhosts/${site.domain}/html --type=constant
            wp config set LITESPEED_CONF__OBJECT__KIND redis --allow-root --path=/var/www/vhosts/${site.domain}/html --type=constant
            wp config set LITESPEED_CONF__OBJECT__HOST ${redisName} --allow-root --path=/var/www/vhosts/${site.domain}/html --type=constant
            wp config set LITESPEED_CONF__OBJECT__PORT 6379 --raw --allow-root --path=/var/www/vhosts/${site.domain}/html --type=constant
            wp config set LITESPEED_CONF__OBJECT__DB_ID 0 --raw --allow-root --path=/var/www/vhosts/${site.domain}/html --type=constant
            wp config set LITESPEED_CONF__OBJECT__PERSISTENT true --raw --allow-root --path=/var/www/vhosts/${site.domain}/html --type=constant
            wp config set LITESPEED_CONF__OBJECT__ADMIN true --raw --allow-root --path=/var/www/vhosts/${site.domain}/html --type=constant
            wp config set LSOC_PREFIX ${siteInfo.name}: --allow-root --path=/var/www/vhosts/${site.domain}/html --type=constant
          ''}

        if ! ${dockerBin} exec ${litespeedName} sh -c ${lib.escapeShellArg "cd /var/www/vhosts/${site.domain}/html && wp core is-installed --allow-root >/dev/null 2>&1"}; then
          ${dockerBin} exec \
            --env WORDPRESS_ADMIN_PASSWORD="$WORDPRESS_ADMIN_PASSWORD" \
            ${litespeedName} sh -c ${lib.escapeShellArg ''
              wp core install \
                --allow-root \
                --path=/var/www/vhosts/${site.domain}/html \
                --url=${siteScheme}://${site.domain} \
                --title=${lib.escapeShellArg site.wordpress.siteTitle} \
                --admin_user=${lib.escapeShellArg site.wordpress.adminUser} \
                --admin_password="$WORDPRESS_ADMIN_PASSWORD" \
                --admin_email=${lib.escapeShellArg site.wordpress.adminEmail} \
                --skip-email
            ''}
        fi

        ${dockerBin} exec ${litespeedName} sh -c ${lib.escapeShellArg ''
          wp option update home ${siteScheme}://${site.domain} --allow-root --path=/var/www/vhosts/${site.domain}/html >/dev/null
          wp option update siteurl ${siteScheme}://${site.domain} --allow-root --path=/var/www/vhosts/${site.domain}/html >/dev/null
        ''}

        if ${dockerBin} exec ${litespeedName} sh -c ${lib.escapeShellArg "wp plugin is-installed litespeed-cache --allow-root --path=/var/www/vhosts/${site.domain}/html >/dev/null 2>&1"}; then
          ${dockerBin} exec ${litespeedName} sh -c ${lib.escapeShellArg ''
            wp plugin activate litespeed-cache --allow-root --path=/var/www/vhosts/${site.domain}/html >/dev/null
          ''}
        else
          ${dockerBin} exec ${litespeedName} sh -c ${lib.escapeShellArg ''
            wp plugin install litespeed-cache --activate --allow-root --path=/var/www/vhosts/${site.domain}/html >/dev/null
          ''}
        fi

        ${dockerBin} exec ${litespeedName} sh -c ${lib.escapeShellArg ''
          wp litespeed-option set object true --allow-root --path=/var/www/vhosts/${site.domain}/html >/dev/null
          wp litespeed-option set object-kind redis --allow-root --path=/var/www/vhosts/${site.domain}/html >/dev/null
          wp litespeed-option set object-host ${redisName} --allow-root --path=/var/www/vhosts/${site.domain}/html >/dev/null
          wp litespeed-option set object-port 6379 --allow-root --path=/var/www/vhosts/${site.domain}/html >/dev/null
          wp litespeed-option set object-db_id 0 --allow-root --path=/var/www/vhosts/${site.domain}/html >/dev/null
          wp litespeed-option set object-persistent true --allow-root --path=/var/www/vhosts/${site.domain}/html >/dev/null
          wp litespeed-option set object-admin true --allow-root --path=/var/www/vhosts/${site.domain}/html >/dev/null
        ''}

        ${dockerBin} exec ${litespeedName} sh -c ${lib.escapeShellArg ''
          chown -R nobody:nogroup /var/www/vhosts/${site.domain}
        ''}
      ''
    )
    siteList;

  bootstrapScript = pkgs.writeShellScript "wordpress-litespeed-bootstrap" ''
    set -euo pipefail

    load_site_secret_env() {
      local secret_env_file="$1"

      if [ ! -f "$secret_env_file" ]; then
        echo "Missing WordPress secret env file: $secret_env_file" >&2
        return 1
      fi

      unset MYSQL_ROOT_PASSWORD MYSQL_PASSWORD WORDPRESS_ADMIN_PASSWORD

      set -a
      . "$secret_env_file"
      set +a

      if [ -z ''${MYSQL_ROOT_PASSWORD:-} ] || [ -z ''${MYSQL_PASSWORD:-} ] || [ -z ''${WORDPRESS_ADMIN_PASSWORD:-} ]; then
        echo "WordPress secret env file is missing required variables: $secret_env_file" >&2
        return 1
      fi
    }

    wait_for_mysql() {
      local container_name="$1"
      local root_password="$2"
      local tries=90

      while [ "$tries" -gt 0 ]; do
        if ${dockerBin} exec "$container_name" env MYSQL_PWD="$root_password" mariadb -uroot -e 'SELECT 1' >/dev/null 2>&1; then
          return 0
        fi

        tries=$((tries - 1))
        sleep 2
      done

      return 1
    }

    wait_for_redis() {
      local tries=60

      while [ "$tries" -gt 0 ]; do
        if ${dockerBin} exec ${redisName} redis-cli ping >/dev/null 2>&1; then
          return 0
        fi

        tries=$((tries - 1))
        sleep 2
      done

      return 1
    }

    ${siteBootstrap}
  '';

  containers = {
    ${litespeedName} = {
      image = "litespeedtech/openlitespeed:${cfg.olsVersion}-${cfg.phpVersion}";
      autoStart = true;
      serviceName = litespeedName;
      environment = {
        TZ = cfg.timeZone;
        TimeZone = cfg.timeZone;
        OLS_VERSION = cfg.olsVersion;
        PHP_VERSION = cfg.phpVersion;
        PHPMYADMIN_VERSION = cfg.phpMyAdminVersion;
      };
      environmentFiles = cfg.environmentFiles;
      volumes = litespeedVolumes;
      ports = [
        "${cfg.bindAddress}:${toString cfg.httpPort}:80"
        "${cfg.bindAddress}:${toString cfg.httpsPort}:443"
        "${cfg.bindAddress}:${toString cfg.httpsPort}:443/udp"
        "${cfg.bindAddress}:${toString cfg.adminPort}:7080"
      ];
      networks = [ serverNetworkName ] ++ map (siteInfo: siteInfo.networkName) siteList;
      dependsOn = mysqlContainerNames ++ [ redisName ];
    };

    ${redisName} = {
      image = "${cfg.redisImage}:${cfg.redisTag}";
      autoStart = true;
      serviceName = redisName;
      cmd = [
        "redis-server"
        "--appendonly"
        "yes"
      ];
      volumes = [
        "${redisDataDir}:/data"
      ];
      networks = [ serverNetworkName ];
      extraOptions = [ "--log-driver=none" ];
    };
  }
  // lib.foldl' lib.recursiveUpdate { } (
    map
      (siteInfo: {
        ${siteInfo.mysqlName} = {
          image = "${cfg.mariadbImage}:${cfg.mariadbTag}";
          autoStart = true;
          serviceName = siteInfo.mysqlName;
          cmd = [ "--max-allowed-packet=512M" ];
          environment = {
            MYSQL_DATABASE = siteInfo.site.database.name;
            MYSQL_USER = siteInfo.site.database.user;
          };
          environmentFiles = cfg.environmentFiles ++ [ siteInfo.site.secretEnvFile ];
          volumes = [
            "${siteInfo.databaseDir}:/var/lib/mysql"
          ];
          networks = [ siteInfo.networkName ];
          extraOptions = [ "--log-driver=none" ];
        };

        ${siteInfo.phpmyadminName} = {
          image = "phpmyadmin/phpmyadmin:${cfg.phpMyAdminVersion}";
          autoStart = true;
          serviceName = siteInfo.phpmyadminName;
          environment = {
            PMA_HOST = siteInfo.mysqlName;
          };
          environmentFiles = cfg.environmentFiles;
          ports = [
            "${cfg.bindAddress}:${toString siteInfo.site.phpMyAdminPort}:80"
          ];
          networks = [ siteInfo.networkName ];
          dependsOn = [ siteInfo.mysqlName ];
        };
      })
      siteList
  );

  tmpfilesRules = [
    "d ${cfg.dataDir} 0755 root root -"
    "d ${cfg.dataDir}/bin 0755 root root -"
    "d ${cfg.dataDir}/lsws 0755 root root -"
    "d ${adminConfDir} 0755 root root -"
    "d ${cfg.dataDir}/redis 0755 root root -"
    "d ${redisDataDir} 0755 root root -"
    "d ${sitesDir} 0755 root root -"
    "d ${sitesDir}/localhost 0755 root root -"
    "d ${sitesDir}/localhost/html 0755 root root -"
    "d ${sitesDir}/localhost/logs 0755 root root -"
    "d ${logsDir} 0755 root root -"
    "d ${cfg.dataDir}/data 0755 root root -"
  ]
  ++ lib.concatMap
    (siteInfo: [
      "d ${siteInfo.databaseDir} 0755 root root -"
      "d ${siteInfo.siteRoot} 0755 root root -"
      "d ${siteInfo.siteHtmlDir} 0755 root root -"
      "d ${siteInfo.siteLogsDir} 0755 root root -"
    ])
    siteList;

  acmeCerts = lib.listToAttrs (
    map
      (
        siteInfo:
        lib.nameValuePair siteInfo.site.domain {
          dnsProvider = cfg.hostAcme.dnsProvider;
          environmentFile = cfg.hostAcme.environmentFile;
          extraDomainNames = siteInfo.extraDomainNames;
          reloadServices = [ "${litespeedName}.service" ];
        }
      )
      siteList
  );
in
{
  imports = [
    (configLib.relativeToRoot "modules/nixos/services/containers")
  ];

  options.my.wordpressLiteSpeed = {
    enable = lib.mkEnableOption "OpenLiteSpeed multi-site WordPress OCI stack";

    dataDir = lib.mkOption {
      type = lib.types.path;
      default = "${config.my.services.baseDataDir}/wordpress-litespeed";
    };

    networkName = lib.mkOption {
      type = lib.types.str;
      default = "wordpress_litespeed_server";
    };

    bindAddress = lib.mkOption {
      type = lib.types.str;
      default = "0.0.0.0";
    };

    acmeEmail = lib.mkOption {
      type = lib.types.str;
    };

    httpPort = lib.mkOption {
      type = lib.types.int;
      default = 80;
    };

    httpsPort = lib.mkOption {
      type = lib.types.int;
      default = 443;
    };

    adminPort = lib.mkOption {
      type = lib.types.int;
      default = 7080;
    };

    timeZone = lib.mkOption {
      type = lib.types.str;
      default = "America/New_York";
    };

    olsVersion = lib.mkOption {
      type = lib.types.str;
      default = "1.8.5";
    };

    phpVersion = lib.mkOption {
      type = lib.types.str;
      default = "lsphp85";
    };

    phpMyAdminVersion = lib.mkOption {
      type = lib.types.str;
      default = "5.2.3";
    };

    redisImage = lib.mkOption {
      type = lib.types.str;
      default = "public.ecr.aws/docker/library/redis";
    };

    redisTag = lib.mkOption {
      type = lib.types.str;
      default = "7-alpine";
    };

    mariadbTag = lib.mkOption {
      type = lib.types.str;
      default = "11.4";
    };

    mariadbImage = lib.mkOption {
      type = lib.types.str;
      default = "public.ecr.aws/docker/library/mariadb";
    };

    hostAcme = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = false;
      };

      dnsProvider = lib.mkOption {
        type = lib.types.str;
        default = "cloudflare";
      };

      environmentFile = lib.mkOption {
        type = lib.types.nullOr lib.types.path;
        default = null;
      };
    };

    sites = lib.mkOption {
      type = lib.types.attrsOf (
        lib.types.submodule (
          { name, ... }:
          {
            options = {
              domain = lib.mkOption {
                type = lib.types.str;
              };

              wwwAlias = lib.mkOption {
                type = lib.types.bool;
                default = true;
              };

              phpMyAdminPort = lib.mkOption {
                type = lib.types.int;
              };

              secretEnvFile = lib.mkOption {
                type = lib.types.path;
                description = ''
                  Path to a sops-nix environment file containing MYSQL_ROOT_PASSWORD,
                  MYSQL_PASSWORD, and WORDPRESS_ADMIN_PASSWORD.
                '';
              };

              wordpress = {
                siteTitle = lib.mkOption {
                  type = lib.types.str;
                  default = "WordPress";
                };

                adminUser = lib.mkOption {
                  type = lib.types.str;
                  default = "admin";
                };

                adminEmail = lib.mkOption {
                  type = lib.types.str;
                  default = "admin@example.com";
                };
              };

              database = {
                name = lib.mkOption {
                  type = lib.types.str;
                  default = name;
                };

                user = lib.mkOption {
                  type = lib.types.str;
                  default = name;
                };
              };
            };
          }
        )
      );
      default = { };
    };

    environmentFiles = lib.mkOption {
      type = lib.types.listOf lib.types.path;
      default = [ ];
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = siteList != [ ];
        message = "my.wordpressLiteSpeed.sites must define at least one site.";
      }
      {
        assertion = (!cfg.hostAcme.enable) || (cfg.hostAcme.environmentFile != null);
        message = "my.wordpressLiteSpeed.hostAcme.environmentFile must be set when hostAcme is enabled.";
      }
      {
        assertion = lib.length (lib.unique siteDomains) == lib.length siteDomains;
        message = "my.wordpressLiteSpeed.sites domains must be unique.";
      }
      {
        assertion = lib.length (lib.unique phpMyAdminPorts) == lib.length phpMyAdminPorts;
        message = "my.wordpressLiteSpeed.sites phpMyAdminPort values must be unique.";
      }
    ];

    security.acme = lib.mkIf cfg.hostAcme.enable {
      acceptTerms = true;
      defaults.email = cfg.acmeEmail;
      certs = acmeCerts;
    };

    systemd.services.${litespeedName} = lib.mkIf cfg.hostAcme.enable {
      after = acmeServices;
      requires = acmeServices;
    };

    systemd.tmpfiles.rules = tmpfilesRules;

    systemd.services.wordpress-litespeed-network = {
      description = "Create WordPress LiteSpeed Docker networks";
      after = [ containerRuntimeService ];
      requires = [ containerRuntimeService ];
      before = containerServices;
      requiredBy = containerServices;
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };
      script = ''
        ${dockerBin} network inspect ${serverNetworkName} >/dev/null 2>&1 || ${dockerBin} network create ${serverNetworkName} --subnet ${configLib.networking.docker.getSubnet serverNetworkName}
        ${lib.concatMapStringsSep "\n" (
          siteInfo:
          "${dockerBin} network inspect ${siteInfo.networkName} >/dev/null 2>&1 || ${dockerBin} network create ${siteInfo.networkName} --subnet ${configLib.networking.docker.getSubnet siteInfo.networkName}"
        ) siteList}
      '';
    };

    virtualisation.oci-containers.containers = containers;

    systemd.services.wordpress-litespeed-bootstrap = {
      description = "Bootstrap LiteSpeed WordPress sites";
      wantedBy = [ "multi-user.target" ];
      after = [
        "network-online.target"
        "${litespeedName}.service"
        "${redisName}.service"
        "wordpress-litespeed-network.service"
      ]
      ++ mysqlServices
      ++ lib.optionals cfg.hostAcme.enable acmeServices;
      wants = [ "network-online.target" ];
      requires = [
        "${litespeedName}.service"
        "${redisName}.service"
        "wordpress-litespeed-network.service"
      ]
      ++ mysqlServices
      ++ lib.optionals cfg.hostAcme.enable acmeServices;
      path = [ pkgs.coreutils ];
      serviceConfig.Type = "oneshot";
      script = ''
        ${bootstrapScript}
      '';
    };
  };
}
