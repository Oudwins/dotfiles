{ config, lib, pkgs, ... }:
let
  nodeExporterPort = 9901;
in
{
  # ! PROMETHEUS NODE EXPORTER

  services.prometheus = {
    # node exporter -> https://prometheus.io/docs/guides/node-exporter/
    exporters.node = {
      enable = true;
      enabledCollectors = [ "systemd" ];
      port = nodeExporterPort;
      # /nix/store/zgsw0yx18v10xa58psanfabmg95nl2bb-node_exporter-1.8.1/bin/node_exporter  --help
      #extraFlags = [ "--collector.ethtool" "--collector.softirqs" "--collector.tcpstat" "--collector.wifi" ];
    };
    scrapeConfigs = [
      {
        job_name = config.networking.hostName;
        static_configs = [
          {
            targets = [ "localhost:${toString nodeExporterPort}" ];
          }
        ];
      }
    ];
  };
}
