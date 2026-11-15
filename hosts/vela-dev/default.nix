{ configLib, inputs, ... }:

{
  imports = [
    (configLib.relativeToRoot "modules/nixos/core/server-base")
    (configLib.relativeToRoot "modules/nixos/core/sops")
    (configLib.relativeToRoot "roles/server")
    (configLib.relativeToRoot
      "roles/local-vm/hardware-configuration.nix")
    (configLib.relativeToRoot "roles/local-vm")
    (configLib.relativeToRoot "modules/nixos/core/tailscale.nix")

    # Users
    (configLib.relativeToRoot "users/tmx/server.nix")

    # modules
    (configLib.relativeToRoot "modules/nixos/services/ssl/cloudflare")
    (configLib.relativeToRoot "modules/nixos/services/hermes-agent")
    (configLib.relativeToRoot "modules/nixos/services/executor")
    (configLib.relativeToRoot "modules/nixos/services/matrix")
    inputs.hermes-agent.nixosModules.default
  ];

  sops.defaultSopsFile = configLib.secretFile "sops/hosts/vela-dev.yaml";

  services.executor = { enable = true; };

  my.server.location = "vela-dev";
  my.server.security.level = "intranet";
  networking.hostName = "vela-dev";
  time.timeZone = "Europe/Madrid";

  system.stateVersion = "26.05";
}
