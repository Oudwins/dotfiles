{ config, pkgs, configLib, lib, inputs, ... }@args:

let
  d = config.my.domains;
  getEmailDomain = email: builtins.elemAt (lib.splitString "@" email) 1;

  mkPasswordSecretName = email: "mail/passwords/${email}";

  mkNoReplyEmail = domain: "no-reply@${domain}";
  mkNoReplyMailConfig = { domain, replyTo ? null, }:
    let
      email = mkNoReplyEmail domain;
      file_path = mkPasswordSecretName email;
    in {
      email = email;
      inherit replyTo;
      smtp = {
        host = "mail.${d.main}";
        port = 465;
        secure = "ssl";
        passwordFile = config.sops.secrets."${file_path}".path;
      };
    };

in {
  imports = [
    (configLib.relativeToRoot "modules/nixos/core/server-base")
    inputs.simple-nixos-mailserver.nixosModules.default
    # Secrets
    (configLib.relativeToRoot "modules/nixos/core/sops")
    # TYPE OF MACHINE
    (configLib.relativeToRoot "roles/server")
    ./hardware-configuration.nix
    (configLib.relativeToRoot "roles/hetzner")
    # (configLib.relativeToRoot "modules/nixos/core/tailscale.nix")

    # USERS
    (configLib.relativeToRoot "users/tmx/server.nix")
    (configLib.relativeToRoot "users/simone/nixos.nix")
    (configLib.relativeToRoot
      "modules/nixos/services/wordpress/lightspeed-proxy.nix")

    # Services
    (configLib.relativeToRoot "modules/nixos/core/restic-backup.nix")

  ];

  sops.defaultSopsFile = configLib.secretFile "sops/hosts/iss.yaml";

  # SERVER OPTIONS
  my.server.location = "iss";
  my.server.security.level = "public";
  networking.hostName = "iss-prod"; # Define your hostname.
  time.timeZone = "Europe/Madrid";

  # This value determines the NixOS release from which the default
  # settings for stateful data, like file locations and database versions
  # on your system were taken. It‘s perfectly fine and recommended to leave
  # this value at the release version of the first install of this system.
  # Before changing this value read the documentation for this option
  # (e.g. man configuration.nix or on https://nixos.org/nixos/options.html).
  system.stateVersion = "24.05"; # Did you read the comment?

  sops.secrets = let
    passwordSecretNames =
      map mkPasswordSecretName (lib.attrNames config.mailserver.accounts);
    mailPasswordSecrets = lib.listToAttrs (map (name: {
      name = name;
      value = {
        owner = "nobody";
        group = "nogroup";
        mode = "0440";
      };
    }) (passwordSecretNames));

  in {
    "cloudflare/cert_credentials" = { owner = "root"; };
    "wordpress_env_file/hfcom" = { owner = "root"; };
    "wordpress_preview_basic_auth" = {
      owner = "nginx";
      group = "nginx";
    };
  } // mailPasswordSecrets // {
    # Shared with the hosts whose services send as this account.
    ${mkPasswordSecretName config.my.smtp.from} =
      mailPasswordSecrets.${mkPasswordSecretName config.my.smtp.from} // {
        sopsFile = configLib.secretFile "sops/shared/mail.yaml";
      };
  };

  my.wordpressLiteSpeedProxy = {
    enable = true;
    bindAddress = "127.0.0.1";
    acmeEmail = config.my.email;
    hostAcme = {
      enable = true;
      environmentFile = config.sops.secrets."cloudflare/cert_credentials".path;
    };

    sites.heike-staging = {
      domain = "stage.${d.heike}";
      proxyPort = 18080;
      adminPort = 17080;
      phpMyAdminPort = 8080;
      secretEnvFile =
        config.sops.secrets."wordpress_env_file/hfcom".path;
      protected = {
        enabled = true;
        passwordFile = config.sops.secrets."wordpress_preview_basic_auth".path;
      };

      wordpress = {
        siteTitle = "Heike freire staging";
        adminUser = "admin";
        adminEmail = config.my.email;
      };

      mail = mkNoReplyMailConfig { domain = d.heike; };

      database = {
        name = "hfcom";
        user = "hfcom";
      };
    };

    sites.heike = {
      domain = d.heike;
      backup.enable = true;
      proxyPort = 18081;
      adminPort = 17081;
      phpMyAdminPort = 8081;
      secretEnvFile =
        config.sops.secrets."wordpress_env_file/hfcom".path;

      wordpress = {
        siteTitle = "Heike freire";
        adminUser = "admin";
        adminEmail = config.my.email;
      };

      mail = mkNoReplyMailConfig {
        domain = d.heike;
        # replyTo = "secretaria@${d.heike}";
      };

      database = {
        name = "hfcom";
        user = "hfcom";
      };
    };

  };

  security.acme.certs."mail.${d.main}" = { domain = "mail.${d.main}"; };

  security.acme.acceptTerms = lib.mkDefault true;
  security.acme.defaults.email = lib.mkDefault config.my.email;
  security.acme.defaults.dnsProvider = lib.mkDefault "cloudflare";
  security.acme.defaults.environmentFile =
    lib.mkDefault config.sops.secrets."cloudflare/cert_credentials".path;
  security.acme.defaults.dnsPropagationCheck = lib.mkDefault true;

  networking.firewall.allowedTCPPorts = [ 25 143 465 587 993 ];

  mailserver = {
    enable = true;
    enableManageSieve = true; # for rules
    stateVersion = 5;
    enableNixpkgsReleaseCheck = false;
    fqdn = "mail.${d.main}";
    domains = lib.unique
      (map getEmailDomain (lib.attrNames config.mailserver.accounts));

    mailboxes.Trash = {
      auto = "subscribe";
      special_use = "\\Trash";
    };
    mailboxes.Junk = {
      auto = "subscribe";
      special_use = "\\Junk";
    };

    x509.useACMEHost = "mail.${d.main}";

    # For connecting with gmail
    enablePop3Ssl = true;

    # full text search & don't store indexes with emails
    indexDir = "/var/lib/dovecot/indices";
    fullTextSearch = {
      enable = true;
      # index new email as they arrive
      autoIndex = true;
    };

    accounts = let
      wordpressMailEmails = lib.unique (map (item: item.value.mail.email)
        (lib.attrsToList config.my.wordpressLiteSpeedProxy.sites));
      wordpressMailAccounts = lib.listToAttrs (map (email: {
        name = email;
        value = {
          passwordFile =
            config.sops.secrets."${mkPasswordSecretName email}".path;
        };
      }) wordpressMailEmails);
    in {
      "postmaster@${d.main}" = {
        aliases = [ "abuse@${d.main}" "webmaster@${d.main}" ];
        passwordFile = config.sops.secrets.${
            mkPasswordSecretName "postmaster@${d.main}"
          }.path;
      };
      # main
      "hola@${d.main}" = {
        passwordFile =
          config.sops.secrets.${mkPasswordSecretName "hola@${d.main}"}.path;
      };
      "team@${d.main}" = {
        passwordFile =
          config.sops.secrets.${mkPasswordSecretName "team@${d.main}"}.path;
      };

      # TM
      "tm@${config.my.domain}" = {
        passwordFile =
          config.sops.secrets.${mkPasswordSecretName "tm@${config.my.domain}"}.path;
      };
      "wall@${config.my.domain}" = {
        passwordFile = config.sops.secrets.${
            mkPasswordSecretName "wall@${config.my.domain}"
          }.path;
      };
      "void@${config.my.domain}" = {
        passwordFile = config.sops.secrets.${
            mkPasswordSecretName "void@${config.my.domain}"
          }.path;
      };

      # Service notifications (vaultwarden, gitea, grafana, ...)
      ${config.my.smtp.from} = {
        passwordFile = config.sops.secrets.${mkPasswordSecretName config.my.smtp.from}.path;
      };

      # Heike
      "secretaria@${d.heike}" = {
        aliases = [ "tristanmayo@${d.heike}" ];
        passwordFile = config.sops.secrets.${
            mkPasswordSecretName "secretaria@${d.heike}"
          }.path;
      };

      "academia@${d.heike}" = {
        passwordFile = config.sops.secrets.${
            mkPasswordSecretName "academia@${d.heike}"
          }.path;
      };

      # path
      "contact@${d.path}" = {
        passwordFile =
          config.sops.secrets.${mkPasswordSecretName "contact@${d.path}"}.path;
        catchAll = [ d.path ];
      };
      "matilda@${d.path}" = {
        passwordFile =
          config.sops.secrets.${mkPasswordSecretName "matilda@${d.path}"}.path;
      };
      # un
      "contact@${d.un}" = {
        passwordFile =
          config.sops.secrets.${mkPasswordSecretName "contact@${d.un}"}.path;
      };

    } // wordpressMailAccounts;

  };
}
