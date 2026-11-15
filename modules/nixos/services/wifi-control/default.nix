{
  config,
  configLib,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.my.wifiControl;
  host = "${config.my.services.wifiControl.subdomain}.${config.my.server.location}.${config.my.domain}";
  executable = lib.getExe pkgs.wifi-control;
  localURL = "http://127.0.0.1:${toString cfg.port}";
  routers = lib.filterAttrs (_: router: router.enable) cfg.routers;
  routerEntries = lib.mapAttrsToList (id: router: { inherit id router; }) routers;
  routerConfig = pkgs.writeText "wifi-control-routers.json" (
    builtins.toJSON {
      routers = lib.mapAttrs (id: router: {
        inherit (router) name url;
        type = router.connectionType;
        certificateSHA256 = router.certificateSHA256;
        credentials = lib.mapAttrs (field: _: "${id}-${field}") router.credentials;
      }) routers;
    }
  );
  events = [
    {
      name = "on";
      time = cfg.onTime;
    }
    {
      name = "off";
      time = cfg.offTime;
    }
  ];
  clockType = lib.types.strMatching "([01][0-9]|2[0-3]):[0-5][0-9]";
in
{
  imports = [ (configLib.relativeToRoot "modules/nixos/services/nginx") ];

  options.my.wifiControl = {
    enable = lib.mkEnableOption "the router Wi-Fi controller";
    port = lib.mkOption {
      type = lib.types.port;
      default = 8790;
      description = "Loopback-only HTTP port.";
    };
    routers = lib.mkOption {
      default = { };
      description = "Routers keyed by a stable ID.";
      type = lib.types.attrsOf (
        lib.types.submodule (
          { name, ... }: {
            options = {
              enable = lib.mkOption {
                type = lib.types.bool;
                default = true;
              };
              name = lib.mkOption {
                type = lib.types.str;
                default = name;
              };
              connectionType = lib.mkOption {
                type = lib.types.enum [
                  "zte-http"
                  "openwrt-ubus"
                ];
              };
              url = lib.mkOption {
                type = lib.types.str;
                description = "ZTE HTTPS origin, or the full OpenWrt HTTPS /ubus endpoint.";
              };
              certificateSHA256 = lib.mkOption {
                type = lib.types.str;
                default = "";
                description = "Certificate SHA-256 pin; empty uses normal CA verification.";
              };
              credentials = lib.mkOption {
                type = lib.types.attrsOf lib.types.path;
                example = lib.literalExpression ''{ password = config.sops.secrets."wifi-control/digi/password".path; }'';
                description = "Authentication fields (username/password or an OpenWrt token) mapped to files holding them, usually sops secret paths.";
              };
            };
          }
        )
      );
    };
    timeZone = lib.mkOption {
      type = lib.types.str;
      default = config.time.timeZone;
      defaultText = lib.literalExpression "config.time.timeZone";
    };
    onTime = lib.mkOption {
      type = clockType;
      default = "07:00";
    };
    offTime = lib.mkOption {
      type = clockType;
      default = "23:00";
    };
    allowedNetworks = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [
        "127.0.0.1"
        "::1"
        "192.168.1.0/24"
        "100.64.0.0/10"
        "fd7a:115c:a1e0::/48"
      ];
      description = "LAN and Tailscale client networks allowed to access the control page.";
    };
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages = [ pkgs.wifi-control ];
    assertions = [
      {
        assertion = cfg.onTime != cfg.offTime;
        message = "Wi-Fi on and off times must differ.";
      }
      {
        assertion = routers != { };
        message = "Enable at least one Wi-Fi router.";
      }
      {
        assertion = lib.all (id: builtins.match "[a-zA-Z0-9][a-zA-Z0-9_-]{0,63}" id != null) (
          builtins.attrNames routers
        );
        message = "Wi-Fi router IDs must be 1–64 letters, digits, underscores, or hyphens.";
      }
    ];

    systemd.services = {
      wifi-control = {
        description = "Router Wi-Fi control page and API";
        wantedBy = [ "multi-user.target" ];
        wants = [ "network-online.target" ];
        after = [ "network-online.target" ];
        serviceConfig = {
          Type = "notify";
          ExecStart = lib.escapeShellArgs [
            executable
            "serve"
            "--listen"
            "127.0.0.1:${toString cfg.port}"
            "--config"
            routerConfig
            "--state-file"
            "/var/lib/wifi-control/locks.json"
            "--public-url"
            "https://${host}"
            "--timezone"
            cfg.timeZone
            "--on"
            cfg.onTime
            "--off"
            cfg.offTime
          ];
          LoadCredential = lib.concatMap (
            { id, router }:
            lib.mapAttrsToList (
              field: file: "${id}-${field}:${file}"
            ) router.credentials
          ) routerEntries;
          StateDirectory = "wifi-control";
          StateDirectoryMode = "0700";
          DynamicUser = true;
          Restart = "on-failure";
          RestartSec = 3;
          NoNewPrivileges = true;
          ProtectSystem = "strict";
          ProtectHome = true;
          PrivateTmp = true;
          RestrictAddressFamilies = [
            "AF_INET"
            "AF_INET6"
            "AF_UNIX"
          ];
        };
      };
    }
    // lib.listToAttrs (
      map (
        event:
        lib.nameValuePair "wifi-control-${event.name}" {
          description = "Set unlocked routers' Wi-Fi ${event.name}";
          requires = [ "wifi-control.service" ];
          after = [ "wifi-control.service" ];
          serviceConfig = {
            Type = "oneshot";
            DynamicUser = true;
            ExecStart = lib.escapeShellArgs [
              executable
              "scheduled-set"
              "--server"
              localURL
              event.name
            ];
            TimeoutStartSec = 70;
            NoNewPrivileges = true;
            ProtectSystem = "strict";
            ProtectHome = true;
          };
        }
      ) events
    );

    systemd.timers = lib.listToAttrs (
      map (
        event:
        lib.nameValuePair "wifi-control-${event.name}" {
          description = "Daily Wi-Fi ${event.name} at ${event.time} (${cfg.timeZone})";
          wantedBy = [ "timers.target" ];
          timerConfig = {
            OnCalendar = "*-*-* ${event.time}:00 ${cfg.timeZone}";
            AccuracySec = "1s";
            RandomizedDelaySec = 0;
            # Manual commands never move these timers. Missed events are not replayed on boot.
            Persistent = false;
          };
        }
      ) events
    );

    networking.firewall.allowedTCPPorts = [
      80
      443
    ];
    services.nginx.virtualHosts.${host} = {
      useACMEHost = "${config.my.server.location}.${config.my.domain}";
      forceSSL = true;
      locations."/" = {
        proxyPass = localURL;
        recommendedProxySettings = true;
        extraConfig = ''
          ${lib.concatMapStrings (network: "allow ${network};\n") cfg.allowedNetworks}
          deny all;
          proxy_read_timeout 65s;
        '';
      };
    };

    my.dashboard.services.wifi-control = {
      label = "Wi-Fi";
      description = "Router controls & locks · on ${cfg.onTime} / off ${cfg.offTime}";
      url = "https://${host}";
      category = "management";
      icon = "mdi-wifi";
    };
  };
}
