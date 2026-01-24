{ ... }:

{
  # NixOS-specific base settings

  nixpkgs.config.permittedInsecurePackages = [
    "beekeeper-studio-5.3.4"
    "dotnet-sdk-6.0.428"
    "dotnet-runtime-6.0.36"
  ];

  networking.networkmanager.enable = true;

  time.timeZone = "Europe/Madrid";
  i18n.defaultLocale = "en_US.UTF-8";
  i18n.extraLocaleSettings = {
    LC_ADDRESS = "es_ES.UTF-8";
    LC_IDENTIFICATION = "es_ES.UTF-8";
    LC_MEASUREMENT = "es_ES.UTF-8";
    LC_MONETARY = "es_ES.UTF-8";
    LC_NAME = "es_ES.UTF-8";
    LC_NUMERIC = "es_ES.UTF-8";
    LC_PAPER = "es_ES.UTF-8";
    LC_TELEPHONE = "es_ES.UTF-8";
    LC_TIME = "es_ES.UTF-8";
  };

  services.journald.extraConfig = "SystemMaxUse=1G";

  nix.gc = {
    automatic = true;
    dates = "weekly";
    options = "--delete-older-than +5";
    randomizedDelaySec = "10min";
  };
  nix.settings.auto-optimise-store = true;
}
