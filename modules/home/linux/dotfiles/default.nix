# Clones this repo to ~/dotfiles when missing and runs updateSymlinks.sh on
# every start of the user manager, so a reinstalled host gets its Stow-managed
# configuration without a manual step. An existing checkout is never pulled.
{ config, pkgs, ... }:

let
  directory = "${config.home.homeDirectory}/dotfiles";
  bootstrap = pkgs.writeShellApplication {
    name = "dotfiles-bootstrap";
    runtimeInputs = with pkgs; [
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
  systemd.user.services.dotfiles-bootstrap = {
    Unit = {
      Description = "Clone dotfiles and link the Stow-managed files";
      # Agent Vault reads its configuration from the linked files.
      Before = [ "agent-vault.service" ];
    };
    Service = {
      Type = "oneshot";
      ExecStart = "${bootstrap}/bin/dotfiles-bootstrap";
      # The network may not be up when the user manager starts.
      Restart = "on-failure";
      RestartSec = 30;
    };
    Install.WantedBy = [ "default.target" ];
  };
}
