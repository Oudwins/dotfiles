{
  config,
  pkgs,
  lib,
  inputs,
  ...
}@args:

let
  # see: https://github.com/NixOS/nixpkgs/blob/fe2ecaf706a5907b5e54d979fbde4924d84b65fc/pkgs/misc/tmux-plugins/default.nix#L15
  # See: https://haseebmajid.dev/posts/2023-07-10-setting-up-tmux-with-nix-home-manager/
  tmux-super-fingers = pkgs.tmuxPlugins.mkTmuxPlugin {
    pluginName = "tmux-super-fingers";
    version = "unstable-2023-01-06";
    src = pkgs.fetchFromGitHub {
      owner = "artemave";
      repo = "tmux_super_fingers";
      rev = "2c12044984124e74e21a5a87d00f844083e4bdf7";
      sha256 = "sha256-cPZCV8xk9QpU49/7H8iGhQYK6JwWjviL29eWabuqruc=";
    };
  };

  home = config.home.homeDirectory;
  projectParentDirs = [
    "open_source"
    "work"
    "personal"
    "projects"
    ".config"
    "Documents"
    ".local/share/droner"
  ];

  projectParentDirsStr = builtins.concatStringsSep "," (
    map (dir: "${home}/${dir}") projectParentDirs
  );
in
{
  # required by sessionx plugin
  home.packages = with pkgs; [
    fzf
    bat
  ];

  programs.tmux = {
    enable = true;
    terminal = "tmux-256color";
    historyLimit = 100000;
    plugins = [
      pkgs.tmuxPlugins.sensible
      {
        plugin = pkgs.tmuxPlugins.vim-tmux-navigator;
        extraConfig = ''
          # sets <leader>C-l to clear terminal
          bind C-l send-keys 'C-l'
        '';
      }
      pkgs.tmuxPlugins.tokyo-night-tmux
      pkgs.tmuxPlugins.yank
      pkgs.tmuxPlugins.resurrect
      pkgs.tmuxPlugins.continuum
      {
        plugin = inputs.tmux-sessionx.packages.${pkgs.system}.default;
        extraConfig = ''
          set -g @sessionx-custom-paths '${projectParentDirsStr}'
          set -g @sessionx-custom-paths-subdirectories 'true'
          set -g @sessionx-fzf-builtin-tmux 'on'
          set -g @sessionx-bind 'o'
          set -g @sessionx-fzf-builtin-tmux 'off'
        '';
      }
    ];
    extraConfig = ''
      # allows mouse support
      set -g mouse on
      # integrates clipboard
      set -s set-clipboard on
      ###
      # Key Bindings
      ###
      # Sets alt+{n} for switching windows
      bind-key -n M-1 select-window -t :1
      bind-key -n M-2 select-window -t :2
      bind-key -n M-3 select-window -t :3
      bind-key -n M-4 select-window -t :4
      bind-key -n M-5 select-window -t :5
      bind-key -n M-6 select-window -t :6
      bind-key -n M-7 select-window -t :7
      bind-key -n M-8 select-window -t :8
      # configures moving between windows with prefix + {hl}
      bind-key -T prefix h previous-window
      bind-key -T prefix l next-window
      # Start windows and panes at 1, not 0
      set -g base-index 1
      set -g pane-base-index 1
      set-window-option -g pane-base-index 1
      set-option -g renumber-windows on
      # Stay in CWD on split
      bind '"' split-window -v -c "#{pane_current_path}"
      bind % split-window -h -c "#{pane_current_path}"
      # set <leader>r to reload config
      unbind R
      bind R source-file ~/.config/tmux/tmux.conf \; display-message "Config reloaded..."
      # set <leader>n to create droner job
      bind a run-shell "~/.config/tmux/droner-create.sh"

      ###
      # Plugin Key Bindings
      ###
      # YANK Plugin key bindings
      bind-key -T copy-mode-vi v send-keys -X begin-selection
      bind-key -T copy-mode-vi C-v send-keys -X rectangle-toggle
      bind-key -T copy-mode-vi y send-keys -X copy-selection-and-cancel
    '';
  };
}
