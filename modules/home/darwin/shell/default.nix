{ config, lib, ... }:

{
  home.sessionVariables.NPM_CONFIG_PREFIX = "${config.home.homeDirectory}/.npm";

  # Darwin-specific zsh settings
  # Use envExtra for PATH modifications - this goes in .zshenv which is read by ALL shells
  programs.zsh.envExtra = ''
    # Darwin-specific: prepend npm and golang to PATH
    export PATH="$HOME/.npm/bin:$HOME/go/bin:$PATH"
  '';
}
