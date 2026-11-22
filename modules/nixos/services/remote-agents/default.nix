# Serves the user's coding agent services (LLM proxy, Executor, T3 Code) at
# <subdomain>.<location>.<domain> for agents on other machines, and lists them
# on the dashboard. Needs roles/agents.nix with services.t3code enabled.
{ config, configLib, lib, ... }:

let
  hm = config.home-manager.users.${config.my.username};
  services = {
    llmproxy = {
      # Matches home-files/tmx/.cli-proxy-api/{personal,work}.yaml.
      port = 8317;
      dashboard = {
        label = "LLM proxy";
        description = "CLIProxyAPI management";
        path = "/management.html";
        icon = "mdi-robot";
      };
    };
    executor = {
      inherit (hm.services.executor) port;
      dashboard = {
        label = "Executor";
        description = "MCP gateway";
        icon = "mdi-hub";
      };
    };
    t3code = {
      inherit (hm.services.t3code) port;
      dashboard = {
        label = "T3 Code";
        description = "Coding agent workspace";
        icon = "mdi-code-braces";
      };
    };
  };
  host = name: "${config.my.services.${name}.subdomain}.${config.my.server.location}.${config.my.domain}";
in
{
  imports = [ (configLib.relativeToRoot "modules/nixos/services/nginx") ];

  services.nginx.virtualHosts = lib.mapAttrs' (
    name: service:
    lib.nameValuePair (host name) {
      useACMEHost = "${config.my.server.location}.${config.my.domain}";
      addSSL = true;
      locations."/" = {
        proxyPass = "http://127.0.0.1:${toString service.port}";
        proxyWebsockets = true;
        recommendedProxySettings = true;
        # Stream model responses and MCP events, and allow large prompts and uploads.
        extraConfig = ''
          proxy_buffering off;
          proxy_read_timeout 1h;
          client_max_body_size 0;
        '';
      };
    }
  ) services;

  my.dashboard.services = lib.mapAttrs (name: service: {
    inherit (service.dashboard) label description icon;
    url = "https://${host name}${service.dashboard.path or ""}";
    category = "agents";
  }) services;
}
