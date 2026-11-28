{ config, lib, pkgs, inputs, outputs, configLib, ... }:

{
  imports = [
    inputs.home-manager-darwin.darwinModules.home-manager
    inputs.nix-homebrew.darwinModules.nix-homebrew
    ./home.nix
    ../../modules/darwin
    ../../roles/agents.nix
    # ./config-files/aerospace.nix
  ];
  # services.aerospace.enable = false;

  services.cli-proxy-api.secretsFile = configLib.secretFile "sops/shared/cli-proxy-api-work.yaml";
  services.cli-proxy-api.configFile = "${config.users.users.${config.my.username}.home}/.cli-proxy-api/work.yaml";

  home-manager = {
    useGlobalPkgs = true;
    useUserPackages = true;
    extraSpecialArgs = { inherit inputs outputs configLib; };
  };

  nix-homebrew = {
    user = config.my.username;
    enable = true;
    enableRosetta = true;
    taps = {
      "homebrew/homebrew-core" = inputs.homebrew-core;
      "homebrew/homebrew-cask" = inputs.homebrew-cask;
      "homebrew/homebrew-bundle" = inputs.homebrew-bundle;
      "typesense/homebrew-tap" = inputs.homebrew-typesense;
      "ngrok/homebrew-ngrok" = inputs.homebrew-ngrok;
      "mongodb/homebrew-brew" = inputs.homebrew-mongodb;
    };
    mutableTaps = true;
    autoMigrate = true;
  };

  users.users.${config.my.username}.home = "/Users/${config.my.username}";
  home-manager.backupFileExtension = "backup";
  system.stateVersion = 6;
  system.primaryUser = config.my.username;
}
