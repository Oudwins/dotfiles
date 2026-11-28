# Edit this configuration file to define what should be installed on
# your system.  Help is available in the configuration.nix(5) man page
# and in the NixOS manual (accessible by running ‘nixos-help’).

{ config
, pkgs
, configLib
, lib
, inputs
, ...
}@args:

let
  d = config.my.domains;
  getEmailDomain = email: builtins.elemAt (lib.splitString "@" email) 1;
  mkPasswordSecretName = email: "mail/passwords/${email}";
  mkNoReplyEmail = domain: "no-reply@${domain}";
  mkNoReplyMailConfig = (
    domain:
    let
      email = mkNoReplyEmail domain;
      file_path = mkPasswordSecretName email;
    in
    {
      email = email;
      smtp = {
        host = "mail.${d.main}";
        port = 465;
        secure = "ssl";
        passwordFile = config.sops.secrets."${file_path}".path;
      };
    }
  );
in
{
  imports = [
    (configLib.relativeToRoot "modules/nixos/core/server-base")
    inputs.simple-nixos-mailserver.nixosModules.default
    # Secrets
    (configLib.relativeToRoot "modules/nixos/core/sops")
    # TYPE OF MACHINE
    (configLib.relativeToRoot "roles/server")
    (configLib.relativeToRoot "roles/local-vm/hardware-configuration.nix")
    (configLib.relativeToRoot "roles/local-vm")
    (configLib.relativeToRoot "modules/nixos/core/tailscale.nix")

    # USERS
    (configLib.relativeToRoot "users/tmx/server.nix")
    (configLib.relativeToRoot "users/simone/nixos.nix")
    (configLib.relativeToRoot "modules/nixos/services/wordpress/lightspeed-proxy.nix")

    # Services
    (configLib.relativeToRoot "modules/nixos/core/restic-backup.nix")

  ];

  sops.defaultSopsFile = configLib.secretFile "sops/hosts/iss-dev.yaml";

  # SERVER OPTIONS
  my.server.location = "iss-dev";
  my.server.security.level = "intranet";
  networking.hostName = "iss-dev"; # Define your hostname.
  time.timeZone = "Europe/Madrid";

  # This value determines the NixOS release from which the default
  # settings for stateful data, like file locations and database versions
  # on your system were taken. It‘s perfectly fine and recommended to leave
  # this value at the release version of the first install of this system.
  # Before changing this value read the documentation for this option
  # (e.g. man configuration.nix or on https://nixos.org/nixos/options.html).
  system.stateVersion = "24.05"; # Did you read the comment?

  sops.secrets =
    let
      passwordSecretNames = map mkPasswordSecretName (lib.attrNames config.mailserver.accounts);
      mailPasswordSecrets = lib.listToAttrs (
        map
          (name: {
            name = name;
            value = {
              owner = "nobody";
              group = "nogroup";
              mode = "0440";
            };
          })
          passwordSecretNames
      );
    in
    {
      "cloudflare/cert_credentials" = {
        owner = "root";
      };
      "wordpress_env_file" = {
        owner = "root";
      };
      "wordpress_preview_basic_auth" = {
        owner = "nginx";
        group = "nginx";
      };
    }
    // mailPasswordSecrets;

  my.wordpressLiteSpeedProxy = {
    enable = true;
    bindAddress = "127.0.0.1";
    acmeEmail = config.my.email;
    hostAcme = {
      enable = true;
      environmentFile = config.sops.secrets."cloudflare/cert_credentials".path;
    };

    sites.test1 = {
      domain = "test1.iss.${config.my.domain}";
      proxyPort = 18080;
      adminPort = 17080;
      phpMyAdminPort = 8080;
      secretEnvFile = config.sops.secrets."wordpress_env_file".path;
      backup.enable = true;

      wordpress = {
        siteTitle = "ISS Dev WordPress";
        adminUser = "admin";
        adminEmail = config.my.email;
      };

      mail = mkNoReplyMailConfig "test1.iss.${config.my.domain}";

      protected = {
        enabled = true;
        passwordFile = config.sops.secrets."wordpress_preview_basic_auth".path;
      };

      database = {
        name = "wordpress";
        user = "wordpress";
      };
    };

    sites.test2 = {
      domain = "test2.iss.${config.my.domain}";
      proxyPort = 18081;
      adminPort = 17081;
      phpMyAdminPort = 8081;
      secretEnvFile = config.sops.secrets."wordpress_env_file".path;

      wordpress = {
        siteTitle = "ISS Dev WordPress 2";
        adminUser = "admin";
        adminEmail = config.my.email;
      };

      mail = mkNoReplyMailConfig "test2.iss.${config.my.domain}";

      database = {
        name = "wordpress";
        user = "wordpress";
      };
    };
  };

  security.acme.certs."mail.${d.main}" = {
    domain = "mail.${d.main}";
  };

  security.acme.acceptTerms = lib.mkDefault true;
  security.acme.defaults.email = lib.mkDefault config.my.email;
  security.acme.defaults.dnsProvider = lib.mkDefault "cloudflare";
  security.acme.defaults.environmentFile =
    lib.mkDefault
      config.sops.secrets."cloudflare/cert_credentials".path;

  networking.firewall.allowedTCPPorts = [
    25
    143
    465
    587
    993
  ];

  # nixos-mailserver requires a local DNSSEC-validating resolver
  services.unbound.enable = true;

  mailserver = {
    enable = true;
    stateVersion = 5;
    enableNixpkgsReleaseCheck = false;
    fqdn = "mail.${d.main}";
    domains = lib.unique (map getEmailDomain (lib.attrNames config.mailserver.accounts));
    mailboxes.Junk = {
      auto = "subscribe";
      special_use = "\\Junk";
    };
    x509.useACMEHost = "mail.${d.main}";

    # full text search & don't store indexes with emails
    indexDir = "/var/lib/dovecot/indices";
    fullTextSearch = {
      enable = true;
      # index new email as they arrive
      autoIndex = true;
    };

    accounts =
      let
        wordpressMailEmails = lib.unique (
          map (item: item.value.mail.email) (lib.attrsToList config.my.wordpressLiteSpeedProxy.sites)
        );
        wordpressMailAccounts = lib.listToAttrs (
          map
            (email: {
              name = email;
              value = {
                passwordFile = config.sops.secrets."${mkPasswordSecretName email}".path;
              };
            })
            wordpressMailEmails
        );
      in
      {
        "postmaster@${d.main}" = {
          aliases = [
            "abuse@${d.main}"
            "webmaster@${d.main}"
          ];
          passwordFile = config.sops.secrets.${mkPasswordSecretName "postmaster@${d.main}"}.path;
        };
      }
      // wordpressMailAccounts;
  };
}
