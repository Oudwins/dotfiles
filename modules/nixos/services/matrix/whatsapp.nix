{ config, lib, pkgs, ... }:

let
  host = config.my.matrix.domain;
  cfg = config.my.matrix.whatsapp;
  inherit (cfg) userId;
  port = 29318;
  botUsername = "whatsappbot";
  ghostPrefix = "whatsapp_";
  registrationGroup = "matrix-appservices";
  registrationDir = "/run/matrix-appservices";
  registration = config.sops.templates."mautrix-whatsapp-registration.yaml";
  doublePuppetRegistration = config.sops.templates."mautrix-whatsapp-double-puppet.yaml";
in
{
  imports = [ ./backup.nix ];

  options.my.matrix.whatsapp = {
    userId = lib.mkOption {
      type = lib.types.str;
      description = "Matrix account allowed to link and use WhatsApp.";
    };
    senderLocalpart = lib.mkOption {
      type = lib.types.str;
      default = "whatsapp_appservice";
      description = "Appservice sender identity, distinct from the encryption bot.";
    };
  };

  config = {
    sops.secrets = lib.genAttrs [
      "matrix/whatsapp/as_token"
      "matrix/whatsapp/hs_token"
      "matrix/whatsapp/pickle_key"
      "matrix/whatsapp/double_puppet_as_token"
      "matrix/whatsapp/double_puppet_hs_token"
    ]
      (_: { });

    sops.templates."mautrix-whatsapp.env" = {
      restartUnits = [ "mautrix-whatsapp.service" ];
      content = ''
        ENCRYPTION_PICKLE_KEY=${config.sops.placeholder."matrix/whatsapp/pickle_key"}
        DOUBLE_PUPPET_AS_TOKEN=${config.sops.placeholder."matrix/whatsapp/double_puppet_as_token"}
      '';
    };

    sops.templates."mautrix-whatsapp-registration.yaml" = {
      group = registrationGroup;
      mode = "0440";
      restartUnits = [ "tuwunel.service" "mautrix-whatsapp.service" ];
      content = builtins.toJSON {
        id = "whatsapp";
        url = "http://127.0.0.1:${toString port}";
        as_token = config.sops.placeholder."matrix/whatsapp/as_token";
        hs_token = config.sops.placeholder."matrix/whatsapp/hs_token";
        sender_localpart = cfg.senderLocalpart;
        rate_limited = false;
        receive_ephemeral = true;
        "io.element.msc4190" = true;
        namespaces.users = [
          {
            regex = "^${lib.escapeRegex "@${botUsername}:${host}"}$";
            exclusive = true;
          }
          {
            regex = "^@${ghostPrefix}.*:${lib.escapeRegex host}$";
            exclusive = true;
          }
        ];
      };
    };

    sops.templates."mautrix-whatsapp-double-puppet.yaml" = {
      group = registrationGroup;
      mode = "0440";
      restartUnits = [ "tuwunel.service" "mautrix-whatsapp.service" ];
      content = builtins.toJSON {
        id = "whatsapp-double-puppet";
        url = null;
        as_token = config.sops.placeholder."matrix/whatsapp/double_puppet_as_token";
        hs_token = config.sops.placeholder."matrix/whatsapp/double_puppet_hs_token";
        sender_localpart = "whatsapp_double_puppet";
        rate_limited = false;
        namespaces.users = [
          {
            regex = "^${lib.escapeRegex userId}$";
            exclusive = false;
          }
        ];
      };
    };

    users.groups.${registrationGroup} = { };
    systemd.tmpfiles.rules = [
      "d ${registrationDir} 0750 root ${registrationGroup} -"
      "L+ ${registrationDir}/whatsapp.yaml - - - - ${registration.path}"
      "L+ ${registrationDir}/double-puppet.yaml - - - - ${doublePuppetRegistration.path}"
    ];
    services.matrix-tuwunel.settings.global.appservice_dir = registrationDir;
    systemd.services.tuwunel = {
      after = [ "systemd-tmpfiles-setup.service" ];
      serviceConfig.SupplementaryGroups = [ registrationGroup ];
    };
    systemd.services.mautrix-whatsapp = {
      requires = [ "tuwunel.service" ];
      serviceConfig.SupplementaryGroups = [ registrationGroup ];
      # Supply the native module's registration before it can generate random
      # tokens. It then reads both tokens from this same SOPS-rendered source.
      preStart = lib.mkBefore ''
        ${pkgs.coreutils}/bin/install -m 0600 ${registration.path} \
          /var/lib/mautrix-whatsapp/whatsapp-registration.yaml
      '';
    };

    services.mautrix-whatsapp = {
      enable = true;
      # Keep the WhatsApp protocol current without updating unrelated packages.
      # Use pure-Go crypto instead of the deprecated libolm dependency.
      package = (pkgs.mautrix-whatsapp.override { withGoolm = true; }).overrideAttrs (_: rec {
        version = "26.09";
        tag = "v0.2609.0";
        src = pkgs.fetchFromGitHub {
          owner = "mautrix";
          repo = "whatsapp";
          inherit tag;
          hash = "sha256-u+Ck8ckCbFu+Q7pVM7T05InqDq7NknqYOAb0wis93OU=";
        };
        vendorHash = "sha256-Kpireqd1Cll0XZvnouUJV4BJYJRWPlhQRDhLekujg60=";
        ldflags = [ "-s" "-w" "-X" "main.Tag=${tag}" ];
      });
      environmentFile = config.sops.templates."mautrix-whatsapp.env".path;
      serviceDependencies = [ "tuwunel.service" ];
      settings = {
        homeserver = {
          address = "http://127.0.0.1:${toString (lib.head config.services.matrix-tuwunel.settings.global.port)}";
          domain = host;
          software = "standard";
        };
        appservice = {
          address = "http://127.0.0.1:${toString port}";
          hostname = "127.0.0.1";
          inherit port;
          bot.username = botUsername;
          username_template = "${ghostPrefix}{{.}}";
          ephemeral_events = true;
        };
        bridge = {
          relay.enabled = false;
          permissions = {
            "*" = "block";
            "${userId}" = "admin";
          };
        };
        double_puppet.secrets."${host}" = "as_token:$DOUBLE_PUPPET_AS_TOKEN";
        encryption = {
          allow = true;
          default = true;
          require = true;
          self_sign = true;
          appservice = false;
          msc4190 = true;
          pickle_key = "$ENCRYPTION_PICKLE_KEY";
        };
        network = {
          enable_status_broadcast = false;
          history_sync = {
            max_initial_conversations = 5;
            request_full_sync = false;
          };
        };
        backfill = {
          enabled = true;
          max_initial_messages = 50;
          queue.enabled = false;
        };
        matrix.federate_rooms = false;
        provisioning.shared_secret = "disable";
      };
    };

    services.matrix-tuwunel.settings.global.max_request_size = 100 * 1024 * 1024;
    services.nginx.virtualHosts."${host}".locations."/_matrix/".extraConfig = ''
      client_max_body_size 100m;
    '';
  };
}
