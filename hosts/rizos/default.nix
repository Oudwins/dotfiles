{ config, configLib, inputs, outputs, lib, ... }:

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
    (configLib.relativeToRoot "modules/nixos/services/dashboard")

    # Coding agents: LLM proxy, Executor, Agent Vault, agent CLIs and T3 Code
    inputs.home-manager.nixosModules.home-manager
    (configLib.relativeToRoot "roles/agents.nix")
    # Serves them to agents on nixos as <subdomain>.r.<domain>
    (configLib.relativeToRoot "modules/nixos/services/remote-agents")
    (configLib.relativeToRoot "modules/nixos/core/dotfiles-bootstrap.nix")
    ./home.nix
  ] ++ lib.optional (builtins.pathExists ./hardware-configuration.nix)
    ./hardware-configuration.nix;

  sops.defaultSopsFile = configLib.secretFile "sops/hosts/rizos.yaml";
  # Decrypts tmx's home-manager secrets.
  sops.secrets."users/tmx/age_key".owner = config.my.username;
  # tmx's default SSH key (e.g. for GitHub); its public key is in a comment
  # above it in rizos.yaml.
  sops.secrets."users/tmx/ssh_key" = {
    owner = config.my.username;
    path = "${config.users.users.${config.my.username}.home}/.ssh/id_ed25519";
  };

  home-manager = {
    useGlobalPkgs = true;
    useUserPackages = true;
    backupFileExtension = "backup";
    extraSpecialArgs = { inherit inputs outputs configLib; };
  };
  # Agent Vault, Executor and T3 Code are user services; run them without a login.
  users.users.${config.my.username}.linger = true;

  agents.executor.cloudflare.enable = true;

  # Root decrypts the proxy's keys with the master key, not tmx's SSH key.
  services.cli-proxy-api.sshKeyFile = config.my.networking.sshMasterKeyPath;
  services.cli-proxy-api.secretsFile = configLib.secretFile "sops/shared/cli-proxy-api-personal.yaml";
  # Its configuration is a Stow-managed file.
  systemd.services.cli-proxy-api = {
    wants = [ "dotfiles-bootstrap.service" ];
    after = [ "dotfiles-bootstrap.service" ];
  };

  # DNS points *.r.<domain> at the tailnet address; the services stay off the LAN.
  networking.firewall.interfaces.tailscale0.allowedTCPPorts = [ 443 ];

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
