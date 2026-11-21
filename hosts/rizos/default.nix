{ config, configLib, inputs, outputs, lib, ... }:

let
  hm = config.home-manager.users.${config.my.username};
  # Coding agents on nixos reach these over the tailnet as <subdomain>.r.<domain>.
  proxied = {
    # Matches home-files/tmx/.cli-proxy-api/config.yaml.
    llmproxy = 8317;
    executor = hm.services.executor.port;
    t3code = hm.services.t3code.port;
  };
in
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

    # Coding agents: LLM proxy, Executor, Agent Vault, agent CLIs and T3 Code
    inputs.home-manager.nixosModules.home-manager
    (configLib.relativeToRoot "roles/agents.nix")
    (configLib.relativeToRoot "modules/nixos/core/dotfiles-bootstrap.nix")
    ./home.nix
  ] ++ lib.optional (builtins.pathExists ./hardware-configuration.nix)
    ./hardware-configuration.nix;

  sops.defaultSopsFile = configLib.secretFile "sops/hosts/rizos.yaml";
  # Decrypts tmx's home-manager secrets; tmx has no personal SSH key here.
  sops.secrets."users/tmx/age_key".owner = config.my.username;

  home-manager = {
    useGlobalPkgs = true;
    useUserPackages = true;
    backupFileExtension = "backup";
    extraSpecialArgs = { inherit inputs outputs configLib; };
  };
  # Agent Vault, Executor and T3 Code are user services; run them without a login.
  users.users.${config.my.username}.linger = true;

  # Root decrypts the proxy's keys with the master key, not tmx's SSH key.
  services.cli-proxy-api.sshKeyFile = config.my.networking.sshMasterKeyPath;
  # Its configuration is a Stow-managed file.
  systemd.services.cli-proxy-api = {
    wants = [ "dotfiles-bootstrap.service" ];
    after = [ "dotfiles-bootstrap.service" ];
  };

  services.nginx.virtualHosts = lib.mapAttrs' (
    name: port:
    lib.nameValuePair "${config.my.services.${name}.subdomain}.${config.my.server.location}.${config.my.domain}" {
      useACMEHost = "${config.my.server.location}.${config.my.domain}";
      addSSL = true;
      locations."/" = {
        proxyPass = "http://127.0.0.1:${toString port}";
        proxyWebsockets = true;
        recommendedProxySettings = true;
        # Stream model responses and MCP events, and allow large prompts and uploads.
        extraConfig = ''
          proxy_buffering off;
          proxy_read_timeout 1h;
          client_max_body_size 0;
        '';
      };
    }
  ) proxied;
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
