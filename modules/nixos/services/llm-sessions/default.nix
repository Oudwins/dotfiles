# The llm-sessions database: ClickHouse (database `llm`, tables `usage` and
# `exchanges`) that proxies write to with modules/shared/llm-session-recorder.
# Served at https://<subdomain>.<location>.<domain> for proxies on other hosts,
# and added to Grafana when Grafana runs here.
#
# The admin and Grafana passwords are generated here on first start and never
# leave the machine. Query as admin with:
#   sudo sh -c 'CLICKHOUSE_PASSWORD="$(cat /var/lib/llm-sessions/default)" clickhouse client --port 9010'
{
  config,
  configLib,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.services.llm-sessions;
  dir = "/var/lib/llm-sessions";
  host = "${config.my.services.llmSessions.subdomain}.${config.my.server.location}.${config.my.domain}";
  grafana = config.services.grafana.enable;
  # Password files and their owners.
  owners = {
    default = "root";
  }
  // lib.optionalAttrs grafana { grafana = "grafana"; };
in
{
  imports = [
    (configLib.relativeToRoot "modules/nixos/services/clickhouse")
    (configLib.relativeToRoot "modules/nixos/services/nginx")
  ];

  options.services.llm-sessions.recorderPasswordFile = lib.mkOption {
    type = lib.types.str;
    description = "Password of the `recorder` user (INSERT only), shared with the recording proxies.";
  };

  config = {
    systemd.services.llm-sessions-passwords = {
      description = "Generate the llm-sessions ClickHouse passwords";
      wantedBy = [ "multi-user.target" ];
      before = [ "clickhouse.service" ] ++ lib.optional grafana "grafana.service";
      requiredBy = [ "clickhouse.service" ] ++ lib.optional grafana "grafana.service";
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        UMask = "0077";
      };
      script = ''
        install -d -m 0711 ${dir}
        ${lib.concatStrings (
          lib.mapAttrsToList (name: owner: ''
            if [ ! -s ${dir}/${name} ]; then
              ${pkgs.openssl}/bin/openssl rand -hex 32 > ${dir}/${name}.tmp
              mv ${dir}/${name}.tmp ${dir}/${name}
            fi
            chown ${owner}: ${dir}/${name}
            chmod 0400 ${dir}/${name}
          '') owners
        )}
      '';
    };

    my.clickhouse.users = {
      default.passwordFile = "${dir}/default";
      recorder = {
        passwordFile = cfg.recorderPasswordFile;
        grants = [ "GRANT INSERT ON llm.*" ];
      };
    }
    // lib.optionalAttrs grafana {
      grafana = {
        passwordFile = "${dir}/grafana";
        grants = [ "GRANT SELECT ON llm.*" ];
      };
    };

    systemd.services.llm-sessions-schema = {
      description = "Create the llm-sessions ClickHouse schema";
      wantedBy = [ "multi-user.target" ];
      after = [ "clickhouse.service" ];
      requires = [ "clickhouse.service" ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        LoadCredential = "password:${dir}/default";
      };
      script = ''
        CLICKHOUSE_PASSWORD="$(< "$CREDENTIALS_DIRECTORY/password")" \
          ${config.services.clickhouse.package}/bin/clickhouse client --port ${toString config.my.clickhouse.tcpPort} --multiquery < ${./schema.sql}
      '';
    };

    services.nginx.virtualHosts.${host} = {
      useACMEHost = "${config.my.server.location}.${config.my.domain}";
      # Proxies send the password with every insert; never serve it over plain HTTP.
      forceSSL = true;
      locations."/" = {
        proxyPass = "http://127.0.0.1:${toString config.my.clickhouse.httpPort}";
        recommendedProxySettings = true;
        # Insert batches carry whole conversations.
        extraConfig = ''
          proxy_request_buffering off;
          client_max_body_size 0;
        '';
      };
    };

    services.grafana = lib.mkIf grafana {
      declarativePlugins = [ pkgs.grafanaPlugins.grafana-clickhouse-datasource ];
      provision.datasources.settings.datasources = [
        {
          name = "LLM sessions";
          type = "grafana-clickhouse-datasource";
          jsonData = {
            host = "127.0.0.1";
            port = config.my.clickhouse.httpPort;
            protocol = "http";
            username = "grafana";
            defaultDatabase = "llm";
          };
          secureJsonData.password = "$__file{${dir}/grafana}";
        }
      ];
    };
  };
}
