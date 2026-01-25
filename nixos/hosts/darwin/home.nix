{ config, pkgs, lib, ... }@args: {
  imports = [ ../../home/darwin ];
  home.username = "tmx";
  home.homeDirectory = "/Users/tmx";

  # This value determines the Home Manager release that your configuration is
  # compatible with. This helps avoid breakage when a new Home Manager release
  # introduces backwards incompatible changes.
  #
  # You should not change this value, even if you update Home Manager. If you do
  # want to update the value, then make sure to first check the Home Manager
  # release notes.
  home.stateVersion = "23.11"; # Please read the comment before changing.

  home.sessionVariables = let
    home = config.home.homeDirectory;
    projectDirs = [ "open_source" "work" "personal" "projects" ];
    obsidianDirs = [ "notes" ];
  in {
    XDG_CONFIG_HOME = home;
    # CLAUDE CODE + VERTEX AI
    CLAUDE_CODE_USE_VERTEX = 1;
    CLOUD_ML_REGION = "us-east5";
    ANTHROPIC_VERTEX_PROJECT_ID = "xi-playground";
    # TERMINAL = "alacritty";
    EDITOR = "nvim";
    # CODE_EDITOR = "nvim";
    # this creates a string of "/home/tmx/projects:/home/tmx/{other_project_dir}"
    # This is used by a rofi script to open the code editor in that project
    # CODE_PROJECT_DIRS = builtins.concatStringsSep ":" (map (dir: "${home}/${dir}") projectDirs);
    # OBSIDIAN_VAULT_DIRS = builtins.concatStringsSep ":" (map (dir: "${home}/${dir}") obsidianDirs);
    # LAUNCHER = "rofi -show drun";
    # DMENU = "rofi -dmenu";
    # SCREENSHOT = "flameshot gui";
    # temporary fix for qbittorrent
  };

  # Let Home Manager install and manage itself.
  programs.home-manager.enable = true;
}
