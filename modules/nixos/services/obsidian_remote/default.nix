{
  config,
  configLib,
  lib,
  pkgs,
  ...
}:
let
  # Never could get this to work.....
  image = "ghcr.io/sytone/obsidian-remote:latest";
in
{
  imports = [
    (configLib.relativeToRoot "modules/nixos/services/containers")
  ];

  systemd.tmpfiles.rules =
    let
      # Careful if we update this we will also need to change it in the obsidian module. Because I was lazy
      user = "root";
      group = "root";
      dataDir = "/srv/obsidian_remote/config";
    in
    [
      #Type Path                      Mode UID     GID      Age Argument
      "d    ${dataDir}                0755 ${user} ${group} -   -"
    ];
  virtualisation.oci-containers.containers.obsidianremote = {
    image = image;
    # autoStart = true;
    serviceName = "obsidianremote";
    ports = [
      "8181:8080"
    ];
    volumes = [
      "/srv/syncthing/notes:/vaults"
      "/srv/obsidian_remote/config:/config"
    ];
    # environment = {
    # };
  };

}
