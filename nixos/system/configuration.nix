# Edit this configuration file to define what should be installed on
# your system.  Help is available in the configuration.nix(5) man page
# and in the NixOS manual (accessible by running ‘nixos-help’).

{ config, pkgs, ... }@args:

{
  imports = [
    ../hosts/nixos
    # tutorial -> https://www.youtube.com/watch?v=UPWkQ3LUDOU
    args.inputs.xremap-flake.nixosModules.default # makes remap service available
    args.inputs.sops-nix.nixosModules.sops
    ./../modules/common/base
    ./../modules/common/sops
    ./../modules/common/agents
    ./../modules/nixos/users/tmx
    ./../modules/nixos/base
    ./../modules/nixos/desktop
    ./../modules/nixos/services
    ./../modules/nixos/virtualization
    ./../modules/nixos/filesystems
    # ../hosts/tmx/pkgs/nvim/katana.nix
  ];

  # Bootloader.
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;
  # IDK WHAT THIS DOES, FOR WORK PROGRAM TO CONNECT TO COMMAND LINE
  boot.kernelParams = [ "console=ttyS0,115200" "console=tty1" ];

  networking.hostName = "nixos"; # Define your hostname.
  # networking.extraHosts = ''
  #   ${builtins.readFile ./../hosts-file}
  # '';
  # networking.wireless.enable = true;  # Enables wireless support via wpa_supplicant.

  # Configure network proxy if necessary
  # networking.proxy.default = "http://user:password@proxy:port/";
  # networking.proxy.noProxy = "127.0.0.1,localhost,internal.domain";

  # Key remapping. Only available because of xremap import above (see imports)
  # services.xremap = {
  #   enable = true;
  #   withX11 = true;
  #   watch = true; # watches for new devices that connect
  #   userName = "tmx";
  #   yamlConfig = ''
  #     modmap:
  #       - name: CapsLock to Esc
  #         remap:
  #           CapsLock: Esc
  #   '';
  # };

  # List packages installed in system profile. To search, run:
  # $ nix search wget
  environment.systemPackages = with pkgs; [
    vim # Do not forget to add an editor to edit configuration.nix! The Nano editor is also installed by default.
    wget
  ];

  services.openssh = {
    enable = true;
    openFirewall = true;
    ports = [ 5555 ];
    settings = {
      PasswordAuthentication = false;
      KbdInteractiveAuthentication = false;
      PermitRootLogin = "no";
      AllowUsers = [ "tmx" ];
    };
  };
  services.fail2ban.enable = true;
  services.endlessh = {
    enable = true;
    port = 22;
    openFirewall = true;
  };

  # Open ports in the firewall.
  networking.firewall = {
    # allowedTCPPorts = [
    #   42000
    #   42001
    # ];
    # allowedUDPPorts = [
    #   5353
    # ];
  };
  #networking.firewall.allowedTCPPorts = [ ... ];
  # networking.firewall.allowedUDPPorts = [ ... ];
  # Or disable the firewall altogether.
  # networking.firewall.enable = false;

  # This value determines the NixOS release from which the default
  # settings for stateful data, like file locations and database versions
  # on your system were taken. It‘s perfectly fine and recommended to leave
  # this value at the release version of the first install of this system.
  # Before changing this value read the documentation for this option
  # (e.g. man configuration.nix or on https://nixos.org/nixos/options.html).
  system.stateVersion = "23.11"; # Did you read the comment?
}
