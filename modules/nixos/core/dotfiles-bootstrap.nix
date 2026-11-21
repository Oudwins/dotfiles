# Clones this repo to ~/dotfiles when missing and runs updateSymlinks.sh at
# boot, so a reinstalled host gets its Stow-managed configuration without a
# manual step. An existing checkout is never pulled. Services that read the
# linked files order themselves after dotfiles-bootstrap.service; the user's
# own services (e.g. Agent Vault) start after it through user@.service.
{ config, pkgs, ... }:

let
  user = config.users.users.${config.my.username};
  directory = "${user.home}/dotfiles";
  bootstrap = pkgs.writeShellApplication {
    name = "dotfiles-bootstrap";
    # updateSymlinks.sh runs `/usr/bin/env bash`.
    runtimeInputs = with pkgs; [
      bash
      git
      stow
      perl
      python3
      findutils
      coreutils
    ];
    # HTTPS: the repo is public and the host may have no GitHub SSH key.
    text = ''
      if [ ! -e ${directory} ]; then
        git clone https://github.com/Oudwins/dotfiles.git ${directory}
      fi
      # In a fresh home Stow would otherwise link whole directories such as
      # ~/.config into the repo, so everything written there would land in it.
      exec ${directory}/updateSymlinks.sh --no-folding
    '';
  };
in
{
  systemd.services.dotfiles-bootstrap = {
    description = "Clone dotfiles and link the Stow-managed files";
    wants = [ "network-online.target" ];
    # Home Manager creates its files first, as on a workstation.
    after = [
      "network-online.target"
      "home-manager-${user.name}.service"
    ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      Type = "oneshot";
      User = user.name;
      Group = user.group;
      ExecStart = "${bootstrap}/bin/dotfiles-bootstrap";
      Restart = "on-failure";
      RestartSec = 30;
    };
  };

  systemd.services."user@".after = [ "dotfiles-bootstrap.service" ];
}
