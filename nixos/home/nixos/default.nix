{ pkgs, ... }:

{
  imports = [
    ../common
    ./desktop
    ./packages
    ./services
  ];

  programs.git = {
    package = pkgs.git.override { withLibsecret = true; };
    settings.credential.helper = "libsecret";
  };
}
