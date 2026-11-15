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

  home-manager = {
    useGlobalPkgs = true;
    useUserPackages = true;
    extraSpecialArgs = { inherit inputs outputs configLib; };
  };

  nix-homebrew = {
    user = "tmx";
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

  users.users.tmx.home = "/Users/tmx";
  home-manager.backupFileExtension = "backup";
  system.stateVersion = 6;
  system.primaryUser = "tmx";
}
