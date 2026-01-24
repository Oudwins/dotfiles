{ ... }:

{
  programs.zsh = {
    enable = true;
    initContent = ''
      export PATH="$HOME/.npm/bin:$PATH"
    '';
  };
}
