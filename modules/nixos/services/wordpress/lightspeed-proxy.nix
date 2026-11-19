{ config, configLib, lib, pkgs, ... }:
let
  cfg = config.my.wordpressLiteSpeedProxy;
  docker = config.virtualisation.oci-containers.backend;
  dockerBin = "${pkgs.${docker}}/bin/${docker}";
  uploadLimit = "${toString cfg.uploadLimitMB}M";
  uploadLimitBytes = cfg.uploadLimitMB * 1024 * 1024;

  containerRuntimeService = "${docker}.service";
  mysqlStopTimeoutSeconds = 120;

  redisName = "wordpress-litespeed-proxy-redis";
  sharedNetworkName = cfg.networkName;
  sitesDir = "${cfg.dataDir}/sites";
  redisDataDir = "${cfg.dataDir}/redis/data";
  smtpPasswordMountPath = "/run/secrets/wordpress-smtp-password";

  smtpMuPluginFile = pkgs.writeText "wordpress-smtp-mu-plugin.php" ''
    <?php
    /**
     * Plugin Name: RIDALY SMTP
     */

    if (!defined('ABSPATH')) {
        exit;
    }

    add_action('phpmailer_init', static function ($phpmailer) {
        if (!defined('WORDPRESS_SMTP_HOST') || !defined('WORDPRESS_SMTP_USER') || !defined('WORDPRESS_SMTP_FROM') || !defined('WORDPRESS_SMTP_PASSWORD_FILE')) {
            return;
        }

        $password = @file_get_contents(WORDPRESS_SMTP_PASSWORD_FILE);
        if ($password === false) {
            error_log('ISS SMTP password file missing: ' . WORDPRESS_SMTP_PASSWORD_FILE);
            return;
        }

        $phpmailer->isSMTP();
        $phpmailer->Host = WORDPRESS_SMTP_HOST;
        $phpmailer->Port = defined('WORDPRESS_SMTP_PORT') ? (int) WORDPRESS_SMTP_PORT : 587;
        $phpmailer->SMTPAuth = true;
        $phpmailer->Username = WORDPRESS_SMTP_USER;
        $phpmailer->Password = trim($password);

        if (defined('WORDPRESS_SMTP_SECURE')) {
            if (WORDPRESS_SMTP_SECURE === 'tls') {
                $phpmailer->SMTPSecure = \PHPMailer\PHPMailer\PHPMailer::ENCRYPTION_STARTTLS;
            } elseif (WORDPRESS_SMTP_SECURE === 'ssl') {
                $phpmailer->SMTPSecure = \PHPMailer\PHPMailer\PHPMailer::ENCRYPTION_SMTPS;
            } else {
                $phpmailer->SMTPSecure = "";
            }
        }

        $fromName = defined('WORDPRESS_SMTP_FROM_NAME') ? WORDPRESS_SMTP_FROM_NAME : get_bloginfo('name');
        $phpmailer->setFrom(WORDPRESS_SMTP_FROM, $fromName, false);
        $phpmailer->Sender = WORDPRESS_SMTP_FROM;

        if (defined('WORDPRESS_SMTP_REPLY_TO') && strlen(WORDPRESS_SMTP_REPLY_TO) > 0) {
            $phpmailer->clearReplyTos();
            $phpmailer->addReplyTo(WORDPRESS_SMTP_REPLY_TO);
        }
    });

    add_action('wp_mail_failed', static function ($error) {
        if (!($error instanceof \WP_Error)) {
            error_log('ISS SMTP wp_mail_failed: unknown error');
            return;
        }

        error_log('ISS SMTP wp_mail_failed: ' . implode('; ', $error->get_error_messages()));

        $data = $error->get_error_data();
        if (is_array($data) && isset($data['phpmailer_exception_code'])) {
            error_log('ISS SMTP phpmailer_exception_code: ' . $data['phpmailer_exception_code']);
        }
    });
  '';

  uploadLimitMuPluginFile =
    pkgs.writeText "wordpress-upload-limit-mu-plugin.php" ''
      <?php
      /**
       * Plugin Name: RIDALY Upload Limit
       */

      if (!defined('ABSPATH')) {
          exit;
      }

      add_filter('upload_size_limit', static function () {
          return ${toString uploadLimitBytes};
      });
    '';

  mkDockerTemplateFile = siteInfo:
    pkgs.writeText "wordpress-litespeed-${siteInfo.name}-docker.conf" ''
      allowSymbolLink           1
      enableScript              1
      restrained                1
      setUIDMode                2
      vhRoot                    /var/www/vhosts/$VH_NAME/
      configFile                $SERVER_ROOT/conf/vhosts/$VH_NAME/vhconf.conf

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
            RewriteFile         .htaccess
          }
        }

        rewrite  {
          enable                1
          autoLoadHtaccess      1
          logLevel              0
          rules                 <<<END_rules
          RewriteCond %{REQUEST_FILENAME} !-f
          RewriteCond %{REQUEST_FILENAME} !-d
          RewriteRule ^(.*)$ /index.php [L,QSA]
          END_rules
        }
      }
    '';

  mkHttpdConfigFile = siteInfo:
    pkgs.writeText "wordpress-litespeed-${siteInfo.name}-httpd_config.conf" ''
      #
      # PLAIN TEXT CONFIGURATION FILE
      #

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
        logLevel                       DEBUG
        debugLevel                     0
        rollingSize                    10M
        enableStderrLog                1
      }

      accessLog logs/access.log {
        rollingSize                    10M
        keepDays                       30
        compressArchive                0
        logReferer                     1
        logUserAgent                   1
      }

      expires {
        enableExpires                  1
        expiresByType                  image/*=A604800,text/css=A604800,application/x-javascript=A604800,application/javascript=A604800,font/*=A604800,application/x-font-ttf=A604800
      }

      tuning{
        maxConnections                 10000
        maxSSLConnections              10000
        connTimeout                    300
        maxKeepAliveReq                10000
        smartKeepAlive                 0
        keepAliveTimeout               5
        sndBufSize                     0
        rcvBufSize                     0
        gzipStaticCompressLevel        6
        gzipMaxFileSize                10M
        eventDispatcher                best
        maxCachedFileSize              4096
        totalInMemCacheSize            20M
        maxMMapFileSize                256K
        totalMMapCacheSize             40M
        useSendfile                    1
        fileETag                       28
        SSLCryptoDevice                null
        maxReqURLLen                   32768
        maxReqHeaderSize               65536
        maxReqBodySize                 ${uploadLimit}
        maxDynRespHeaderSize           32768
        maxDynRespSize                 2047M
        enableGzipCompress             1
        enableBrCompress               4
        enableDynGzipCompress          1
        gzipCompressLevel              6
        brStaticCompressLevel          6
        compressibleTypes              default
        gzipAutoUpdateStatic           1
        gzipMinFileSize                300
      }

      accessDenyDir{
        dir                            /
        dir                            /etc/*
        dir                            /dev/*
        dir                            conf/*
        dir                            admin/conf/*
      }

      fileAccessControl{
        followSymbolLink               1
        checkSymbolLink                0
        requiredPermissionMask         000
        restrictedPermissionMask       000
      }

      perClientConnLimit{
        staticReqPerSec                0
        dynReqPerSec                   0
        outBandwidth                   0
        inBandwidth                    0
        softLimit                      10000
        hardLimit                      10000
        gracePeriod                    15
        banPeriod                      300
      }

      CGIRLimit{
        maxCGIInstances                20
        minUID                         11
        minGID                         10
        priority                       0
        CPUSoftLimit                   10
        CPUHardLimit                   50
        memSoftLimit                   2047M
        memHardLimit                   2047M
        procSoftLimit                  400
        procHardLimit                  450
      }

      accessControl{
        allow                          ALL
        deny
      }

      extProcessor lsphp{
        type                           lsapi
        address                        uds://tmp/lshttpd/lsphp.sock
        maxConns                       10
        env                            PHP_LSAPI_CHILDREN=10
        env                            LSAPI_AVOID_FORK=200M
        initTimeout                    60
        retryTimeout                   0
        persistConn                    1
        pcKeepAliveTimeout
        respBuffer                     0
        autoStart                      1
        path                           fcgi-bin/lsphp
        backlog                        100
        instances                      1
        priority                       0
        memSoftLimit                   0
        memHardLimit                   0
        procSoftLimit                  1400
        procHardLimit                  1500
      }

      scriptHandler{
        add lsapi:lsphp                php
      }

      railsDefaults{
        binPath
        railsEnv                       1
        maxConns                       1
        env                            LSAPI_MAX_IDLE=60
        initTimeout                    60
        retryTimeout                   0
        pcKeepAliveTimeout             60
        respBuffer                     0
        backlog                        50
        runOnStartUp                   3
        extMaxIdleTime                 300
        priority                       3
        memSoftLimit                   0
        memHardLimit                   0
        procSoftLimit                  500
        procHardLimit                  600
      }

      wsgiDefaults{
        binPath
        railsEnv                       1
        maxConns                       5
        env                            LSAPI_MAX_IDLE=60
        initTimeout                    60
        retryTimeout                   0
        pcKeepAliveTimeout             60
        respBuffer                     0
        backlog                        50
        runOnStartUp                   3
        extMaxIdleTime                 300
        priority                       3
        memSoftLimit                   0
        memHardLimit                   0
        procSoftLimit                  500
        procHardLimit                  600
      }

      nodeDefaults{
        binPath
        railsEnv                       1
        maxConns                       5
        env                            LSAPI_MAX_IDLE=60
        initTimeout                    60
        retryTimeout                   0
        pcKeepAliveTimeout             60
        respBuffer                     0
        backlog                        50
        runOnStartUp                   3
        extMaxIdleTime                 300
        priority                       3
        memSoftLimit                   0
        memHardLimit                   0
        procSoftLimit                  500
        procHardLimit                  600
      }

      virtualHost Example{
        vhRoot                         Example/
        allowSymbolLink                1
        enableScript                   1
        restrained                     1
        maxKeepAliveReq
        smartKeepAlive
        setUIDMode                     0
        chrootMode                     0
        configFile                     conf/vhosts/Example/vhconf.conf
      }

      listener Default{
        address                        *:8088
        secure                         0
        map                            Example *
      }

      vhTemplate centralConfigLog{
        templateFile                   conf/templates/ccl.conf
        listeners                      Default
      }

      vhTemplate EasyRailsWithSuEXEC{
        templateFile                   conf/templates/rails.conf
        listeners                      Default
      }

      module cache {
        ls_enabled                     1

        checkPrivateCache              1
        checkPublicCache               1
        maxCacheObjSize                10000000
        maxStaleAge                    200
        qsCache                        1
        reqCookieCache                 1
        respCookieCache                1
        ignoreReqCacheCtrl             1
        ignoreRespCacheCtrl            0

        enableCache                    0
        expireInSeconds                3600
        enablePrivateCache             0
        privateExpireInSeconds         3600
      }

      listener HTTP {
        address                        *:80
        secure                         0
      }

      vhTemplate docker {
        templateFile                   conf/templates/docker.conf
        listeners                      HTTP

        member ${siteInfo.site.domain} {
          vhDomain                     ${siteInfo.vhDomains}
        }

        note                           docker
      }
    '';

  siteInfos = lib.mapAttrs (name: site:
    let
      mysqlName = "wordpress-ls-${name}-mysql";
      phpmyadminName = "wordpress-ls-${name}-phpmyadmin";
      litespeedName = "wordpress-ls-${name}";
      networkName = "wordpress_litespeed_proxy_${name}";
      databaseDir = if builtins.length (lib.attrNames cfg.sites) == 1 then
        "${cfg.dataDir}/data/db"
      else
        "${cfg.dataDir}/data/${name}/db";
      siteRoot = "${sitesDir}/${site.domain}";
      siteHtmlDir = "${siteRoot}/html";
      siteLogsDir = "${siteRoot}/logs";
      backupDir = "${cfg.dataDir}/backups/${name}";
      litespeedDir = "${cfg.dataDir}/lsws/${name}";
      adminConfDir = "${litespeedDir}/admin-conf";
      litespeedConfigDir = "${litespeedDir}/config";
      litespeedLogsDir = "${litespeedDir}/logs";
      smtpUser = site.mail.email;
      smtpPasswordFile = site.mail.smtp.passwordFile;
      extraDomainNames =
        lib.optionals (site.wwwAlias && !(lib.hasPrefix "www." site.domain))
        [ "www.${site.domain}" ];
      vhDomains =
        lib.concatStringsSep "," ([ site.domain ] ++ extraDomainNames);
    in {
      inherit name site mysqlName phpmyadminName litespeedName networkName
        databaseDir siteRoot siteHtmlDir siteLogsDir backupDir litespeedDir
        adminConfDir litespeedConfigDir litespeedLogsDir extraDomainNames
        vhDomains smtpUser smtpPasswordFile;

      mysqlService = "${mysqlName}.service";
      phpmyadminService = "${phpmyadminName}.service";
      litespeedService = "${litespeedName}.service";
      acmeService = "acme-${site.domain}.service";
      dockerTemplateFile =
        mkDockerTemplateFile { inherit name site vhDomains; };
      httpdConfigFile = mkHttpdConfigFile { inherit name site vhDomains; };
      dockerTemplatePath = "${litespeedConfigDir}/docker.conf";
      httpdConfigPath = "${litespeedConfigDir}/httpd_config.conf";
      smtpPasswordMountPath = smtpPasswordMountPath;
    }) cfg.sites;

  siteList = lib.sort (a: b: a.name < b.name) (lib.attrValues siteInfos);
  backupSiteList = lib.filter (siteInfo: siteInfo.site.backup.enable) siteList;
  containerServices = [ "${redisName}.service" ] ++ lib.concatMap (siteInfo: [
    siteInfo.litespeedService
    siteInfo.mysqlService
    siteInfo.phpmyadminService
  ]) siteList;
  mysqlServices = map (siteInfo: siteInfo.mysqlService) siteList;
  litespeedServices = map (siteInfo: siteInfo.litespeedService) siteList;
  siteDomains = map (siteInfo: siteInfo.site.domain) siteList;
  phpMyAdminPorts = map (siteInfo: siteInfo.site.phpMyAdminPort) siteList;
  adminPorts = map (siteInfo: siteInfo.site.adminPort) siteList;
  proxyPorts = map (siteInfo: siteInfo.site.proxyPort) siteList;

  wordpressBackupJobs = lib.listToAttrs (map (siteInfo:
    lib.nameValuePair "wordpress-${siteInfo.name}" {
      enable = true;
      user = "root";
      extraConfig = {
        paths = [ siteInfo.siteHtmlDir siteInfo.backupDir ];
        backupPrepareCommand = ''
          set -euo pipefail
          umask 077

          container_name=${lib.escapeShellArg siteInfo.mysqlName}
          dump_file=${lib.escapeShellArg "${siteInfo.backupDir}/database.sql"}
          tmp_file="$dump_file.tmp"
          tries=90

          mkdir -p ${lib.escapeShellArg siteInfo.backupDir}
          trap 'rm -f "$tmp_file"' EXIT

          until ${dockerBin} exec "$container_name" sh -c 'export MYSQL_PWD="$MYSQL_ROOT_PASSWORD"; mariadb -uroot -e "SELECT 1"' >/dev/null 2>&1; do
            tries=$((tries - 1))
            if [ "$tries" -eq 0 ]; then
              echo "MariaDB did not become ready: $container_name" >&2
              exit 1
            fi
            sleep 2
          done

          ${dockerBin} exec "$container_name" sh -c 'export MYSQL_PWD="$MYSQL_ROOT_PASSWORD"; exec mariadb-dump -uroot --single-transaction --quick --routines --events --triggers --hex-blob --add-drop-database --databases "$MYSQL_DATABASE"' > "$tmp_file"
          test -s "$tmp_file"
          mv "$tmp_file" "$dump_file"
          trap - EXIT
        '';
        timerConfig = {
          OnCalendar = "daily";
          RandomizedDelaySec = "1h";
          Persistent = true;
        };
        pruneOpts = [ "--keep-daily 7" "--keep-monthly 6" ];
        runCheck = true;
      };
    }) backupSiteList);

  wordpressRestoreScripts = map (siteInfo:
    pkgs.writeShellApplication {
      name = "wordpress-${siteInfo.name}-restore";
      runtimeInputs = [ pkgs.coreutils pkgs.rsync pkgs.systemd ];
      text = ''
        if [ "$(id -u)" -ne 0 ]; then
          echo "Run this restore command as root." >&2
          exit 1
        fi

        snapshot="''${1:-latest}"
        restore_dir=$(mktemp -d /var/tmp/wordpress-${siteInfo.name}-restore.XXXXXX)
        timer_stopped=false
        wordpress_stopped=false

        cleanup() {
          status=$?
          rm -rf "$restore_dir"
          if [ "$wordpress_stopped" = true ]; then
            systemctl start ${siteInfo.litespeedService} || true
          fi
          if [ "$timer_stopped" = true ]; then
            systemctl start restic-backups-wordpress-${siteInfo.name}.timer || true
          fi
          exit "$status"
        }
        trap cleanup EXIT

        if systemctl is-active --quiet restic-backups-wordpress-${siteInfo.name}.timer; then
          systemctl stop restic-backups-wordpress-${siteInfo.name}.timer
          timer_stopped=true
        fi

        if systemctl is-active --quiet restic-backups-wordpress-${siteInfo.name}.service; then
          echo "The wordpress-${siteInfo.name} backup is currently running." >&2
          exit 1
        fi

        restic-wordpress-${siteInfo.name} restore "$snapshot" --target "$restore_dir"

        restored_html="$restore_dir${siteInfo.siteHtmlDir}"
        database_dump="$restore_dir${siteInfo.backupDir}/database.sql"
        test -d "$restored_html"
        test -s "$database_dump"

        systemctl stop ${siteInfo.litespeedService}
        wordpress_stopped=true

        rsync --archive --delete "$restored_html/" ${lib.escapeShellArg "${siteInfo.siteHtmlDir}/"}
        ${dockerBin} exec -i ${siteInfo.mysqlName} sh -c 'export MYSQL_PWD="$MYSQL_ROOT_PASSWORD"; exec mariadb -uroot' < "$database_dump"

        systemctl start ${siteInfo.litespeedService}
        wordpress_stopped=false

        if [ "$timer_stopped" = true ]; then
          systemctl start restic-backups-wordpress-${siteInfo.name}.timer
          timer_stopped=false
        fi

        rm -rf "$restore_dir"
        trap - EXIT
        echo "Restored wordpress-${siteInfo.name} from snapshot $snapshot."
      '';
    }) backupSiteList;

  wordpressBackupSystemdServices = lib.listToAttrs (map (siteInfo:
    lib.nameValuePair "restic-backups-wordpress-${siteInfo.name}" {
      after = [ containerRuntimeService siteInfo.mysqlService ];
      requires = [ containerRuntimeService siteInfo.mysqlService ];
    }) backupSiteList);

  siteBootstrap = lib.concatMapStringsSep "\n\n" (siteInfo:
    let
      site = siteInfo.site;
      secretEnvFile = toString site.secretEnvFile;
      siteScheme = if cfg.hostAcme.enable then "https" else "http";
    in ''
      load_site_secret_env ${lib.escapeShellArg secretEnvFile}
      wait_for_mysql ${siteInfo.mysqlName} "$MYSQL_ROOT_PASSWORD"
      wait_for_redis
      wait_for_container ${siteInfo.litespeedName}

      if ! ${dockerBin} exec ${siteInfo.litespeedName} sh -c ${
        lib.escapeShellArg
        "test -f /var/www/vhosts/${site.domain}/html/wp-config.php"
      }; then
        ${dockerBin} exec \
          --env MYSQL_PASSWORD="$MYSQL_PASSWORD" \
          ${siteInfo.litespeedName} sh -c ${
            lib.escapeShellArg ''
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
                --dbhost=${siteInfo.mysqlName} \
                --quiet >/dev/null
            ''
          }
      fi

      ${dockerBin} exec \
        --env MYSQL_PASSWORD="$MYSQL_PASSWORD" \
        ${siteInfo.litespeedName} sh -c ${
          lib.escapeShellArg ''
                        wp config set DB_NAME ${site.database.name} --allow-root --path=/var/www/vhosts/${site.domain}/html --type=constant
                        wp config set DB_USER ${site.database.user} --allow-root --path=/var/www/vhosts/${site.domain}/html --type=constant
                        wp config set DB_PASSWORD "$MYSQL_PASSWORD" --allow-root --path=/var/www/vhosts/${site.domain}/html --type=constant --quiet >/dev/null
                         wp config set DB_HOST ${siteInfo.mysqlName} --allow-root --path=/var/www/vhosts/${site.domain}/html --type=constant
                         wp config set WP_HOME ${siteScheme}://${site.domain} --allow-root --path=/var/www/vhosts/${site.domain}/html --type=constant
                         wp config set WP_SITEURL ${siteScheme}://${site.domain} --allow-root --path=/var/www/vhosts/${site.domain}/html --type=constant
                          wp config set WORDPRESS_SMTP_HOST ${
                            lib.escapeShellArg site.mail.smtp.host
                          } --allow-root --path=/var/www/vhosts/${site.domain}/html --type=constant >/dev/null
                          wp config set WORDPRESS_SMTP_PORT ${
                            toString site.mail.smtp.port
                          } --raw --allow-root --path=/var/www/vhosts/${site.domain}/html --type=constant >/dev/null
                          wp config set WORDPRESS_SMTP_SECURE ${
                            lib.escapeShellArg site.mail.smtp.secure
                          } --allow-root --path=/var/www/vhosts/${site.domain}/html --type=constant >/dev/null
                         wp config set WORDPRESS_SMTP_USER ${
                           lib.escapeShellArg siteInfo.smtpUser
                         } --allow-root --path=/var/www/vhosts/${site.domain}/html --type=constant >/dev/null
                         wp config set WORDPRESS_SMTP_FROM ${
                           lib.escapeShellArg siteInfo.smtpUser
                         } --allow-root --path=/var/www/vhosts/${site.domain}/html --type=constant >/dev/null
                          wp config set WORDPRESS_SMTP_FROM_NAME ${
                            lib.escapeShellArg site.wordpress.siteTitle
                          } --allow-root --path=/var/www/vhosts/${site.domain}/html --type=constant >/dev/null
                          ${
                            if site.mail.replyTo == null then
                              "wp config delete WORDPRESS_SMTP_REPLY_TO --allow-root --path=/var/www/vhosts/${site.domain}/html --type=constant >/dev/null 2>&1 || true"
                            else
                              "wp config set WORDPRESS_SMTP_REPLY_TO ${
                                lib.escapeShellArg site.mail.replyTo
                              } --allow-root --path=/var/www/vhosts/${site.domain}/html --type=constant >/dev/null"
                          }
                          wp config set WORDPRESS_SMTP_PASSWORD_FILE ${
                            lib.escapeShellArg siteInfo.smtpPasswordMountPath
                          } --allow-root --path=/var/www/vhosts/${site.domain}/html --type=constant >/dev/null
                         ${
                           lib.optionalString cfg.hostAcme.enable
                           "wp config set FORCE_SSL_ADMIN true --raw --allow-root --path=/var/www/vhosts/${site.domain}/html --type=constant"
                         }
                        config_path=/var/www/vhosts/${site.domain}/html/wp-config.php
                        if ! grep -q "HTTP_X_FORWARDED_PROTO" "$config_path"; then
                          sed -i "/require_once/i\\
            if (isset(\$_SERVER['HTTP_X_FORWARDED_PROTO']) \&\& \$_SERVER['HTTP_X_FORWARDED_PROTO'] === 'https') {\\
                \$_SERVER['HTTPS'] = 'on';\\
            }\\
            if (isset(\$_SERVER['HTTP_X_FORWARDED_HOST'])) {\\
                \$_SERVER['HTTP_HOST'] = \$_SERVER['HTTP_X_FORWARDED_HOST'];\\
            }\\
            " "$config_path"
                        fi
          ''
        }

      if ! ${dockerBin} exec ${siteInfo.litespeedName} sh -c ${
        lib.escapeShellArg
        "cd /var/www/vhosts/${site.domain}/html && wp core is-installed --allow-root >/dev/null 2>&1"
      }; then
        ${dockerBin} exec \
          --env WORDPRESS_ADMIN_PASSWORD="$WORDPRESS_ADMIN_PASSWORD" \
          ${siteInfo.litespeedName} sh -c ${
            lib.escapeShellArg ''
              wp core install \
                --allow-root \
                --path=/var/www/vhosts/${site.domain}/html \
                --url=${siteScheme}://${site.domain} \
                --title=${lib.escapeShellArg site.wordpress.siteTitle} \
                --admin_user=${lib.escapeShellArg site.wordpress.adminUser} \
                --admin_password="$WORDPRESS_ADMIN_PASSWORD" \
                --admin_email=${lib.escapeShellArg site.wordpress.adminEmail} \
                --skip-email \
                --quiet >/dev/null
            ''
          }
      fi

      ${dockerBin} exec ${siteInfo.litespeedName} sh -c ${
        lib.escapeShellArg ''
          wp option update home ${siteScheme}://${site.domain} --allow-root --path=/var/www/vhosts/${site.domain}/html >/dev/null
          wp option update siteurl ${siteScheme}://${site.domain} --allow-root --path=/var/www/vhosts/${site.domain}/html >/dev/null
          wp rewrite flush --hard --allow-root --path=/var/www/vhosts/${site.domain}/html >/dev/null
        ''
      }

      if ${dockerBin} exec ${siteInfo.litespeedName} sh -c ${
        lib.escapeShellArg
        "wp plugin is-installed litespeed-cache --allow-root --path=/var/www/vhosts/${site.domain}/html >/dev/null 2>&1"
      }; then
        ${dockerBin} exec ${siteInfo.litespeedName} sh -c ${
          lib.escapeShellArg ''
            wp plugin activate litespeed-cache --allow-root --path=/var/www/vhosts/${site.domain}/html >/dev/null
          ''
        }
      else
        ${dockerBin} exec ${siteInfo.litespeedName} sh -c ${
          lib.escapeShellArg ''
            wp plugin install litespeed-cache --activate --allow-root --path=/var/www/vhosts/${site.domain}/html >/dev/null
          ''
        }
      fi

      ${dockerBin} exec ${siteInfo.litespeedName} sh -c ${
        lib.escapeShellArg ''
          wp config set LITESPEED_CONF true --raw --allow-root --path=/var/www/vhosts/${site.domain}/html --type=constant >/dev/null
          wp config set LITESPEED_CONF__OBJECT true --raw --allow-root --path=/var/www/vhosts/${site.domain}/html --type=constant >/dev/null
          wp config set LITESPEED_CONF__OBJECT__KIND redis --allow-root --path=/var/www/vhosts/${site.domain}/html --type=constant >/dev/null
          wp config set LITESPEED_CONF__OBJECT__HOST ${redisName} --allow-root --path=/var/www/vhosts/${site.domain}/html --type=constant >/dev/null
          wp config set LITESPEED_CONF__OBJECT__PORT 6379 --raw --allow-root --path=/var/www/vhosts/${site.domain}/html --type=constant >/dev/null
          wp config set LITESPEED_CONF__OBJECT__DB_ID 0 --raw --allow-root --path=/var/www/vhosts/${site.domain}/html --type=constant >/dev/null
          wp config set LITESPEED_CONF__OBJECT__PERSISTENT true --raw --allow-root --path=/var/www/vhosts/${site.domain}/html --type=constant >/dev/null
          wp config set LITESPEED_CONF__OBJECT__ADMIN true --raw --allow-root --path=/var/www/vhosts/${site.domain}/html --type=constant >/dev/null
          wp config set LSOC_PREFIX ${siteInfo.name}: --allow-root --path=/var/www/vhosts/${site.domain}/html --type=constant >/dev/null
          wp litespeed-option set object true --allow-root --path=/var/www/vhosts/${site.domain}/html >/dev/null
          wp litespeed-option set object-kind redis --allow-root --path=/var/www/vhosts/${site.domain}/html >/dev/null
          wp litespeed-option set object-host ${redisName} --allow-root --path=/var/www/vhosts/${site.domain}/html >/dev/null
          wp litespeed-option set object-port 6379 --allow-root --path=/var/www/vhosts/${site.domain}/html >/dev/null
          wp litespeed-option set object-db_id 0 --allow-root --path=/var/www/vhosts/${site.domain}/html >/dev/null
          wp litespeed-option set object-persistent true --allow-root --path=/var/www/vhosts/${site.domain}/html >/dev/null
          wp litespeed-option set object-admin true --allow-root --path=/var/www/vhosts/${site.domain}/html >/dev/null
        ''
      }

      ${dockerBin} exec ${siteInfo.litespeedName} sh -c ${
        lib.escapeShellArg ''
          chown -R nobody:nogroup /var/www/vhosts/${site.domain}
        ''
      }
    '') siteList;

  bootstrapScript =
    pkgs.writeShellScript "wordpress-litespeed-proxy-bootstrap" ''
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

      wait_for_container() {
        local container_name="$1"
        local tries=90

        while [ "$tries" -gt 0 ]; do
          if ${dockerBin} exec "$container_name" true >/dev/null 2>&1; then
            return 0
          fi

          tries=$((tries - 1))
          sleep 2
        done

        echo "WordPress container did not become ready: $container_name" >&2
        return 1
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

  configMaterializeScript =
    pkgs.writeShellScript "wordpress-litespeed-proxy-materialize-config" ''
      set -euo pipefail

      ${lib.concatMapStringsSep "\n" (siteInfo: ''
        ${pkgs.coreutils}/bin/install -Dm0644 ${siteInfo.httpdConfigFile} ${
          lib.escapeShellArg siteInfo.httpdConfigPath
        }
        ${pkgs.coreutils}/bin/install -Dm0644 ${siteInfo.dockerTemplateFile} ${
          lib.escapeShellArg siteInfo.dockerTemplatePath
        }
        ${pkgs.coreutils}/bin/install -Dm0644 ${smtpMuPluginFile} ${
          lib.escapeShellArg
          "${siteInfo.siteHtmlDir}/wp-content/mu-plugins/iss-smtp.php"
        }
        ${pkgs.coreutils}/bin/install -Dm0644 ${uploadLimitMuPluginFile} ${
          lib.escapeShellArg
          "${siteInfo.siteHtmlDir}/wp-content/mu-plugins/iss-upload-limit.php"
        }
      '') siteList}
    '';

  containers = {
    ${redisName} = {
      image = "${cfg.redisImage}:${cfg.redisTag}";
      autoStart = true;
      serviceName = redisName;
      cmd = [ "redis-server" "--appendonly" "yes" ];
      volumes = [ "${redisDataDir}:/data" ];
      networks = [ sharedNetworkName ];
      extraOptions = [ "--log-driver=none" ];
    };
  } // lib.foldl' lib.recursiveUpdate { } (map (siteInfo: {
    ${siteInfo.litespeedName} = {
      image = "litespeedtech/openlitespeed:${cfg.olsVersion}-${cfg.phpVersion}";
      autoStart = true;
      serviceName = siteInfo.litespeedName;
      environment = {
        TZ = cfg.timeZone;
        TimeZone = cfg.timeZone;
        OLS_VERSION = cfg.olsVersion;
        PHP_VERSION = cfg.phpVersion;
        PHPMYADMIN_VERSION = cfg.phpMyAdminVersion;
      };
      environmentFiles = cfg.environmentFiles;
      volumes = [
        "${siteInfo.adminConfDir}:/usr/local/lsws/admin/conf"
        "${siteInfo.siteRoot}:/var/www/vhosts/${siteInfo.site.domain}"
        "${siteInfo.litespeedLogsDir}:/usr/local/lsws/logs"
        "${siteInfo.httpdConfigPath}:/usr/local/lsws/conf/httpd_config.conf"
        "${siteInfo.dockerTemplatePath}:/usr/local/lsws/conf/templates/docker.conf"
        "${siteInfo.smtpPasswordFile}:${siteInfo.smtpPasswordMountPath}:ro"
      ];
      ports = [
        "127.0.0.1:${toString siteInfo.site.proxyPort}:80"
        "${cfg.bindAddress}:${toString siteInfo.site.adminPort}:7080"
      ];
      networks = [ sharedNetworkName siteInfo.networkName ];
      dependsOn = [
        siteInfo.mysqlName
        redisName

      ];
    };

    ${siteInfo.mysqlName} = {
      image = "${cfg.mariadbImage}:${cfg.mariadbTag}";
      autoStart = true;
      serviceName = siteInfo.mysqlName;
      cmd = [ "--max-allowed-packet=512M" ];
      environment = {
        MYSQL_DATABASE = siteInfo.site.database.name;
        MYSQL_USER = siteInfo.site.database.user;
      };
      environmentFiles = cfg.environmentFiles
        ++ [ siteInfo.site.secretEnvFile ];
      volumes = [ "${siteInfo.databaseDir}:/var/lib/mysql" ];
      networks = [ siteInfo.networkName ];
      extraOptions = [
        "--log-driver=none"
        "--stop-timeout=${toString mysqlStopTimeoutSeconds}"
      ];
    };

    ${siteInfo.phpmyadminName} = {
      image = "phpmyadmin:${cfg.phpMyAdminVersion}-apache";
      autoStart = true;
      serviceName = siteInfo.phpmyadminName;
      environment = { PMA_HOST = siteInfo.mysqlName; };
      environmentFiles = cfg.environmentFiles;
      ports =
        [ "${cfg.bindAddress}:${toString siteInfo.site.phpMyAdminPort}:80" ];
      networks = [ siteInfo.networkName ];
      dependsOn = [ siteInfo.mysqlName ];
    };
  }) siteList);

  tmpfilesRules = [
    "d ${cfg.dataDir} 0755 root root -"
    "d ${cfg.dataDir}/data 0755 root root -"
    "d ${cfg.dataDir}/lsws 0755 root root -"
    "d ${cfg.dataDir}/redis 0755 root root -"
    "d ${redisDataDir} 0755 root root -"
    "d ${sitesDir} 0755 root root -"
  ] ++ lib.concatMap (siteInfo: [
    "d ${builtins.dirOf siteInfo.databaseDir} 0755 root root -"
    "d ${siteInfo.databaseDir} 0755 :root :root -"
    "d ${siteInfo.litespeedDir} 0755 root root -"
    "d ${siteInfo.adminConfDir} 0755 root root -"
    "d ${siteInfo.litespeedConfigDir} 0755 root root -"
    "d ${siteInfo.litespeedLogsDir} 0755 root root -"
    "d ${siteInfo.siteRoot} 0755 root root -"
    "d ${siteInfo.siteHtmlDir} 0755 root root -"
    "d ${siteInfo.siteLogsDir} 0755 root root -"
  ]) siteList ++ lib.optionals (backupSiteList != [ ])
    [ "d ${cfg.dataDir}/backups 0700 root root -" ]
    ++ map (siteInfo: "d ${siteInfo.backupDir} 0700 root root -")
    backupSiteList;

  acmeCerts = lib.listToAttrs (map (siteInfo:
    lib.nameValuePair siteInfo.site.domain {
      dnsProvider = cfg.hostAcme.dnsProvider;
      environmentFile = cfg.hostAcme.environmentFile;
      dnsPropagationCheck = true;
      extraDomainNames = siteInfo.extraDomainNames;
      reloadServices = [ "nginx.service" ];
    }) siteList);

  nginxVirtualHosts = lib.listToAttrs (map (siteInfo:
    let site = siteInfo.site;
    in lib.nameValuePair site.domain ({
      serverAliases = siteInfo.extraDomainNames;
      # NGINX2Shell (CVE-2026-123007/123633) is only reachable over HTTP/2.
      # Re-enable once nixpkgs ships nginx >= 1.30.7.
      http2 = false;
      # password for protected sites.
      # must be in htpasswd format
      # generate one with -> openssl passwd -apr1 'your-password-here'
      # format is user:password for the the file
      extraConfig = lib.optionalString site.protected.enabled ''
        auth_basic "Restricted";
        auth_basic_user_file ${site.protected.passwordFile};
      '' + ''
        client_max_body_size ${uploadLimit};
      '';
      locations."/" = {
        proxyPass = "http://127.0.0.1:${toString site.proxyPort}";
        proxyWebsockets = true;
        extraConfig = ''
          proxy_set_header Host $host;
          proxy_set_header X-Real-IP $remote_addr;
          proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
          proxy_set_header X-Forwarded-Proto $scheme;
          proxy_set_header X-Forwarded-Host $host;
          proxy_set_header X-Forwarded-Port $server_port;
          proxy_redirect off;
        '';
      };
    } // lib.optionalAttrs cfg.hostAcme.enable {
      useACMEHost = site.domain;
      addSSL = true;
    })) siteList);
in {
  options.my.wordpressLiteSpeedProxy = {
    enable = lib.mkEnableOption
      "OpenLiteSpeed multi-site WordPress stack behind host nginx";

    dataDir = lib.mkOption {
      type = lib.types.path;
      default = "${config.my.services.baseDataDir}/wordpress-litespeed-proxy";
    };

    networkName = lib.mkOption {
      type = lib.types.str;
      default = "wordpress_litespeed_proxy_server";
    };

    bindAddress = lib.mkOption {
      type = lib.types.str;
      default = "0.0.0.0";
    };

    acmeEmail = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
    };

    timeZone = lib.mkOption {
      type = lib.types.str;
      default = "America/New_York";
    };

    olsVersion = lib.mkOption {
      type = lib.types.str;
      default = "1.9.3";
    };

    phpVersion = lib.mkOption {
      type = lib.types.str;
      default = "lsphp85";
    };

    phpMyAdminVersion = lib.mkOption {
      type = lib.types.str;
      default = "5.2.3";
    };

    uploadLimitMB = lib.mkOption {
      type = lib.types.int;
      default = 100;
      description = "Maximum WordPress upload/request body size in megabytes.";
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
      type = lib.types.attrsOf (lib.types.submodule ({ name, ... }: {
        options = {
          domain = lib.mkOption { type = lib.types.str; };

          wwwAlias = lib.mkOption {
            type = lib.types.bool;
            default = true;
          };

          proxyPort = lib.mkOption { type = lib.types.int; };

          adminPort = lib.mkOption { type = lib.types.int; };

          phpMyAdminPort = lib.mkOption { type = lib.types.int; };

          secretEnvFile = lib.mkOption {
            type = lib.types.path;
            description = ''
              Path to a sops-nix environment file containing MYSQL_ROOT_PASSWORD,
              MYSQL_PASSWORD, and WORDPRESS_ADMIN_PASSWORD.
            '';
          };

          backup.enable =
            lib.mkEnableOption "daily Restic backups for this WordPress site";

          protected = {
            enabled = lib.mkOption {
              type = lib.types.bool;
              default = false;
            };

            passwordFile = lib.mkOption {
              type = lib.types.nullOr lib.types.path;
              default = null;
              description = ''
                Path to an htpasswd-format file used by nginx basic auth.
              '';
            };
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

          mail = {
            email = lib.mkOption {
              type = lib.types.str;
              description = "Sender email address used by this WordPress site.";
            };

            replyTo = lib.mkOption {
              type = lib.types.nullOr lib.types.str;
              default = null;
              description =
                "Optional Reply-To email address used by this WordPress site.";
            };

            smtp = {
              host = lib.mkOption {
                type = lib.types.str;
                description = "SMTP host used by this WordPress site.";
              };

              port = lib.mkOption {
                type = lib.types.int;
                description = "SMTP port used by this WordPress site.";
              };

              secure = lib.mkOption {
                type = lib.types.enum [ "tls" "ssl" "none" ];
                description =
                  "SMTP transport security used by this WordPress site.";
              };

              passwordFile = lib.mkOption {
                type = lib.types.path;
                description =
                  "Path to the SMTP password file for this WordPress site.";
              };
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
      }));
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
        message =
          "my.wordpressLiteSpeedProxy.sites must define at least one site.";
      }
      {
        assertion = (!cfg.hostAcme.enable)
          || (cfg.hostAcme.environmentFile != null);
        message =
          "my.wordpressLiteSpeedProxy.hostAcme.environmentFile must be set when hostAcme is enabled.";
      }
      {
        assertion = (!cfg.hostAcme.enable) || (cfg.acmeEmail != null);
        message =
          "my.wordpressLiteSpeedProxy.acmeEmail must be set when hostAcme is enabled.";
      }
      {
        assertion = lib.length (lib.unique siteDomains)
          == lib.length siteDomains;
        message =
          "my.wordpressLiteSpeedProxy.sites domains must be unique.";
      }
      {
        assertion = lib.all (siteInfo:
          (!siteInfo.site.protected.enabled)
          || (siteInfo.site.protected.passwordFile != null)) siteList;
        message =
          "my.wordpressLiteSpeedProxy.sites protected.passwordFile must be set when protected.enabled is true.";
      }
      {
        assertion = lib.length (lib.unique phpMyAdminPorts)
          == lib.length phpMyAdminPorts;
        message =
          "my.wordpressLiteSpeedProxy.sites phpMyAdminPort values must be unique.";
      }
      {
        assertion = lib.length (lib.unique adminPorts) == lib.length adminPorts;
        message =
          "my.wordpressLiteSpeedProxy.sites adminPort values must be unique.";
      }
      {
        assertion = lib.length (lib.unique proxyPorts) == lib.length proxyPorts;
        message =
          "my.wordpressLiteSpeedProxy.sites proxyPort values must be unique.";
      }
    ];

    virtualisation.docker.enable = lib.mkDefault true;
    virtualisation.oci-containers.backend = lib.mkDefault "docker";

    networking.firewall.allowedTCPPorts = [ 80 443 ];

    networking.firewall.allowedUDPPorts = [ 443 ];

    services.nginx = {
      enable = true;
      recommendedTlsSettings = true;
      recommendedGzipSettings = true;
      virtualHosts = nginxVirtualHosts;
    };

    users.users.nginx.extraGroups =
      lib.optionals cfg.hostAcme.enable [ "acme" ];

    security.acme = lib.mkIf cfg.hostAcme.enable {
      acceptTerms = true;
      defaults = {
        email = cfg.acmeEmail;
        dnsProvider = cfg.hostAcme.dnsProvider;
        environmentFile = cfg.hostAcme.environmentFile;
        dnsPropagationCheck = true;
      };
      certs = acmeCerts;
    };

    systemd.tmpfiles.rules = tmpfilesRules;

    my.resticBackup = wordpressBackupJobs;

    environment.systemPackages = wordpressRestoreScripts;

    virtualisation.oci-containers.containers = containers;

    systemd.services = wordpressBackupSystemdServices // {
      wordpress-litespeed-proxy-config = {
        description = "Materialize WordPress LiteSpeed proxy configs";
        before = litespeedServices;
        requiredBy = litespeedServices;
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
        };
        script = ''
          ${configMaterializeScript}
        '';
      };

      wordpress-litespeed-proxy-network = {
        description = "Create WordPress LiteSpeed proxy Docker networks";
        after = [ containerRuntimeService ];
        requires = [ containerRuntimeService ];
        before = containerServices;
        requiredBy = containerServices;
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
        };
        script = ''
          ${dockerBin} network inspect ${sharedNetworkName} >/dev/null 2>&1 || ${dockerBin} network create ${sharedNetworkName} --subnet ${
            configLib.networking.docker.getSubnet sharedNetworkName
          }
          ${lib.concatMapStringsSep "\n" (siteInfo:
            "${dockerBin} network inspect ${siteInfo.networkName} >/dev/null 2>&1 || ${dockerBin} network create ${siteInfo.networkName} --subnet ${
              configLib.networking.docker.getSubnet siteInfo.networkName
            }") siteList}
        '';
      };

      wordpress-litespeed-proxy-bootstrap = {
        description = "Bootstrap LiteSpeed proxy WordPress sites";
        wantedBy = [ "multi-user.target" ];
        after = [
          "network-online.target"
          "${redisName}.service"
          "wordpress-litespeed-proxy-network.service"
        ] ++ mysqlServices ++ litespeedServices;
        wants = [ "network-online.target" ];
        requires =
          [ "${redisName}.service" "wordpress-litespeed-proxy-network.service" ]
          ++ mysqlServices ++ litespeedServices;
        path = [ pkgs.coreutils ];
        serviceConfig.Type = "oneshot";
        script = ''
          ${bootstrapScript}
        '';
      };
    };
  };
}
