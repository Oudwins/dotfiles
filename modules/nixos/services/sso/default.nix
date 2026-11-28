# Single sign-on from the caller's Tailscale identity: nobody types a password.
# tsidp is the OIDC provider (its own tailnet node, idp-<location>); it is
# patched to only log in the users a client allows (pkgs/tsidp).
#
# A host turns it on with my.sso.enable (opting a service out with
# my.sso.services.<name> = false). Service modules import this one and, when
# my.sso.enabledFor "<service>", register:
#   - my.sso.clients.<service>: an OIDC client, for apps with native OIDC.
#   - my.sso.proxy.<vhost>: nginx checks every request with oauth2-proxy (itself
#     a tsidp client) and passes the user's email to the app as Remote-User.
# Who may use which service comes from my.sso.users and my.sso.tags (soft
# secrets); the built-in "admin" tag is every service.
#
# The host provides the tailnet auth key for tsidp as services.tsidp.environmentFile
# (TS_AUTHKEY=...). Client secrets are generated on the machine in /var/lib/sso.
{
  config,
  lib,
  pkgs,
  ...
}:

let
  inherit (lib) mkOption types;
  cfg = config.my.sso;

  fqdn = "${config.services.tsidp.settings.hostName}.${config.my.tailnet}";
  secretsDir = "/var/lib/sso";
  proxyAddress = "127.0.0.1:4180";

  # tsidp's email claim: GitHub and passkey logins get the idp host appended.
  emailOf =
    login:
    if lib.hasSuffix "@github" login || lib.hasSuffix "@passkey" login then "${login}.${fqdn}" else login;
  emailsWhere = pred: map emailOf (lib.attrNames (lib.filterAttrs (_: pred) cfg.users));
  isAdmin = user: lib.elem "admin" user.tags;
  emailsFor =
    service:
    emailsWhere (
      user: isAdmin user || lib.any (tag: lib.elem service (cfg.tags.${tag} or [ ])) user.tags
    );

  clientsFile = pkgs.writeText "tsidp-clients.json" (
    builtins.toJSON (
      lib.mapAttrs (name: client: {
        client_id = name;
        client_name = name;
        redirect_uris = client.redirectURIs;
        allowed_emails = client.emails;
        created_at = "1970-01-01T00:00:00Z";
      }) cfg.clients
    )
  );

  oauth2ProxyHeaders = ''
    auth_request off;
    proxy_set_header Host $host;
    proxy_set_header X-Forwarded-Proto https;
  '';
in
{
  options.my.sso = {
    enabledFor = mkOption {
      type = types.functionTo types.bool;
      readOnly = true;
      default = service: cfg.enable && cfg.services.${service} or true;
      description = "Whether a service's module should wire it to SSO.";
    };
    issuer = mkOption {
      type = types.str;
      readOnly = true;
      default = "https://${fqdn}";
    };
    admins = mkOption {
      type = types.listOf types.str;
      readOnly = true;
      default = emailsWhere isAdmin;
      description = "Email claims of the users with access to everything.";
    };
    clients = mkOption {
      type = types.attrsOf (
        types.submodule (
          { name, ... }:
          {
            options = {
              redirectURIs = mkOption { type = types.listOf types.str; };
              emails = mkOption {
                type = types.listOf types.str;
                default = emailsFor name;
              };
              secretFile = mkOption {
                type = types.str;
                readOnly = true;
                default = "${secretsDir}/${name}";
              };
            };
          }
        )
      );
      default = { };
    };
    proxy = mkOption {
      type = types.attrsOf (
        types.submodule {
          options = {
            service = mkOption { type = types.str; };
            # Paths apps call without a browser (they keep their own API keys).
            skipLocations = mkOption {
              type = types.listOf types.str;
              default = [ ];
            };
          };
        }
      );
      default = { };
    };
  };

  config = lib.mkIf cfg.enable (lib.mkMerge [
    {
      assertions = [
        {
          assertion = !(cfg.tags ? admin);
          message = "my.sso.tags.admin is built in (every service); don't define it.";
        }
      ]
      ++ lib.mapAttrsToList (login: user: {
        assertion = lib.subtractLists ([ "admin" ] ++ lib.attrNames cfg.tags) user.tags == [ ];
        message = "my.sso.users.\"${login}\" uses tags not in my.sso.tags.";
      }) cfg.users;

      services.tsidp = {
        enable = true;
        settings = {
          hostName = "idp-${config.my.server.location}";
          # Token exchange would let a token for one client be swapped for another.
          enableSts = false;
        };
      };

      system.activationScripts.sso-secrets = ''
        install -d -m 0700 ${secretsDir}
        for name in ${lib.escapeShellArgs (lib.attrNames cfg.clients ++ [ "oauth2-proxy-cookie" ])}; do
          [ -s "${secretsDir}/$name" ] || (umask 077; ${lib.getExe pkgs.openssl} rand -hex 16 | tr -d '\n' > "${secretsDir}/$name")
        done
      '';

      # tsidp keeps its clients in its state dir; rewrite them from Nix on start.
      systemd.services.tsidp = {
        restartTriggers = [ clientsFile ];
        serviceConfig = {
          LoadCredential = lib.mapAttrsToList (name: client: "${name}:${client.secretFile}") cfg.clients;
          ExecStartPre = pkgs.writeShellScript "tsidp-clients" ''
            clients=$(< ${clientsFile})
            for name in ${lib.escapeShellArgs (lib.attrNames cfg.clients)}; do
              clients=$(${lib.getExe pkgs.jq} --arg n "$name" --rawfile s "$CREDENTIALS_DIRECTORY/$name" \
                '.[$n].client_secret = $s' <<<"$clients")
            done
            printf '%s' "$clients" > "$STATE_DIRECTORY/oidc-funnel-clients.json"
          '';
        };
      };
    }

    (lib.mkIf (cfg.proxy != { }) {
      assertions = lib.mapAttrsToList (vhost: p: {
        assertion = emailsFor p.service != [ ];
        message = "my.sso.proxy.\"${vhost}\": no user in my.sso.users may use ${p.service}.";
      }) cfg.proxy;

      my.sso.clients.oauth2-proxy = {
        redirectURIs = map (vhost: "https://${vhost}/oauth2/callback") (lib.attrNames cfg.proxy);
        # Each vhost restricts further with allowed_emails.
        emails = map emailOf (lib.attrNames cfg.users);
      };

      services.oauth2-proxy = {
        enable = true;
        provider = "oidc";
        oidcIssuerUrl = cfg.issuer;
        clientID = "oauth2-proxy";
        clientSecretFile = cfg.clients.oauth2-proxy.secretFile;
        cookie.secretFile = "${secretsDir}/oauth2-proxy-cookie";
        email.domains = [ "*" ];
        upstream = "static://202";
        httpAddress = "http://${proxyAddress}";
        reverseProxy = true;
        trustedProxyIP = [ "127.0.0.1/32" ];
        setXauthrequest = true;
      };

      # It fetches the issuer's discovery document on start, before tsidp is up.
      systemd.services.oauth2-proxy = {
        wants = [ "tsidp.service" ];
        after = [ "tsidp.service" ];
        startLimitIntervalSec = 0;
        serviceConfig.RestartSec = 5;
      };

      services.nginx.virtualHosts = lib.mapAttrs (vhost: p: {
        extraConfig = ''
          auth_request /oauth2/auth;
          error_page 401 = @sso_login;
        '';
        locations = {
          "/".extraConfig = ''
            auth_request_set $sso_email $upstream_http_x_auth_request_email;
            proxy_set_header Remote-User $sso_email;
          '';
          "/oauth2/" = {
            proxyPass = "http://${proxyAddress}";
            extraConfig = oauth2ProxyHeaders;
          };
          "= /oauth2/auth" = {
            proxyPass = "http://${proxyAddress}/oauth2/auth?allowed_emails=${
              lib.concatMapStringsSep "," lib.escapeURL (emailsFor p.service)
            }";
            extraConfig = oauth2ProxyHeaders + ''
              proxy_set_header Content-Length "";
              proxy_pass_request_body off;
            '';
          };
          "@sso_login" = {
            return = "307 https://$host/oauth2/start?rd=$request_uri";
            extraConfig = "auth_request off;";
          };
        }
        // lib.genAttrs p.skipLocations (_: {
          inherit (config.services.nginx.virtualHosts.${vhost}.locations."/") proxyPass;
          extraConfig = ''
            auth_request off;
            proxy_set_header Remote-User "";
          '';
        });
      }) cfg.proxy;
    })
  ]);
}
