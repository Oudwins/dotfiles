{ pkgs, ... }:
let
  rootTubbyPublicKey =
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIJNhigdDgF7oXpXvhZANuO/Y31g1ViCUCOFQz2PDAtpW tm@tristanmayo.com";
in {
  systemd.tmpfiles.rules = [ "d /root/.ssh 0700 root root -" ];

  sops.secrets."ssh/root/private" = {
    owner = "root";
    mode = "0600";
    path = "/root/.ssh/id_ed25519";
  };

  system.activationScripts.rootTubbyPublicKey.text = ''
    install -d -m 0700 /root/.ssh
    install -m 0644 -o root -g root ${
      pkgs.writeText "id_ed25519.pub" rootTubbyPublicKey
    } /root/.ssh/id_ed25519.pub
  '';
}
