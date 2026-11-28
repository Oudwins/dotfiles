# The *arr apps behind SSO with their own login off. Their APIs (each other,
# Jellyseerr, recyclarr, phone apps) and calendar feeds skip SSO and keep the
# API key.
{ config, lib, ... }:

let
  inherit (config.my.sso) enabledFor;
  host = service: "${config.my.services.media.${service}.subdomain}.${config.my.server.location}.${config.my.domain}";
  apps = {
    sonarr = [ "/feed" ];
    radarr = [ "/feed" ];
    lidarr = [ "/feed" ];
    # Indexer proxy endpoints the other apps search and download through.
    prowlarr = [ "~ ^/[0-9]+/(api|download)" ];
    # Bazarr's settings aren't Nix-managed: set Settings > General > Address to
    # 127.0.0.1 before setting Authentication to None.
    bazarr = [ ];
  };
  servarr = [
    "sonarr"
    "radarr"
    "lidarr"
    "prowlarr"
  ];
in
{
  imports = [ ../sso ];

  my.sso.proxy = lib.mapAttrs' (
    service: skip:
    lib.nameValuePair (host service) {
      inherit service;
      skipLocations = [ "/api" ] ++ skip;
    }
  ) (lib.filterAttrs (service: _: enabledFor service) apps);

  services =
    lib.genAttrs servarr (
      service:
      lib.mkIf (enabledFor service) {
        settings = {
          auth.method = "External";
          # Tailscale accepts all tailnet traffic, so with its login off the app
          # must only be reachable through nginx.
          server.bindaddress = "127.0.0.1";
        };
      }
    )
    // {
      nginx.virtualHosts = lib.listToAttrs (
        map (
          service:
          lib.nameValuePair (host service) {
            locations."/".proxyPass = lib.mkForce "http://127.0.0.1:${toString config.services.${service}.settings.server.port}";
          }
        ) (lib.filter enabledFor servarr)
      );
    };
}
