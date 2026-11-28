# Grafana logs in through tsidp directly. SSO admins become Grafana admins.
# The local login stays at /login?disableAutoLogin.
{ config, lib, ... }:

let
  domain = "${config.my.services.grafana.subdomain}.${config.my.server.location}.${config.my.domain}";
  inherit (config.my.sso) issuer;
in
{
  imports = [ ../sso ];

  config = lib.mkIf (config.my.sso.enabledFor "grafana") {
    my.sso.clients.grafana.redirectURIs = [ "https://${domain}/login/generic_oauth" ];

    systemd.services.grafana.serviceConfig.LoadCredential = [
      "sso-client-secret:${config.my.sso.clients.grafana.secretFile}"
    ];

    services.grafana.settings = {
      server.root_url = "https://${domain}/";
      "auth.generic_oauth" = {
        enabled = true;
        name = "Tailscale";
        auto_login = true;
        allow_sign_up = true;
        use_pkce = true;
        client_id = "grafana";
        client_secret = "$__file{/run/credentials/grafana.service/sso-client-secret}";
        scopes = "openid email profile";
        auth_url = "${issuer}/authorize";
        token_url = "${issuer}/token";
        api_url = "${issuer}/userinfo";
        role_attribute_path = "contains([${
          lib.concatMapStringsSep "," (email: "'${email}'") config.my.sso.admins
        }], email) && 'Admin' || 'Viewer'";
      };
    };
  };
}
