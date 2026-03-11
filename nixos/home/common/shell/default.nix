{ config, ... }:

{
  programs.bash = {
    enable = true;
    bashrcExtra = ''
      ## set bash to vi mode
      set -o vi
      ## ensure ctl + l is bound to clear screen
      bind '"\C-l": clear-screen'
      #####
      ## tmux sessionizer
      ####
      tmux_sessionizer_widget() {
        "${config.home.homeDirectory}/dotfiles/scripts/tmux-sessionizer.sh"
      }
      bind -x '"\eo":tmux_sessionizer_widget'
      # Adds go to path
      export PATH="$PATH:${config.home.homeDirectory}/go/bin:${config.home.homeDirectory}/.npm/bin"

      # This allows tldr to load from nvim always
      tldrv() {
        # if nvim isn't available fall back to the real tldr output
        if ! command -v nvim >/dev/null 2>&1; then
          command tldr "$@"
          return
        fi

        # Use the real tldr (avoid recursion), pipe into nvim reading stdin
        command tldr "$@" | nvim -R -c 'set ft=markdown' -
      }
    '';
  };

  programs.zsh = {
    enable = true;
    initContent = ''
      ## set zsh to vi mode
      set -o vi
      ## ensure ctl + l is bound to clear screen
      bindkey '^L' clear-screen
      ####
      ## tmux sessionizer
      ####
      tmux_sessionizer_widget() {
        zle -I
        "${config.home.homeDirectory}/dotfiles/scripts/tmux-sessionizer.sh"
        zle reset-prompt
      }
      zle -N tmux_sessionizer_widget
      bindkey '^[o' tmux_sessionizer_widget
      # Adds go to path
      export PATH="$PATH:${config.home.homeDirectory}/go/bin:${config.home.homeDirectory}/.npm/bin"

      # This allows tldr to load from nvim always
      tldrv() {
        # if nvim isn't available fall back to the real tldr output
        if ! command -v nvim >/dev/null 2>&1; then
          command tldr "$@"
          return
        fi

        # Use the real tldr (avoid recursion), pipe into nvim reading stdin
        command tldr "$@" | nvim -R -c 'set ft=markdown' -
      }
    '';
  };

  programs.direnv = {
    enable = true;
    nix-direnv.enable = true;
  };

  programs.starship = { enable = true; };
}
