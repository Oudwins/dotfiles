{ configLib, inputs, lib, ... }:

{
  imports = [
    (configLib.relativeToRoot "modules/nixos/hardware/disko/encryptedDisko.nix")
    (configLib.relativeToRoot "modules/nixos/core/remote-unlock.nix")
    (configLib.relativeToRoot "modules/nixos/core/server-base")
    (configLib.relativeToRoot "roles/server")
    (configLib.relativeToRoot "modules/nixos/core/sops")

    # users
    (configLib.relativeToRoot "users/root/nixos.nix")
    (configLib.relativeToRoot "users/tmx/server.nix")
    inputs.disko.nixosModules.disko

    (configLib.relativeToRoot "modules/nixos/core/tailscale.nix")
    (configLib.relativeToRoot "modules/nixos/services/ssl/cloudflare")
  ] ++ lib.optional (builtins.pathExists ./hardware-configuration.nix)
    ./hardware-configuration.nix;

  sops.defaultSopsFile = configLib.secretFile "sops/hosts/rizos.yaml";

  # nixos-anywhere generates the hardware configuration before installation.
  nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";
  disko.devices.disk.main.device = "/dev/nvme0n1";

  my.server.location = "r";
  time.timeZone = "Europe/Madrid";

  networking = {
    hostName = "rizos";
    useNetworkd = true;
    useDHCP = false;
  };

  boot = {
    loader.systemd-boot.enable = true;
    loader.efi.canTouchEfiVariables = true;

    # NIC drivers are not necessarily included by nixos-generate-config.
    initrd.availableKernelModules = [ "r8169" "e1000e" "igb" "igc" ];
  };

  my.server.security.level = "intranet";

  system.stateVersion = "26.05";
}
