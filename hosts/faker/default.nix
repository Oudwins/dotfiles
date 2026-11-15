# Edit this configuration file to define what should be installed on
# your system.  Help is available in the configuration.nix(5) man page
# and in the NixOS manual (accessible by running ‘nixos-help’).

{ config, pkgs, configLib, lib, inputs, ... }:

{
  imports = [
    (configLib.relativeToRoot "modules/nixos/core/server-base")
    # Secrets
    (configLib.relativeToRoot "modules/nixos/core/sops")
    # TYPE OF MACHINE
    (configLib.relativeToRoot "roles/server")
    (configLib.relativeToRoot
      "roles/local-vm/hardware-configuration.nix")
    (configLib.relativeToRoot "roles/local-vm")

    # USERS
    (configLib.relativeToRoot "users/tmx/server.nix")

    # Services
    (configLib.relativeToRoot "modules/nixos/core/restic-backup.nix")
    (configLib.relativeToRoot "modules/nixos/core/tailscale.nix")

    (configLib.relativeToRoot "modules/nixos/services/ssl/cloudflare")
    (configLib.relativeToRoot "modules/nixos/services/nextcloud")
    # (configLib.relativeToRoot "modules/nixos/services/transmission")
    (configLib.relativeToRoot "modules/nixos/services/syncthing")
    (configLib.relativeToRoot "modules/nixos/services/paperless")
    (configLib.relativeToRoot "modules/nixos/services/metrics")
    (configLib.relativeToRoot "modules/nixos/services/shiori")
    (configLib.relativeToRoot "modules/nixos/services/freshRSS")
    (configLib.relativeToRoot "modules/nixos/services/vaultwarden")
    (configLib.relativeToRoot "modules/nixos/services/dashboard")
    (configLib.relativeToRoot "modules/nixos/services/timetracking/solidtime")
    (configLib.relativeToRoot "modules/nixos/services/media-server")
    (configLib.relativeToRoot "modules/nixos/services/immich")
    (configLib.relativeToRoot "modules/nixos/services/gitea")
    # (configLib.relativeToRoot "modules/nixos/services/obsidian_remote")
    (configLib.relativeToRoot "modules/nixos/services/couchdb")
    (configLib.relativeToRoot "modules/nixos/services/mealie")
    (configLib.relativeToRoot "modules/nixos/services/memos")

    # Accounting container
    (configLib.relativeToRoot "modules/nixos/services/accounting")
  ];

  sops.defaultSopsFile = configLib.secretFile "sops/hosts/faker.yaml";

  # Database passwords and app keys for the containers, as env files.
  sops.secrets."memos/env_file" = { };
  sops.secrets."solidtime/env_file" = { };
  sops.secrets."solidtime/db_env_file" = { };
  sops.secrets."shiori/env_file" = { };
  my.memos.environmentFile = config.sops.secrets."memos/env_file".path;
  my.solidtime.environmentFile = config.sops.secrets."solidtime/env_file".path;
  my.solidtime.dbEnvironmentFile = config.sops.secrets."solidtime/db_env_file".path;
  services.shiori.environmentFile = config.sops.secrets."shiori/env_file".path;

  # SERVER OPTIONS
  my.server.location = "f";
  my.server.security.level = "intranet";
  networking.hostName = "faker"; # Define your hostname.
  time.timeZone = "Europe/Madrid";

  # This value determines the NixOS release from which the default
  # settings for stateful data, like file locations and database versions
  # on your system were taken. It‘s perfectly fine and recommended to leave
  # this value at the release version of the first install of this system.
  # Before changing this value read the documentation for this option
  # (e.g. man configuration.nix or on https://nixos.org/nixos/options.html).
  system.stateVersion = "24.05"; # Did you read the comment?

}
