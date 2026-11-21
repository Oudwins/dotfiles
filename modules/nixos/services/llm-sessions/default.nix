# Records every CLIProxyAPI request on this machine into a local ClickHouse
# (database `llm`, tables `usage` and `exchanges`) and adds it to Grafana when
# Grafana runs here. Import alongside modules/nixos/services/llmproxy.
#
# The ClickHouse passwords are generated here on first start and never leave
# the machine. Query as admin with:
#   sudo sh -c 'CLICKHOUSE_PASSWORD="$(cat /var/lib/llm-sessions/default)" clickhouse client'
{
  config,
  configLib,
  lib,
  pkgs,
  ...
}:

let
  dir = "/var/lib/llm-sessions";
  grafana = config.services.grafana.enable;
  # Password files and their owners.
  owners = {
    default = "root";
    recorder = "cli-proxy-api";
  }
  // lib.optionalAttrs grafana { grafana = "grafana"; };
  clickhouseUrl = "http://127.0.0.1:${toString config.my.clickhouse.httpPort}";
in
{
  imports = [ (configLib.relativeToRoot "modules/nixos/services/clickhouse") ];

  systemd.services.llm-sessions-passwords = {
    description = "Generate the llm-sessions ClickHouse passwords";
    wantedBy = [ "multi-user.target" ];
    before = [
      "clickhouse.service"
      "cli-proxy-api.service"
    ]
    ++ lib.optional grafana "grafana.service";
    requiredBy = [
      "clickhouse.service"
      "cli-proxy-api.service"
    ]
    ++ lib.optional grafana "grafana.service";
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
      passwordFile = "${dir}/recorder";
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
    before = [ "cli-proxy-api.service" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      LoadCredential = "password:${dir}/default";
    };
    script = ''
      CLICKHOUSE_PASSWORD="$(< "$CREDENTIALS_DIRECTORY/password")" \
        ${config.services.clickhouse.package}/bin/clickhouse client --port 9000 --multiquery < ${./schema.sql}
    '';
  };

  services.cli-proxy-api.plugins.session-recorder = {
    package = pkgs.cpa-session-recorder;
    settings = {
      url = clickhouseUrl;
      database = "llm";
      user = "recorder";
      password-file = "${dir}/recorder";
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
}
