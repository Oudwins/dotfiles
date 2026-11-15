# Single source of truth for per-host values (replaces the old servers `vars`).
# Defaults live here; private values come from nix-secrets soft secrets
# (merged by lib/soft.nix); a host file overrides either with a plain assignment.
{ config, lib, ... }:

let
  inherit (lib) mkOption types;

  str = default: mkOption {
    type = types.str;
    inherit default;
  };
  required = mkOption { type = types.str; };
  subdomains = lib.mapAttrs (_: default: { subdomain = str default; });
in
{
  options.my = {
    domain = required;
    email = required;
    # Private domains a host serves (websites, mail), by a neutral key, e.g.
    # "postmaster@${config.my.domains.main}". Values come from soft secrets.
    domains = mkOption {
      type = types.attrsOf types.str;
      default = { };
    };
    username = str "tmx";
    initialPassword = str "nixos";

    networking = {
      sshMasterKeyPath = str "/etc/ssh/ssh_master_key";
    };

    providers.openrouter.baseURL = str "https://openrouter.ai/api/v1";

    services = {
      baseDataDir = str "/var/lib";
      media = subdomains {
        prowlarr = "prowlarr";
        lidarr = "lidarr";
        radarr = "radarr";
        sonarr = "sonarr";
        bazarr = "bazarr";
        jellyseerr = "jellyseerr";
        jellyfin = "media";
        navidrome = "navidrome";
        audiobookshelf = "books";
      };
    }
    // subdomains {
      nextcloud = "cloud";
      onlyoffice = "office";
      transmission = "tors";
      paperless = "paper";
      shiori = "shiori";
      freshrss = "rss";
      rssfeeds = "feeds";
      syncthing = "syncthing";
      grafana = "grafana";
      ntfy = "ntfy";
      vaultwarden = "warden";
      solidtime = "time";
      immich = "immich";
      mealie = "mealie";
      memos = "memos";
      executor = "executor";
      firecrawl = "firecrawl";
      wifiControl = "wifi";
      gitea = "gitea";
      manager = "manager";
      couchdb = "couchdb";
    };

    # How `just deploy <host>` reaches this machine. null = not deployable remotely.
    deploy = {
      host = mkOption {
        type = types.nullOr types.str;
        default = null;
      };
      user = str "root";
      port = mkOption {
        type = types.port;
        default = builtins.head (lib.attrByPath [ "services" "openssh" "ports" ] [ 22 ] config);
      };
      buildOnTarget = mkOption {
        type = types.bool;
        default = false;
      };
    };
  };
}
