{ pkgs, ... }:
let
  google-cloud = pkgs.google-cloud-sdk.withExtraComponents [
    pkgs.google-cloud-sdk.components.gke-gcloud-auth-plugin
    pkgs.google-cloud-sdk.components.kubectl
  ];
in
{
  environment.systemPackages = with pkgs; [
    vim
    neovim
    direnv
    sshs
    carapace
    firefox
    google-chrome
    stow
    colima
    bun
    jq
    csvkit
    google-cloud
    python314
    terraform
  ];
}
