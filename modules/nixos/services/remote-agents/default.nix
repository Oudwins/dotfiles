# Serves the user's coding agent services (LLM proxy, Executor, T3 Code) at
# <subdomain>.<location>.<domain> for agents on other machines, and lists them
# on the dashboard. Needs roles/agents.nix with services.t3code enabled.
{ config, configLib, lib, ... }:

let
  cfg = config.my.remoteAgents;
  hm = config.home-manager.users.${config.my.username};
  # Written by nginx's preStart from cfg.t3code.tokenFile; sets $t3code_token.
  t3codeTokenConf = "/run/nginx/t3code-token.conf";
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
      # Browsers skip pairing: nginx signs them in with the token.
      extraConfig = ''
        include ${t3codeTokenConf};
        proxy_set_header Authorization $t3code_authorization;
      '';
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

  options.my.remoteAgents.t3code.tokenFile = lib.mkOption {
    type = lib.types.path;
    description = ''
      T3 Code bearer token (`t3 auth session issue --token-only`), readable by
      nginx. nginx sends it for browsers on the T3 Code site so they don't
      need a pairing code.
    '';
  };

  config = {
    services.nginx.preStart = ''
      printf 'set $t3code_token "%s";\n' "$(cat ${cfg.t3code.tokenFile})" > ${t3codeTokenConf}
    '';

    # A client's own credentials (the desktop app, the CLI) pass through. The
    # token goes only to requests from the site itself or typed into the address
    # bar, so pages on other sites can't use it through the browser. Chromium
    # sends no Sec-Fetch-Site on WebSocket handshakes, so those match on Origin.
    services.nginx.appendHttpConfig = ''
      map "$http_authorization|$http_sec_fetch_site|$http_origin|$scheme://$http_host" $t3code_authorization {
        default $http_authorization;
        "~^\|(same-origin|none)\|" "Bearer $t3code_token";
        "~^\|[^|]*\|([^|]+)\|\1$" "Bearer $t3code_token";
        "~^\|" "";
      }
    '';

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
          '' + service.extraConfig or "";
        };
      }
    ) services;

    my.dashboard.services = lib.mapAttrs (name: service: {
      inherit (service.dashboard) label description icon;
      url = "https://${host name}${service.dashboard.path or ""}";
      category = "agents";
    }) services;
  };
}
