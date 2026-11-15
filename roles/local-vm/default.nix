{
  config,
  pkgs,
  configLib,
  lib,
  inputs,
  ...
}@args:

{

  imports = [
    # Disk
    inputs.disko.nixosModules.disko
    (configLib.relativeToRoot "modules/nixos/hardware/disko/simpleDisko.nix")
    {
      _module.args = {
        disk = "/dev/vda";
        inherit lib;
        specialArgs = args;
      };
    }
  ];

  # VIRTUALIZATION SPECIFIC SETTINGS
  services.spice-vdagentd.enable = true;

  # Bootloader.
  boot.loader.grub = {
    enable = true;
    useOSProber = true;
    efiSupport = true;
    efiInstallAsRemovable = true;
  };

  # Enable networking
  networking.networkmanager.enable = true;

  # Enable the X11 windowing system.
  services.xserver.enable = true;

  # Enable the XFCE Desktop Environment.
  services.xserver.displayManager.lightdm.enable = true;
  services.xserver.desktopManager.xfce.enable = true;

  # Configure keymap in X11
  services.xserver = {
    layout = "us";
    xkbVariant = "";
  };

  # List packages installed in system profile. To search, run:
  # $ nix search wget
  environment.systemPackages = with pkgs; [
    vim
    neovim
    git
    firefox
    sqlite
    # beekeeper-studio
    openssl
  ];

  # Enable the OpenSSH daemon.
  # ENABLE CONNECTIONS EASY. THIS IS VERY INSECURE. DO NOT USE IN PRODUCTION.
  services.openssh = {
    enable = true;
    settings = {
      PermitRootLogin = lib.mkDefault "yes";
      PasswordAuthentication = lib.mkDefault true;
    };
  };
  networking.firewall.enable = lib.mkDefault false;
}
