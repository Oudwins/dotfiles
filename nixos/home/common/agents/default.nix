{ config, pkgs, lib, ... }@args: {
  imports = [ ];
  # We don't install opencode, claude code or codex here because these packages are updated a lot so would prefer to just install manually

  home.packages = with pkgs;
    [
      # Opencode for code linting
      typescript-language-server
    ];
}
