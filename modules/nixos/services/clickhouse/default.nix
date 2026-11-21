# Loopback-only ClickHouse with password users. Passwords are read from files at
# start (systemd credentials) and handed to ClickHouse through @from_env, so they
# never enter the Nix store. Not backed up.
{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.my.clickhouse;
  envName = name: "CLICKHOUSE_PASSWORD_${lib.toUpper (lib.replaceStrings [ "-" ] [ "_" ] name)}";
  loopback = [
    "127.0.0.1"
    "::1"
  ];
  start = pkgs.writeShellScript "clickhouse-start" ''
    set -euo pipefail
    ${lib.concatStrings (
      lib.mapAttrsToList (name: _: ''
        ${envName name}="$(< "$CREDENTIALS_DIRECTORY/${name}")"
        export ${envName name}
      '') cfg.users
    )}
    exec ${config.services.clickhouse.package}/bin/clickhouse-server --config=/etc/clickhouse-server/config.xml
  '';
in
{
  options.my.clickhouse = {
    httpPort = lib.mkOption {
      type = lib.types.port;
      default = 8123;
      description = "Loopback HTTP port.";
    };
    tcpPort = lib.mkOption {
      type = lib.types.port;
      # 9000 is ClickHouse's default, but S3 servers such as RustFS default to it too.
      default = 9010;
      description = "Loopback native protocol port, used by `clickhouse client`.";
    };
    users = lib.mkOption {
      default = { };
      description = "Users allowed from loopback only. `default` is the built-in admin.";
      type = lib.types.attrsOf (
        lib.types.submodule {
          options = {
            passwordFile = lib.mkOption {
              type = lib.types.str;
              description = "File containing the user's password.";
            };
            grants = lib.mkOption {
              type = lib.types.listOf lib.types.str;
              default = [ ];
              example = [ "GRANT INSERT ON db.*" ];
              description = "GRANT statements for the user. Leave empty for `default`, which keeps full access.";
            };
          };
        }
      );
    };
  };

  config = {
    assertions = [
      {
        assertion = cfg.users ? default;
        message = "my.clickhouse.users.default needs a passwordFile; ClickHouse's default user has none.";
      }
    ];

    services.clickhouse = {
      enable = true;
      # The packaged config already listens on ::1 and 127.0.0.1 only.
      serverConfig = {
        http_port = cfg.httpPort;
        tcp_port = cfg.tcpPort;
        mysql_port."@remove" = "1";
        postgresql_port."@remove" = "1";
        interserver_http_port."@remove" = "1";
        # System logs have no TTL by default; keep the useful ones for a month.
        query_log.ttl = "event_date + INTERVAL 30 DAY";
        error_log.ttl = "event_date + INTERVAL 30 DAY";
      }
      //
        lib.genAttrs
          [
            "trace_log"
            "text_log"
            "metric_log"
            "asynchronous_metric_log"
            "query_metric_log"
            "query_thread_log"
            "part_log"
            "processors_profile_log"
            "latency_log"
            "background_schedule_pool_log"
            "opentelemetry_span_log"
            "instrumentation_trace_log"
          ]
          (_: {
            "@remove" = "1";
          });
      usersConfig.users = lib.mapAttrs (
        name: user:
        {
          password."@from_env" = envName name;
          networks = {
            "@replace" = "replace";
            ip = loopback;
          };
        }
        // lib.optionalAttrs (user.grants != [ ]) {
          profile = "default";
          quota = "default";
          grants.query = user.grants;
        }
      ) cfg.users;
    };

    systemd.services.clickhouse.serviceConfig = {
      LoadCredential = lib.mapAttrsToList (name: user: "${name}:${user.passwordFile}") cfg.users;
      ExecStart = lib.mkForce start;
    };
  };
}
