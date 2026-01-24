{ ... }:

{
  imports = [
    ../../modules/darwin
    # ./config-files/aerospace.nix
  ];
  # services.aerospace.enable = false;

  users.users.tmx.home = "/Users/tmx";
  home-manager.backupFileExtension = "backup";
  system.stateVersion = 6;
  system.primaryUser = "tmx";
}
