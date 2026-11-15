{
  config,
  lib,
  pkgs,
  ...
}:
let
  grafanaPort = 3333;
  grafanaDomain = "${config.my.services.grafana.subdomain}.${config.my.server.location}.${config.my.domain}";
  prometheusPort = 9900;
in
{
  imports = [
    ./metricsClient.nix
  ];

  environment.etc = {
    "grafana-dashboards/1860-node-exporter-full.json" = {
      source = ./grafana-dashboards/1860-node-exporter-full.json;
      group = "grafana";
      user = "grafana";
    };
  };

  sops.secrets."grafana/secret_key" = {
    owner = "grafana";
    group = "grafana";
    mode = "0400";
  };

  # ! GRAFANA
  services.grafana = {
    enable = true;
    settings = {
      security.secret_key = "$__file{${config.sops.secrets."grafana/secret_key".path}}";
      server = {
        # domain = grafanaDomain;
        http_port = grafanaPort;
        http_addr = "0.0.0.0";
      };
    };
    provision = {
      enable = true;
      # Provision grafana dashboards
      dashboards.settings.providers = [
        {
          # https://grafana.com/grafana/dashboards/1860-node-exporter-full/
          name = "my dashboards";
          options.path = "/etc/grafana-dashboards";
        }
      ];
      # connect to prometheus
      datasources.settings.datasources = [
        {
          name = "Prometheus";
          type = "prometheus";
          url = "http://${config.services.prometheus.listenAddress}:${toString config.services.prometheus.port}";
          isDefault = true;
        }
      ];
    };
  };

  services.nginx.virtualHosts."${grafanaDomain}" = {
    useACMEHost = "${config.my.server.location}.${config.my.domain}";
    addSSL = true;
    locations."/" = {
      proxyPass = "http://localhost:${toString grafanaPort}";
      proxyWebsockets = true; # Enable if needed
      recommendedProxySettings = true;
    };
  };

  # ! PROMETHEUS

  services.prometheus = {
    enable = true;
    port = prometheusPort;
  };

  my.dashboard.services.grafana = {
    label = "Grafana";
    description = "Metrics";
    url = "https://${config.my.services.grafana.subdomain}.${config.my.server.location}.${config.my.domain}";
    category = "system";
    icon = "grafana";
  };

}
