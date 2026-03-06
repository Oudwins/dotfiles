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
    projectDirs = [ "Documents" "Documents2" ".droner/worktrees" ];
  in {
    OPENCODE_CONFIG = "${home}/.config/opencode/opencode.jsonc";
    OPENCODE_CONFIG_DIR = "${home}/.config/opencode";
    # Opencode vertex ai
    GOOGLE_CLOUD_PROJECT = "xi-playground";
    GOOGLE_APPLICATION_CREDENTIALS =
      "/Users/tmx/.config/gcloud/application_default_credentials.json";
    VERTEX_LOCATION = "us-east5";
    # CLAUDE CODE + VERTEX AI
    CLAUDE_CODE_USE_VERTEX = 1;
    CLOUD_ML_REGION = "us-east5";
    ANTHROPIC_VERTEX_PROJECT_ID = "xi-playground";
    # TERMINAL = "alacritty";
    EDITOR = "nvim";
    # this creates a string of "/home/tmx/projects:/home/tmx/{other_project_dir}"
    # This is used by a rofi script to open the code editor in that project
    CODE_PROJECTS_PARENT_DIRS =
      builtins.concatStringsSep ":" (map (dir: "${home}/${dir}") projectDirs);
    CODE_PROJECTS = "";
  };

  # Let Home Manager install and manage itself.
  programs.home-manager.enable = true;
}
