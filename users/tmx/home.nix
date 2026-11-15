# tmx's home-manager settings shared by every host that gives tmx a home.
# Hosts add platform modules and host-only tweaks in hosts/<name>/home.nix.
{ configLib, ... }:

{
  home.stateVersion = "23.11"; # Please read the comment before changing.

  sops.defaultSopsFile = configLib.secretFile "sops/users/tmx.yaml";
}
