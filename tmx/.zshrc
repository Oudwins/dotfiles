typeset -U path cdpath fpath manpath
for profile in ${(z)NIX_PROFILES}; do
  fpath+=($profile/share/zsh/site-functions $profile/share/zsh/$ZSH_VERSION/functions $profile/share/zsh/vendor-completions)
done

HELPDIR="/nix/store/1qyfxzg1p1ggn727lh1ryi0zxvg2mrgj-zsh-5.9/share/zsh/$ZSH_VERSION/help"

autoload -U compinit && compinit
# History options should be set in .zshrc and after oh-my-zsh sourcing.
# See https://github.com/nix-community/home-manager/issues/177.
HISTSIZE="10000"
SAVEHIST="10000"

HISTFILE="$HOME/.zsh_history"
mkdir -p "$(dirname "$HISTFILE")"

setopt HIST_FCNTL_LOCK
unsetopt APPEND_HISTORY
setopt HIST_IGNORE_DUPS
unsetopt HIST_IGNORE_ALL_DUPS
unsetopt HIST_SAVE_NO_DUPS
unsetopt HIST_FIND_NO_DUPS
setopt HIST_IGNORE_SPACE
unsetopt HIST_EXPIRE_DUPS_FIRST
setopt SHARE_HISTORY
unsetopt EXTENDED_HISTORY


if [[ $TERM != "dumb" ]]; then
  eval "$(/nix/store/pn12pmvwsyb69pnmjhllbcwdwnyqj33v-starship-1.23.0/bin/starship init zsh)"
fi

eval "$(/nix/store/g8hmdwd25ddyrbni7whd255cq7i6kk48-direnv-2.36.0/bin/direnv hook zsh)"

export PATH="$HOME/.npm/bin:$PATH"