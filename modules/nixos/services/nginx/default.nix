{
  config,
  lib,
  pkgs,
  ...
}:

{
  users.users.nginx = {
    isSystemUser = true;
    group = "nginx";
    extraGroups = [
      "acme"
    ];
  };
  users.groups.nginx = {
  };
  services.nginx = {
    enable = true;
    # recommendedProxySettings = true; # warning will break nextcloud top level domain
    # recommendedOptimisation = true;
    recommendedTlsSettings = true;
    recommendedGzipSettings = true;

  };
}
