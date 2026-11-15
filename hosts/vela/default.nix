{ config, configLib, inputs, lib, ... }@args:

{
  imports = [
    ./hardware-configuration.nix
    (configLib.relativeToRoot "modules/nixos/core/server-base")
    (configLib.relativeToRoot "modules/nixos/core/sops")
    (configLib.relativeToRoot "roles/server")

    # Disk
    inputs.disko.nixosModules.disko
    (configLib.relativeToRoot "modules/nixos/hardware/disko/simpleDisko.nix")
    {
      _module.args = {
        disk = "/dev/nvme0n1";
        inherit lib;
        specialArgs = args;
      };
    }

    # Users
    (configLib.relativeToRoot "users/tmx/server.nix")

    # Services
    (configLib.relativeToRoot "modules/nixos/core/tailscale.nix")
    (configLib.relativeToRoot "modules/nixos/services/ssl/cloudflare")
    (configLib.relativeToRoot "modules/nixos/services/hermes-agent")
    (configLib.relativeToRoot "modules/nixos/services/executor")
    (configLib.relativeToRoot "modules/nixos/services/firecrawl")
    (configLib.relativeToRoot "modules/nixos/services/matrix")
    (configLib.relativeToRoot "modules/nixos/services/matrix/whatsapp.nix")
    inputs.hermes-agent.nixosModules.default
  ];

  sops.defaultSopsFile = configLib.secretFile "sops/hosts/vela.yaml";

  services.executor = { enable = true; };
  sops.secrets."firecrawl/env_file" = { };
  services.firecrawl = {
    enable = true;
    environmentFile = config.sops.secrets."firecrawl/env_file".path;
  };

  my.hermes-agent.matrix = {
    homeserver = "https://matrix.${config.my.domain}";
    allowedUsers = [ "@tmx:${config.my.matrix.domain}" ];
    # homeRoom comes from soft secrets.
    allowedRooms = [ config.my.hermes-agent.matrix.homeRoom ];
  };
  my.matrix.domain = "matrix.${config.my.domain}";
  my.matrix.whatsapp.userId = "@tmx:${config.my.matrix.domain}";
  my.matrix.whatsapp.senderLocalpart = "eDfImKwIBgZB35A1KVuWJhCdJlMltcI9";
  my.server.location = "vela";
  my.server.security.level = "intranet";
  networking.hostName = "vela";
  time.timeZone = "Europe/Madrid";

  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  system.stateVersion = "26.05";
}
