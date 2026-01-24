{ lib, ... }:

{
  # Darwin-specific zsh settings (merged with common shell config)
  programs.zsh.initContent = lib.mkAfter ''
    # Darwin-specific: prepend npm to PATH for priority
    export PATH="$HOME/.npm/bin:$PATH"
  '';
}
